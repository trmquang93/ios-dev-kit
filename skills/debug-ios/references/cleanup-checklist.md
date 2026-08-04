# Post-Debug Cleanup Checklist

Run this **only after** the user confirms the fix on device (fresh install + happy path). Do not clean up while the bug is still open.

---

## Gate: confirm before deleting

Ask or verify:

- [ ] User reproduced the **fixed** behavior on a real device
- [ ] Unit tests pass with the production fix in place
- [ ] No open questions in the latest `[FeatureDebug]` log paste

If any item is unchecked, keep instrumentation.

---

## Remove (temporary debug instrumentation)

| Artifact | Action |
|----------|--------|
| `FeatureDebugLog.swift` (or `TalkToMeDebugLog.swift`) | **Delete** if only used for this investigation |
| `TalkToMeDebugLog.log()` calls in ViewModels / Services | **Remove every call** |
| `flushToConsole()` calls | **Remove** |
| `hypothesisId` parameters and comments | **Remove** |
| `#region agent log` blocks | **Remove** |
| Hardcoded Mac log paths (e.g. `.cursor/debug-*.log`) | **Remove** |
| `print("[FeatureDebug] …")` in production code | **Remove** |
| Verbose `os.Logger` per-event spam | **Remove** or reduce to error-only |
| Documents debug log file writes | **Remove** with the logger |
| `.cursor/debug-*.log` in repo | **Delete** if committed accidentally |

**Grep patterns** to find leftovers:

```bash
rg -n "DebugLog|FeatureDebug|TalkToMeDebug|hypothesisId|flushToConsole|#region agent log|debug-.*\.log" --glob '*.swift'
```

Re-run until zero hits in production targets (tests may still reference stubs — see below).

---

## Keep (permanent value from the debug session)

| Artifact | Why keep |
|----------|----------|
| **Production fix** (retry, prefetch, per-locale skip, VM cache, etc.) | The actual bug fix |
| **Injection seam** (`SpeechLocaleCataloging`, stub transcriber, etc.) | Enables tests without SDK |
| **Regression unit tests** (`*ColdStartDebugTests`, `*DebugTests`) | Prevent recurrence |
| **Test helpers** (`StubTranscriber`, `makeIsolatedDefaults`) | Shared test infra |

---

## Adapt tests after logger removal

Debug tests that assert on log strings must be refactored — **do not delete the tests**.

### Before (log-coupled)

```swift
let logs = FeatureDebugLog.readAll()
#expect(logs.contains("installAssets partial"))
#expect(logs.contains("skippedBcp47Ids"))
```

### After (behavior-coupled)

```swift
#expect(vm.permissionState == .granted)
#expect(vm.selectedLocales.map { $0.identifier(.bcp47) } == ["en-US"])
#expect(vm.hasConfirmedLanguages == true)
```

| Old log assertion | Replace with |
|-------------------|----------------|
| `"catalog poll"` + `count: 0` | `#expect(vm.availableLocales.isEmpty)` before hydrate; non-empty after |
| `"installAssets partial"` | `#expect(selectedLocales == ["en-US"])` after partial install |
| `"locale asset skipped"` | Stub returns subset; assert VM uses subset |
| `"hydrate left catalog empty"` | `#expect(permissionState == .unavailable)` on empty-catalog stub |

**Stub tests:** remove `FeatureDebugLog.log` from stubs; stubs should only drive behavior. Remove `FeatureDebugLog.reset()` / `readAll()` from tests.

---

## Shrink test-only exposure

If `hydrateAvailableLocalesAndReconcile()` was made `internal` only for tests:

- **Keep** if tests need it and it documents a real sub-step
- **Or** drive through public API (`onAppear` + stub catalog) and make the method `private` again

Prefer testing through public surface when the stub can simulate the full path.

---

## Verify after cleanup

1. **Grep** — no debug logger references in app target
2. **Build** — `ios-build-test` build.sh succeeds
3. **Tests** — all unit tests pass (including adapted regression tests)
4. **Diff review** — production diff contains only fix + seams + tests, no print/log noise

```bash
cd /path/to/project
~/.claude/skills/ios-build-test/scripts/build.sh --scheme "<scheme>"
~/.claude/skills/ios-build-test/scripts/run_tests.sh --scheme "<scheme>" unit
```

5. **Optional device smoke** — user confirms one more run without debug noise in console

---

## What NOT to do

- Do not remove injection protocols to "simplify" — they are the test seam
- Do not remove regression tests because logs are gone — refactor assertions first
- Do not leave `TalkToMeDebugLog` in Release builds "just in case"
- Do not delete `.cursor/` rules or docs the user did not ask to change
- Do not revert the production fix while cleaning logs

---

## Optional: retain minimal error logging

If the feature benefits from permanent diagnostics, keep **error-only** logging:

```swift
// OK to keep — errors only, no hypothesis IDs, no per-poll spam
logger.error("installAssets failed: \(error.localizedDescription, privacy: .public)")
```

Gate behind `#if DEBUG` or use `os.Logger` at `.error` level only. Never keep high-volume JSON poll logs in production.