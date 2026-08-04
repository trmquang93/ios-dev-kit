---
name: debug-ios
description: Systematic iOS/SwiftUI bug debugging workflow — add structured debug logs, create deterministic unit-test repros with injection seams, run tests via ios-build-test, analyze device/simulator console output, fix root cause, verify, then remove temporary logs and debug code after user confirms fix. Use when user asks to debug iOS app, investigate device-only bugs, add debug logging, reproduce race conditions, clean up debug instrumentation, or says "debug-ios", "learn debug-ios", or shares [TalkToMeDebug]-style console logs.
argument-hint: [bug-description-or-feature-area]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# iOS Debug Skill

Structured workflow for debugging iOS/SwiftUI issues that reproduce on device but are hard to catch in simulator, or that involve async SDK races (Speech, AVFoundation, SwiftData, etc.).

**Arguments:** `$ARGUMENTS` — optional bug summary or feature area (e.g. `Talk to Me cold start`, `voice picker unavailable`).

**Depends on:** `ios-build-test` skill for all builds and tests — never run raw `xcodebuild`.

---

## Agent workflow (follow in order)

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

1. Unit tests pass (`ios-build-test`)
2. User confirms on **fresh device install**
3. Log shows happy path (e.g. `installAssets partial` + `prefetch succeeded` with pruned locales)

Ask explicitly: *"Fix confirmed on device — should I remove the debug logs and temporary instrumentation?"*

---

### 9. Clean up logs and debug code

**Mandatory after user confirms fix.** See [references/cleanup-checklist.md](references/cleanup-checklist.md).

#### Remove

- Debug logger file (`*DebugLog.swift`) and every `log()` / `flushToConsole()` call
- `print("[FeatureDebug] …")`, `hypothesisId` fields, `#region agent log` blocks
- Hardcoded log paths, Documents debug file writes, committed `.cursor/debug-*.log` files

#### Keep

- Production fix (retry, prefetch, partial install, VM cache, etc.)
- Injection seams (`*Cataloging` protocols, stub factories)
- Regression tests — **refactor** log assertions to behavior assertions (see cleanup doc)

#### Cleanup workflow

1. **Grep** for leftovers:
   ```bash
   rg -n "DebugLog|FeatureDebug|TalkToMeDebug|hypothesisId|flushToConsole|#region agent log" --glob '*.swift'
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

- [logging-pattern.md](references/logging-pattern.md) — Swift debug logger template (temporary; delete after fix)
- [test-repro-pattern.md](references/test-repro-pattern.md) — stub injection + test structure
- [cleanup-checklist.md](references/cleanup-checklist.md) — remove logs/debug code; keep fix + tests

## Related skills

- `ios-build-test` — build and test execution
- `ios-simulator` — simulator interaction when UI repro needed
- `apple-dev` — Apple API behavior questions