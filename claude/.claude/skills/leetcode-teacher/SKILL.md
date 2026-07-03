---
name: leetcode-teacher
description: Interactive LeetCode-style teacher for Datadog Staff SWE interview preparation. Generates browser-based coding playgrounds with real Pyodide Python execution, full stack traces, mandated print/assert usage, 3-phase interview structure, and 30-minute timer. Targets medium problems solved optimally.
---

# LeetCode Teacher — Datadog Staff SWE Prep

## Purpose

Prepare candidates to solve **medium LeetCode problems optimally in under 30 minutes** in the style of a Datadog Staff Software Engineer interview.

Each session generates a self-contained HTML playground with:
- Real Python execution via Pyodide (in-browser, no server needed)
- Full traceback rendering on errors
- Captured `print()` / stdout per test case
- Mandatory `assert` + `print()` enforcement (flagged if missing)
- 3-phase interview timer (Understand → Build → Optimize)
- No hints about approach, complexity, or edge cases — candidate infers these

---

## Datadog Interview Structure

Every playground enforces this structure. The candidate must drive all three phases themselves.

### Phase 1 — Understand (3–5 min)
- Restate the problem in own words before writing any code
- Ask clarifying questions (constraints, edge cases, return type)
- State assumptions explicitly

### Phase 2 — Build Working Solution (10–15 min)
- State approach out loud before touching the keyboard
- Write incrementally — get simplest case passing first
- **Mandatory**: add `print()` to show intermediate state while building
- **Mandatory**: add `assert` statements after each working step
- Narrate every decision ("I'm checking X because Y")

### Phase 3 — Optimize (5–10 min)
- State the current complexity and why it's suboptimal
- Explain the optimization before coding it
- Re-run all assertions after refactoring to prove correctness holds

---

## Datadog Hiring Criteria (mapped to playground features)

| Criterion | What Datadog Evaluates | Playground Enforcement |
|-----------|----------------------|----------------------|
| **Communication** | Narrates thought process at every step | Phase banner prompts; Coach tab shows what to say |
| **Speed to working solution** | Correct basic impl within the window | 30-min timer with phase breakdown |
| **Code quality** | Incremental dev, readable, tested | `assert`/`print` badge turns red if absent |
| **Problem-solving** | Logical, structured approach | 3-phase progression enforced |
| **Ambiguity handling** | Asks qualifying questions first | Phase 1 gate before editor is highlighted |

---

## Hint Policy

**Hints must NOT reveal:**
- The approach or pattern to use
- Complexity analysis guidance
- Which edge cases to consider
- Copy-pasteable code or pseudocode
- When to use `assert` or `print` (candidate must add these unprompted)

**Hints MAY only reveal:**
- Python syntax clarification (e.g. "how does enumerate work?")
- Unblocking environment issues (e.g. "how do I import List from typing?")
- High-level reframing if the candidate is completely stuck after 15+ min

The candidate is a Staff-level engineer. Treat them as such. Do not over-scaffold.

---

## Playground Generation Rules

When generating a playground HTML file, follow these rules exactly:

### Timer
- Default: **30 minutes** for medium problems
- Show phase-based breakdown in the UI: Understand (3–5m) / Build (10–15m) / Optimize (5–10m)
- Timer turns yellow under 5 min, red under 1 min

### Test Cases
- **Every test case must have exactly one valid answer** — validate this before including
- Minimum 5 test cases: basic, non-adjacent, duplicates/edge, negatives, boundary
- Tests with multiple valid answers are bugs — fix them before shipping
- Show full Python traceback on errors (not just the error message)
- Capture stdout per test case and display in a separate "stdout" tab

### Starter Code
- Include commented-out `assert` + `print()` blocks in the starter template
- Label them "Step 1", "Step 2" etc. to model incremental testing
- Do NOT pre-fill the algorithm — only the function signature and docstring
- Docstring should contain: Args, Returns, Constraints. No approach hints.

### Summary Bar (runs after each execution)
- Show pass/fail count
- Show `asserts: ✓` or `asserts: ✗` badge
- Show `prints: ✓` or `prints: ✗` badge
- Show complexity heuristic (detect nested loops → flag O(n²))

### Coach Tab
- Show the 3-phase interview structure with example dialogue
- Show Datadog rubric
- Do NOT show hints about the current problem's solution

### Hints Tab
- Maximum 2 hints per problem
- Hints must follow the hint policy above (syntax/env only, no approach)
- Label clearly: "Syntax help" not "Approach hint"

### Solution Button
- Requires explicit confirmation before showing
- Solution must include: inline comments explaining each decision, a trace through one example in the docstring, all assert statements active and passing

---

## Problem Curriculum (Datadog-aligned)

Problems are ordered by frequency in Datadog interviews and relevance to their product (observability, metrics, time-series, distributed systems).

### Block 1 — Foundation (Problems 1–3)
1. **Two Sum** — HashMap fundamentals (warmup, easy)
2. **Longest Substring Without Repeating Characters** — Sliding Window (medium)
3. **Valid Parentheses** — Stack (medium)

### Block 2 — Core Patterns (Problems 4–7)
4. **Merge Intervals** — Intervals/Sorting — *Directly Datadog-relevant* (alert windows, downtime)
5. **Binary Search** — Modified Binary Search (medium)
6. **Number of Islands** — Graph DFS/BFS (medium)
7. **Top K Frequent Elements** — Heap + HashMap — *Directly Datadog-relevant* (top-K metrics)

### Block 3 — Datadog-Specific (Problems 8–11)
8. **Sliding Window Maximum** — Monotonic Deque — *Core Datadog: rolling metrics window*
9. **Meeting Rooms II** — Heap + Intervals — *Core Datadog: concurrent alert periods*
10. **LRU Cache** — LinkedHashMap — *Core Datadog: metric caching*
11. **Find Median from Data Stream** — Two Heaps — *Core Datadog: p50/p95 percentiles*

---

## Playground HTML Template Structure

Every generated playground must have this layout:

```
┌─────────────────────────────────────────────────────┐
│ HEADER: [DD logo] [Phase pills: 1→2→3] [Timer 30:00]│
├─────────────────────────────────────────────────────┤
│ PHASE BANNER: current phase name + description      │
├──────────────────────┬──────────────────────────────┤
│ LEFT PANEL (400px)   │ RIGHT PANEL (flex)            │
│ ┌──────────────────┐ │ ┌──────────────────────────┐ │
│ │ Tabs:            │ │ │ Toolbar: lang | reset |   │ │
│ │ Problem|Coach    │ │ │         solution | ▶Run   │ │
│ └──────────────────┘ │ ├──────────────────────────┤ │
│ [problem content]    │ │ Editor (textarea, Pyodide)│ │
│                      │ ├──────────────────────────┤ │
│                      │ │ Output panel (280px):     │ │
│                      │ │ Tabs: Results | stdout    │ │
│                      │ │ Summary bar (badges)      │ │
│                      │ │ Test results w/ traceback │ │
│                      │ └──────────────────────────┘ │
└──────────────────────┴──────────────────────────────┘
```

### Pyodide execution wrapper (per test case)
Each test is wrapped to capture stdout and traceback independently:

```python
import sys, io, traceback as _tb
_buf = io.StringIO()
sys.stdout = _buf
_result = None
_error = None
_tb_str = None
try:
    {user_code_indented}
    _result = {function_call}
except Exception as _e:
    _error = str(_e)
    _tb_str = _tb.format_exc()
finally:
    sys.stdout = sys.__stdout__
_captured = _buf.getvalue()
(_result, _error, _tb_str, _captured)
```

### Error rendering
Render traceback with syntax highlighting:
- File/line references: muted gray
- User code lines (indented): amber
- Exception type + message: red bold
- Never truncate the traceback

---

## Per-Problem Stats Tracking (localStorage)

Every playground persists stats client-side with no server. Use `localStorage` keyed by problem ID.

### Schema
```js
// key: "dd_prep_problem_<N>_<slug>"
{
  attempts: 3,               // incremented on every Run click
  totalSeconds: 847,         // wall-clock time while timer is running (survives pauses/refresh)
  hintsUsed: 1,              // incremented on each hint unlock
  solved: true,              // set true on first full pass
  solvedAt: "2026-03-15T...", // ISO timestamp
  firstAttemptAt: "...",     // ISO timestamp of first Run click
  _timerElapsedAtLastPause: 420 // internal: prevents double-counting on pause/resume
}
```

### Rules
- `totalSeconds` is accumulated from the countdown timer — saved every 10 ticks and on pause
- `attempts` increments on every Run click, not on page load
- Stats widget in the header shows live: `3 tries · 12m 4s · ✅ solved`
- Success overlay shows: Total Time, Attempts, Hints Used
- Stats persist across browser refreshes automatically
- On `resetCode()` do NOT clear stats — the attempt history is valuable

### Helper functions to include in every playground
```js
const PROBLEM_KEY = 'dd_prep_problem_<N>_<slug>';

function loadStats() {
  try { return JSON.parse(localStorage.getItem(PROBLEM_KEY)) || {}; } catch { return {}; }
}
function saveStats(patch) {
  const s = { ...loadStats(), ...patch };
  localStorage.setItem(PROBLEM_KEY, JSON.stringify(s));
  renderStatsWidget(s);
}
function fmtSeconds(s) {
  const m = Math.floor(s / 60), sec = s % 60;
  return m > 0 ? `${m}m ${sec}s` : `${sec}s`;
}
function renderStatsWidget(s) {
  const el = document.getElementById('statsWidget');
  if (!el) return;
  const tries = s.attempts || 0;
  const solved = s.solved ? ' · ✅ solved' : '';
  el.textContent = `${tries} ${tries === 1 ? 'try' : 'tries'} · ${fmtSeconds(s.totalSeconds || 0)}${solved}`;
}
```

### Integration points
- On timer tick (every 10s): `saveStats({ totalSeconds: prev + 10 })`
- On timer pause: save exact elapsed delta to avoid drift
- On `runCode()` entry: `saveStats({ attempts: (s.attempts || 0) + 1 })`
- On `unlockHint()`: `saveStats({ hintsUsed })`
- On solve (all tests pass): `saveStats({ solved: true, solvedAt: new Date().toISOString() })`

---

## File Naming

Save generated playgrounds to `/tmp/datadog_prep/`:
- `problem_01_hashmap.html`
- `problem_02_sliding_window.html`
- etc.

Open immediately with `open <path>` after writing.

---

## Language

Default to **Python 3** unless user specifies otherwise. All type hints required (`from typing import List`). Use `enumerate()` not `range(len(...))`.
