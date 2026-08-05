---
name: debug-ios
description: Systematic iOS/SwiftUI bug debugging workflow — add structured debug logs, instrument layout with GeometryReader + NDJSON ingest, reproduce via agent-device or unit tests, analyze runtime evidence, fix root cause, verify with before/after logs, then remove temporary instrumentation. Use when user asks to debug iOS app, investigate layout jumps, device-only bugs, add debug logging, reproduce race conditions, clean up debug instrumentation, or says "debug-ios", "learn debug-ios", or shares [TalkToMeDebug]-style console logs.
argument-hint: [bug-description-or-feature-area]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# iOS Debug Skill

Structured workflow for debugging iOS/SwiftUI issues. Pick a **track** based on bug type:

| Track | Bug type | Primary evidence |
|-------|----------|------------------|
| **A — SDK / async** | Cold-start races, Speech/AVFoundation, permission flows | `[FeatureDebug]` console + unit-test stubs |
| **B — Layout / visual** | Jumping UI, resizing chrome, animation glitches | `GeometryReader` NDJSON logs + `globalMinY` comparison |

**Arguments:** `$ARGUMENTS` — optional bug summary or feature area (e.g. `Talk to Me cold start`, `bottom chrome jumps on mode select`).

**Depends on:**
- `ios-build-test` — all builds and tests; never run raw `xcodebuild`
- `agent-device` — simulator UI automation when agent should reproduce end-to-end

---

## Track B — Layout / visual bugs (SwiftUI)

Use when UI elements shift, jump, or resize on state change. Full pattern: [references/layout-debug-pattern.md](references/layout-debug-pattern.md).

### B1. Hypothesize (3–5 IDs)

Before reading code deeply, list layout hypotheses: variable sibling height (H1), parent `.animation` sliding chrome (H2), root animation re-layout (H3), `ZStack` height swap (H4), `matchedGeometryEffect`/transitions (H5).

### B2. Read view hierarchy

Trace: container (`VStack`/`ZStack`) → state driver → `.animation`/`.transition` on ancestors → `@ViewBuilder` branches with different intrinsic heights.

### B3. Instrument geometry (Cursor debug mode)

When session provides ingest endpoint + log path:

1. Add temporary `AgentDebugLog` (`#if DEBUG`, `#region agent log`) that **POSTs NDJSON** to the ingest URL — Simulator cannot write to Mac workspace paths
2. Attach `GeometryReader` backgrounds to:
   - Variable content area (height)
   - Tab bar / picker (`globalMinY` — key metric for vertical jump)
   - Outermost chrome container (total dock height + `globalMinY`)
3. Include `hypothesisId`, `runId` (`pre-fix` / `post-fix`), `location`, `message`, `data` in each payload
4. Cap ~6 log sites; map each to a hypothesis

See [references/layout-debug-pattern.md](references/layout-debug-pattern.md) for logger template and placement table.

### B4. Build + reproduce

```bash
cd /path/to/project
~/.cursor/plugins/cache/ios-dev-kit-marketplace/ios-dev-kit/6b2377b6c703a102bf3ba4f2e16165075b2a8216/skills/ios-build-test/scripts/build.sh --scheme "<scheme>"
```

**Agent repro (preferred when user says "run it yourself"):**

```bash
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }
SESSION="layout-debug"; UDID="<from ad devices>"

ad install ".derivedData/Build/Products/Debug-iphonesimulator/App.app" --platform ios --udid "$UDID"
ad open "com.bundle.id" --session "$SESSION" --platform ios --udid "$UDID" --relaunch
# Navigate + tap each state that triggers the jump; use --settle after each press
ad close --session "$SESSION"
```

**Before each run:** delete only your session log file (e.g. `.cursor/debug-<sessionId>.log`).

### B5. Analyze → confirm (never fix on code alone)

Read NDJSON log file. Mark each hypothesis CONFIRMED/REJECTED with cited values:

- `globalMinY` varying across taps → vertical jump confirmed
- Content `height` range (e.g. 52–92pt) → fixed slot needed
- Dock total height swing → ZStack or parent needs fixed frame

Build a before/after table for verification.

### B6. Fix surgically

Common layout fixes (apply only what logs support):

| Evidence | Fix |
|----------|-----|
| Variable action content height | `.frame(height: measuredMax, alignment: .top)` on content slot |
| ZStack swaps different heights | `.frame(height: measuredMax, alignment: .top)` on ZStack |
| Parent `.animation` slides chrome | Remove from `VStack`/root; scope animation to opacity transition only |
| Constants | Use **max height from pre-fix logs**, not guesses |

**Keep instrumentation in place.**

### B7. Verify with post-fix logs

1. Set `runId: "post-fix"` in logger
2. Delete log file → rebuild → reinstall → rerun same tap sequence
3. Confirm `globalMinY` and heights are stable across all states
4. Only then remove instrumentation (step 9)

---

## Track A — SDK / async bugs

For cold-start races, SDK partial init, device-only timing. Follow steps 1–9 below.

---

## Agent workflow — Track A (follow in order)

### 1. Lock repro steps

Before writing code, restate:

- **Steps to reproduce** (numbered, from user report)
- **Expected vs actual** behavior
- **Fresh install vs repeat** — does closing/reopening change behavior? (signals race, cache, or asset install)
- **Device vs simulator** — which environments differ?

Do not guess the root cause yet. List 2–4 hypotheses with IDs (`H1`, `H2`, …).

---

### 2. Read the flow end-to-end

Read before instrumenting:

- ViewModel + View state machine (what drives each UI state?)
- Coordinator / sheet presentation (VM recreated mid-flow?)
- Service layer (SDK calls, persistence)
- Existing tests and preview factories

Identify **test seams** — protocols or factories already used for stubs (`VoiceTranscribing`, `SpeechLocaleCataloging`, etc.).

---

### 3. Add structured debug logging

Create or extend a feature-scoped logger. See [references/logging-pattern.md](references/logging-pattern.md).

**Requirements:**

| Requirement | Why |
|-------------|-----|
| Prefix `[FeatureDebug]` on every `print()` | User can filter Xcode console and copy/paste |
| JSON-lines payload | Machine-parseable; one line = one event |
| In-memory buffer + file | Simulator tests read memory; device writes Documents |
| `flushToConsole()` on failure/dismiss | User gets full session dump to share |
| `hypothesisId` field | Maps log lines to hypotheses |
| `os.Logger` alongside print | Console.app filtering on device |

**Log at every state transition:** init/hydration, async SDK poll, permission result, install attempt, success/failure, UI-driving property changes.

**Do not** log secrets (API keys, tokens, PII transcripts in production builds unless user explicitly debugging that).

---

### 4. Add a deterministic unit-test repro

See [references/test-repro-pattern.md](references/test-repro-pattern.md).

- Inject a **stub catalog/service** that simulates the failure mode (empty-then-ready catalog, asset-not-found per locale, etc.)
- Test file naming: `{Feature}DebugTests.swift` or `{Feature}ColdStartDebugTests.swift`
- Test asserts on VM state **and** log content (`readAll().contains("…")`)
- Print log dump in test output for CI visibility

Run tests:

```bash
cd /path/to/project
~/.claude/skills/ios-build-test/scripts/run_tests.sh --scheme "<scheme>" unit
```

Never pipe test output. Wait for `🎉 All tests passed!` or failures.

---

### 5. Reproduce on device (user-assisted)

Tell user to:

1. Run **Debug** build from Xcode with device attached
2. Filter console on `[FeatureDebug]`
3. Reproduce once; copy lines between `—— session dump ——` markers (or all `[FeatureDebug]` lines)
4. Paste logs back

**Log locations on device:**

| Location | How to access |
|----------|---------------|
| Xcode console | Filter `[FeatureDebug]` while running |
| Console.app | Subsystem = bundle ID, category from `os.Logger` |
| App Documents | Xcode → Devices → Download Container → `AppData/Documents/*.log` |

---

### 6. Analyze logs → root cause

Common iOS debug patterns (check logs for these):

| Pattern | Typical cause | Fix direction |
|---------|---------------|---------------|
| SDK returns empty, then populated on retry | Cold-start race | Poll with backoff before proceeding |
| `isAvailable()` true but catalog empty | Partial SDK init | Don't gate on single check alone |
| Asset install fails for one locale | Model not downloadable on device | Per-locale install; skip failures; continue with rest |
| Works on second open only | VM recreated, assets cached, or prefs saved | Cache VM across sheet re-renders; prefetch assets |
| Sheet shows wrong state | `permissionState` flipped after sub-step failure | Separate preparing vs granted; safety-net empty checks in View |

Match log lines to hypotheses. **Confirm with evidence** before fixing.

---

### 7. Fix surgically

- Minimum code for the confirmed root cause
- Prefer **graceful degradation** (skip bad locale, retry transient SDK errors) over hard unavailable
- Update or add tests that fail on old behavior
- **Keep all debug logging in place** until step 8 is complete — do not clean up mid-investigation

---

### 8. Verify (gate before cleanup)

Do not proceed to step 9 until all pass:

**Track A (SDK):**
1. Unit tests pass (`ios-build-test`)
2. User confirms on **fresh device install**
3. Log shows happy path (e.g. `installAssets partial` + `prefetch succeeded` with pruned locales)

**Track B (layout):**
1. Build succeeds (`ios-build-test`)
2. Post-fix NDJSON logs show stable `globalMinY` / heights across all repro steps
3. Agent-device or user confirms visually (no jump)

Ask explicitly: *"Fix confirmed — should I remove the debug logs and temporary instrumentation?"*

---

### 9. Clean up logs and debug code

**Mandatory after user confirms fix.** See [references/cleanup-checklist.md](references/cleanup-checklist.md).

#### Remove

- Debug logger file (`*DebugLog.swift`, `AgentDebugLog`) and every `log()` / `flushToConsole()` call
- `print("[FeatureDebug] …")`, `hypothesisId` fields, `#region agent log` blocks
- `GeometryReader` backgrounds added only for debug logging
- Hardcoded log paths, Documents debug file writes, HTTP ingest URLs (`7329/ingest`), committed `.cursor/debug-*.log` files

#### Keep

- Production fix (retry, prefetch, partial install, VM cache, **fixed layout frames**, scoped animations, etc.)
- Injection seams (`*Cataloging` protocols, stub factories)
- Regression tests — **refactor** log assertions to behavior assertions (see cleanup doc)

#### Cleanup workflow

1. **Grep** for leftovers:
   ```bash
   rg -n "DebugLog|AgentDebugLog|FeatureDebug|TalkToMeDebug|hypothesisId|flushToConsole|#region agent log|7329/ingest" --glob '*.swift'
   ```
2. **Delete** logger + strip calls from ViewModels/Services
3. **Adapt tests** — replace `readAll().contains("…")` with state expectations
4. **Build + test** via `ios-build-test`
5. **Report** what was removed vs kept in the PR/summary

Do not remove injection protocols or regression tests to "simplify."

---

## Console copy template for user

When asking user for logs, include:

```
Filter Xcode console on: [FeatureDebug]
Reproduce the bug once, then copy every line starting with [FeatureDebug]
Paste them here.
```

---

## Reference docs

- [layout-debug-pattern.md](references/layout-debug-pattern.md) — **Track B:** GeometryReader instrumentation, NDJSON ingest, agent-device repro, layout fix patterns (fixed frames, scoped animations)
- [logging-pattern.md](references/logging-pattern.md) — **Track A:** Swift debug logger template (temporary; delete after fix)
- [test-repro-pattern.md](references/test-repro-pattern.md) — stub injection + test structure
- [cleanup-checklist.md](references/cleanup-checklist.md) — remove logs/debug code; keep fix + tests

## Related skills

- `ios-build-test` — build and test execution
- `agent-device` — simulator UI automation for layout repro and verification
- `apple-dev` — Apple API behavior questions