---
name: stackback-investigate
description: Investigate a Stackback boosted-cashback-rate complaint end to end via BigQuery — resolve the uid, pull quota_holds eligibility snapshots, rule out the CDC back-stamping artifact, check requirement 3 (active recurring buy/round-up) against planner's plan history at the relevant timestamp, check rate grants, and size blast radius. Executes bq queries directly (does not just hand back SQL). Use when someone reports "boosted Stackback rate not applied" / "getting base rate instead of boosted" and you have a uid, email, or Linear ticket to work from.
argument-hint: "<uid|email> [--from=<date>] [--to=<date>] [--fleet]"
---

# Stackback Boosted-Rate Investigation

**Command**: `/stackback-investigate <uid|email> [--from=YYYY-MM-DD] [--to=YYYY-MM-DD] [--fleet]`

Companion docs: `~/Downloads/stackback-engineering-sop.md` (this skill mechanizes it), `~/Downloads/stackback-care-sop.md` (non-technical version for Care), [Stackback Details – Internal Alignment (Notion)](https://app.notion.com/p/bitstack/Stackback-Details-Internal-Alignment-2f3dc08ba57c80d48b36c0c1292ef98b).

Audience: engineers/on-call with `bq` CLI access. This skill runs the queries itself via Bash — it does not just print SQL for someone else to paste.

---

## The model (read before interpreting any result)

Two independent conditions gate the boosted rate. **Both must hold, or the payout falls to base rate:**

1. **Tier** — resolved from total savings *executed in month M-1* (recurring buys + Bitstack Card round-ups + synced-card round-ups, summed). Same tier table, same inclusive thresholds every month.
2. **Active method today** — at least one **currently live** savings method: active recurring buy **and/or** active round-ups (Bitstack Card or synced external card — interchangeable, either satisfies it).

If #2 is false, rate is forced to base **regardless of tier**. A `tier_used.Rate` (boosted) vs `tier_rate` (base) mismatch in the data is the **expected signature of requirement 2 failing** — it is not automatically a bug. Most reports resolve at Step 4 below.

Code references (for when the decision tree bottoms out in "genuine bug, needs code-level debugging"):

| Function | File:line | Role |
|---|---|---|
| `payoutRate` | `lakshmi/internal/bank/cashback/service.go:209-215` | Only function that can pay less than the tier's own rate. `!activeMethod` → base rate; else grant-floor (raises only). |
| `hasActiveMethod` | `lakshmi/internal/bank/cashback/ingestor.go:291-306` | Requirement-2 check: `RECURRING`/`SMART_RECURRING`/`ROUNDUP`/`CARD_ROUNDUP`, not deleted, not paused, has `payment_method_id`. |
| `CalculateCashback` / `consumeQuota` | `service.go:426-523` / `service.go:639-744` | Authorization-time vs settlement-time computation. Settlement re-reads active-method state **live, at settlement time** — see Gotcha 6. |
| `effectiveRate` / grants | `lakshmi/internal/bank/cashback/grants.go:41-74` | Plus-subscription rate floor (`cashback.rate_grants`). Only raises, never lowers. |
| Tier table | `lakshmi/config/conf.libsonnet` (~L71-81) → `tiers.go:30-75` | Static config, not DB-backed. |

---

## Step 0: Parse arguments, hard-stop validation

- `<uid|email>` required unless `--fleet` is passed alone (fleet-wide sweep, no single user).
- If given an email, resolve to uid first (check `rpl_lakshmi_cloudsql_cashback.users` or ask the engineer for the uid if no resolution path is available — do not guess).
- `--from`/`--to` default to the last 30 days if omitted.
- **Hard stop** if no uid/email and no `--fleet`: ask for an identifier before running anything.

---

## Step 1: Pull latest eligibility snapshots

```bash
bq query --project_id=bitstack --use_legacy_sql=false --format=prettyjson '
WITH ranked AS (
  SELECT
    id, operation_id, amount, cashback_amount, status, created_at, sats_credited,
    eligibility_snapshot,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp DESC) AS rn
  FROM `bitstack.rpl_lakshmi_cloudsql_cashback.quota_holds`
  WHERE uid = "<UID>"
    AND created_at BETWEEN "<FROM>" AND "<TO>"
)
SELECT id, operation_id, amount, cashback_amount, status, created_at, sats_credited, eligibility_snapshot
FROM ranked WHERE rn = 1
ORDER BY created_at ASC'
```

Then extract the diagnostic fields (do this as a second query, not by hand-parsing the JSON text):

```bash
bq query --project_id=bitstack --use_legacy_sql=false --format=prettyjson '
WITH ranked AS (
  SELECT
    id, created_at, status,
    JSON_VALUE(eligibility_snapshot, "$.tier_rate")      AS tier_rate,
    JSON_VALUE(eligibility_snapshot, "$.tier_used.Rate")  AS tier_used_rate,
    JSON_VALUE(eligibility_snapshot, "$.tier_used.Level") AS tier_used_level,
    JSON_VALUE(eligibility_snapshot, "$.eligible")        AS eligible,
    JSON_VALUE(eligibility_snapshot, "$.is_grace_period") AS grace,
    JSON_VALUE(eligibility_snapshot, "$.rate_source")     AS rate_source,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp DESC) AS rn
  FROM `bitstack.rpl_lakshmi_cloudsql_cashback.quota_holds`
  WHERE uid = "<UID>" AND created_at BETWEEN "<FROM>" AND "<TO>"
)
SELECT * FROM ranked WHERE rn = 1 ORDER BY created_at ASC'
```

**If `tier_rate == tier_used_rate` for every row → not this issue.** Say so plainly and stop; point at MCC exclusion (`NoCashbackMCCs` in `cashback.go`) or transaction-not-eligible as the next thing to check, but don't chase those yourself — out of scope for this skill.

If any row diverges, continue to Step 2.

---

## Step 2: Rule out the CDC back-stamping artifact

**Do this before concluding anything about "when" the issue started.** Compare each divergent hold's FIRST vs LAST CDC-event version:

```bash
bq query --project_id=bitstack --use_legacy_sql=false --format=prettyjson '
WITH ranked AS (
  SELECT
    id, created_at, status,
    JSON_VALUE(eligibility_snapshot, "$.tier_rate") AS tier_rate,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp ASC)  AS rn_first,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp DESC) AS rn_last,
    COUNT(*) OVER (PARTITION BY id) AS n_versions
  FROM `bitstack.rpl_lakshmi_cloudsql_cashback.quota_holds`
  WHERE uid = "<UID>" AND created_at BETWEEN "<FROM>" AND "<TO>"
)
SELECT id, created_at, n_versions,
  MAX(IF(rn_first=1, tier_rate, NULL)) AS tier_rate_first,
  MAX(IF(rn_last=1,  tier_rate, NULL)) AS tier_rate_last
FROM ranked GROUP BY id, created_at, n_versions
ORDER BY created_at ASC'
```

Interpretation:
- `first == last`, both wrong → wrong from the moment of creation. Check active-method state **as of `created_at`** in Step 3.
- `first` correct, `last` wrong → recomputed after the fact. Settlement (`consumeQuota`) reads active-method state live at settlement time, not hold-creation time (Gotcha 6) — check active-method state **as of the settlement timestamp** (the hold's `updated_at`/consume time), not `created_at`.
- High `n_versions` (20-40+) alone is **not** suspicious — the reconciliation job runs every 4 hours and touches every open hold repeatedly. Only a *value change* across versions is signal.
- **Do not report an apparent "N-second regression window" between two nearby transactions without doing this check first** — a released hold (never revisited) next to a consumed hold (revisited later) can look like an instant flip when it's actually a multi-day settlement-lag artifact.

---

## Step 3: Check requirement 2 against planner ground truth, AT THE RELEVANT TIMESTAMP

**Do not use `cashback.users.total_planned`/`total_saved` as a proxy** — not the same signal `hasActiveMethod` reads. Query planner directly:

```bash
bq query --project_id=bitstack --use_legacy_sql=false --format=prettyjson '
WITH ranked AS (
  SELECT
    id, plan_type, payment_method_id, periodicity,
    created_at, updated_at, deleted_at, paused_until,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp DESC) AS rn
  FROM `bitstack.rpl_planner_public.plans`
  WHERE uid = "<UID>"
)
SELECT id, plan_type, payment_method_id, periodicity, created_at, updated_at, deleted_at, paused_until
FROM ranked WHERE rn = 1
ORDER BY created_at ASC'
```

A plan counts toward requirement 2 **only if**, at the evaluation timestamp `T` from Step 2 (created_at or settlement time, whichever applies):

- `plan_type IN ('RECURRING', 'SMART_RECURRING', 'ROUNDUP', 'CARD_ROUNDUP')`
- `created_at <= T`
- `deleted_at IS NULL OR deleted_at > T`
- `paused_until IS NULL OR paused_until < T`
- `payment_method_id IS NOT NULL AND payment_method_id != ''`

**Reconstruct state at `T` from the timestamps — do not just look at current `deleted_at` and assume it reflects the past.** A plan deleted last week was live a month ago.

**If no plan satisfies this at `T` → base rate is correct per spec, not a bug.** Report this as the finding and stop — this is the primary explanation for the large majority of reports. State clearly: "user had no active recurring buy or round-up as of `<T>`; base rate is expected per spec requirement 2."

---

## Step 4: Check grants (only if Step 3 clears the user, i.e. they DO have an active method and are still on base rate)

```bash
bq query --project_id=bitstack --use_legacy_sql=false --format=prettyjson '
SELECT uid, source, rate_bps, valid_until, created_at
FROM `bitstack.rpl_lakshmi_cloudsql_cashback.rate_grants`
WHERE uid = "<UID>"'
```

Grants only ever raise the rate. If the user has an active method (Step 3 passed) and is still on base rate, this is a **genuine bug** — report it with the Step 1-3 query outputs as evidence and stop. Do not attempt a code fix as part of this skill.

---

## Step 5: Fleet-wide blast radius (run when `--fleet` is passed, or when a single-user finding needs sizing)

```bash
bq query --project_id=bitstack --use_legacy_sql=false --format=prettyjson '
WITH ranked AS (
  SELECT
    uid, created_at,
    JSON_VALUE(eligibility_snapshot, "$.tier_rate")      AS tier_rate,
    JSON_VALUE(eligibility_snapshot, "$.tier_used.Rate") AS tier_used_rate,
    JSON_VALUE(eligibility_snapshot, "$.eligible")       AS eligible,
    JSON_VALUE(eligibility_snapshot, "$.is_grace_period") AS grace,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp ASC) AS rn
  FROM `bitstack.rpl_lakshmi_cloudsql_cashback.quota_holds`
  WHERE created_at BETWEEN "<FROM>" AND "<TO>"
)
SELECT DATE(created_at) AS day,
  COUNT(DISTINCT uid) AS affected_uids,
  COUNT(*) AS affected_holds
FROM ranked
WHERE rn = 1 AND eligible = "true" AND grace = "false" AND tier_rate != tier_used_rate
GROUP BY day ORDER BY day'
```

Use **first-version** (`rn` via `ASC`), not latest — sizing a regression's true onset needs "wrong from the moment it was computed," not muddied by later back-stamping.

---

## Known gotchas — apply these before drawing any conclusion

1. **A commit found via `git log --all` may never have shipped.** If a code/config timeline matters to the finding, verify ancestry: `git merge-base --is-ancestor <hash> origin/develop && echo yes || echo no` and `git branch --all --contains <hash>`. A PR can sit unmerged on a branch for days with a commit hash that predates when it actually deployed.
2. **`credit_history` (in `rpl_lakshmi_cloudsql_cashback`) is stale since 2026-01-27** — its CDC stream stopped and never resumed. Never use it to corroborate actual money credited/sats; `quota_holds.eligibility_snapshot` is the fresh source of truth for computed amounts.
3. **`cashback.boosts` is not the tier table.** Original tier-table schema was dropped 2026-01-29; current schema (since 2026-06-19) is unrelated Apple Pay one-time-boost tracking (`uid`, `operation_id`, `boost_kind`). The real tier table is static jsonnet config, not a DB table.
4. **`tier_used` vs `tier_rate` divergence is by design** — it's how the code represents "the tier says X, but a gate/floor changed what's actually paid." Always run Steps 3-4 before calling a divergence a regression.
5. **Reconciliation runs every 4 hours** and re-touches every open hold — 20-40+ CDC versions per hold is normal, not signal. Only a value change across versions matters (Step 2).
6. **Settlement (`consumeQuota`) reads active-method/flag state live, at settlement time — not at hold-creation time.** A hold created before a state change but settled after it reflects the *new* state. This is what makes two nearby transactions look like an instant flip when it's really a multi-day settlement-lag artifact (Step 2).
7. **All BigQuery tables here are append-only Datastream CDC replicas.** Every UPDATE on the source row lands as a new row sharing the same `id` — always dedupe with `ROW_NUMBER() OVER (PARTITION BY id ORDER BY datastream_metadata.source_timestamp DESC/ASC)`. Querying without this returns contradictory values for the same `id` and will misdirect the investigation.

---

## Decision tree

```
tier_rate == tier_used_rate (Step 1)?
├── yes → not this bug, check MCC exclusion / eligibility elsewhere. Stop.
└── no →
    first version == last version (Step 2)?
    ├── no (first correct, last wrong) → check active-method state AT SETTLEMENT time (Step 3)
    └── yes (wrong from creation) → check active-method state AT created_at (Step 3)
        no live plan at T?
        ├── yes (no active method) → EXPECTED (spec requirement 2). Report and stop.
        └── no (has active method) →
            live rate_grant exists and still isn't applied (Step 4)?
            ├── yes → genuine bug. Report with evidence, stop — do not attempt a fix here.
            └── no → escalate to service owner for code-level debugging. Report findings, stop.
```

---

## Output format

```
## Stackback Investigation — <uid> (<from> to <to>)

### Snapshot summary
- N holds checked, M divergent (tier_rate != tier_used_rate)

### Back-stamping check
- <first-vs-last version summary per divergent hold>

### Requirement-2 check (planner plan history)
- <plan(s) found / not found live at T, with dates>

### Grants check
<only if Step 4 ran>

### Verdict
<EXPECTED (requirement 2 / spec) | GENUINE BUG | INCONCLUSIVE — needs code-level debugging>

### Evidence
<raw query outputs backing the verdict>
```

## Execution notes

1. **Run the queries yourself via Bash `bq query`** — this skill is for engineers who can execute, unlike `xpollens-query` which only generates SQL for someone else to run.
2. **Never comment on the originating Linear ticket or touch its labels** — report findings in the terminal; let the requester relay/update Linear themselves.
3. **Don't skip Step 2** — it is the single most common source of a wrong onset-date conclusion in this investigation area.
4. **Stop at the first step that resolves it** — don't run Steps 4-5 if Step 3 already explains the report.
