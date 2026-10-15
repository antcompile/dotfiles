#!/usr/bin/env bash
#
# fix-poisoned-ci-runners.sh
#
# Scans every RUNNING instance in the staging CI runner MIG and repairs any box
# whose github-runner docker config holds a stale static Artifact Registry token
# (the `crane auth login -u oauth2accesstoken -p <1h-token>` poison). The fix
# removes only the static `auths` entry for the AR host, reverting the runner to
# clean ADC/metadata auth. credHelpers/credsStore, if present, are preserved.
#
# Usage:
#   ./fix-poisoned-ci-runners.sh            # scan + fix
#   ./fix-poisoned-ci-runners.sh --dry-run  # scan + report only, change nothing
#
set -euo pipefail

# ---- config -----------------------------------------------------------------
PROJECT="${PROJECT:-bitstack-test}"          # staging project
MIG="${MIG:-ci-runner-20260430}"
REGION="${REGION:-europe-west1}"
AR_HOST="${AR_HOST:-europe-west1-docker.pkg.dev}"
RUNNER_USER="${RUNNER_USER:-github-runner}"
CFG_PATH="/home/${RUNNER_USER}/.docker/config.json"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ---- colours ----------------------------------------------------------------
if [[ -t 1 ]]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; Z=$'\e[0m'; else R= G= Y= B= Z=; fi
say()  { printf '%s\n' "$*"; }
info() { printf '%s==>%s %s\n' "$B" "$Z" "$*"; }

# ---- 1. auth / login on staging --------------------------------------------
command -v gcloud >/dev/null 2>&1 || { say "${R}gcloud not found${Z}"; exit 1; }

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
  info "No active gcloud account — launching login"
  gcloud auth login
fi
ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
info "Authenticated as ${G}${ACCOUNT}${Z}, project ${G}${PROJECT}${Z}"
gcloud config set project "$PROJECT" >/dev/null 2>&1

# ---- 2. remote repair script (base64 to dodge all quoting) ------------------
# Emits one line: CLEAN:<reason> | FIXED:<what> | ERROR:<msg>
read -r -d '' REMOTE_PY <<PY || true
import json, os, sys
CFG = "${CFG_PATH}"
HOST = "${AR_HOST}"
DRY  = ${DRY_RUN}
if not os.path.exists(CFG):
    print("CLEAN:no-config"); sys.exit(0)
try:
    d = json.load(open(CFG))
except Exception as e:
    print("ERROR:unparseable:%s" % e); sys.exit(0)
auth = (d.get("auths", {}) or {}).get(HOST, {}).get("auth")
if not auth:
    print("CLEAN:no-static-token"); sys.exit(0)
# poisoned
if DRY:
    print("POISONED:would-fix"); sys.exit(0)
try:
    os.replace(CFG, CFG + ".poisoned.bak")
except Exception:
    pass
d.get("auths", {}).pop(HOST, None)
if not d.get("auths") and not d.get("credHelpers") and not d.get("credsStore"):
    print("FIXED:removed-file")
else:
    with open(CFG, "w") as f:
        json.dump(d, f, indent=2)
    os.chmod(CFG, 0o600)
    print("FIXED:removed-entry")
PY
REMOTE_B64="$(printf '%s' "$REMOTE_PY" | base64 | tr -d '\n')"
REMOTE_CMD="echo ${REMOTE_B64} | base64 -d | sudo python3 -"

# ---- 3. enumerate running runners ------------------------------------------
info "Listing RUNNING instances in ${MIG} (${REGION})"
ROWS=()
while IFS= read -r line; do [[ -n "$line" ]] && ROWS+=("$line"); done < <(gcloud compute instances list \
  --project="$PROJECT" \
  --filter="name~^${MIG}- AND status=RUNNING" \
  --format="value(name,zone.basename())" 2>/dev/null)

[[ ${#ROWS[@]} -gt 0 ]] || { say "${Y}No running runners found${Z}"; exit 0; }
say "Found ${#ROWS[@]} running runner(s). Mode: $([[ $DRY_RUN == 1 ]] && echo DRY-RUN || echo FIX)"
say ""

fixed=(); clean=(); poisoned=(); failed=()

# ---- 4. loop + repair -------------------------------------------------------
for row in "${ROWS[@]}"; do
  name="${row%%$'\t'*}"; zone="${row##*$'\t'}"
  printf '  %-28s (%s) ... ' "$name" "$zone"
  out="$(gcloud compute ssh "$name" \
          --project="$PROJECT" --zone="$zone" --tunnel-through-iap \
          --command="$REMOTE_CMD" 2>/dev/null | grep -E '^(CLEAN|FIXED|POISONED|ERROR):' | tail -1 || true)"
  case "$out" in
    FIXED:*)    say "${G}FIXED${Z} (${out#FIXED:})";         fixed+=("$name ($zone)") ;;
    POISONED:*) say "${Y}POISONED${Z} (dry-run, not changed)"; poisoned+=("$name ($zone)") ;;
    CLEAN:*)    say "${B}clean${Z} (${out#CLEAN:})";         clean+=("$name") ;;
    ERROR:*)    say "${R}error${Z} (${out#ERROR:})";         failed+=("$name ($zone): ${out#ERROR:}") ;;
    *)          say "${R}unreachable/ssh-failed${Z}";        failed+=("$name ($zone): ssh/no-output") ;;
  esac
done

# ---- 5. summary -------------------------------------------------------------
say ""
info "Summary"
if [[ $DRY_RUN == 1 ]]; then
  say "  ${Y}Would fix (${#poisoned[@]}):${Z}"; for m in "${poisoned[@]:-}"; do [[ -n "$m" ]] && say "    - $m"; done
else
  say "  ${G}Fixed (${#fixed[@]}):${Z}";        for m in "${fixed[@]:-}";    do [[ -n "$m" ]] && say "    - $m"; done
fi
say "  ${B}Already clean (${#clean[@]})${Z}"
if [[ ${#failed[@]} -gt 0 ]]; then
  say "  ${R}Failed (${#failed[@]}):${Z}";      for m in "${failed[@]}";     do say "    - $m"; done
fi

# exit non-zero if anything failed, so CI/cron can alert
[[ ${#failed[@]} -eq 0 ]]
