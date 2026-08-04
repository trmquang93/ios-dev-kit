# iOS Debug Test Repro Pattern

Deterministic unit tests for bugs that are flaky or device-only when hitting real SDKs.

## Structure

```
ProjectTests/
  FeatureColdStartDebugTests.swift   # repro + regression tests
  FeatureViewModelTests.swift        # existing behavior tests
```

## 1. Protocol seam (production)

Extract async SDK boundary into a protocol the ViewModel accepts via init:

```swift
protocol FeatureCataloging: Sendable {
    func loadData() async -> [Item]
    func prepare(items: [Item]) async throws -> [Item]
}

struct LiveFeatureCatalog: FeatureCataloging { /* real SDK */ }
```

Default to live implementation in production coordinator; inject stub in tests.

## 2. Stub that reproduces the bug

```swift
private final class ColdStartStubCatalog: FeatureCataloging, @unchecked Sendable {
    private var fetchCount = 0
    let emptyAttempts: Int

    func loadData() async -> [Item] {
        fetchCount += 1
        FeatureDebugLog.log("stub poll", data: ["count": fetchCount])
        return fetchCount <= emptyAttempts ? [] : fullCatalog
    }
}
```

**Repro tests to write:**

| Test | Simulates |
|------|-----------|
| `coldStartEmptyThenReady` | SDK race (empty → populated) |
| `immediateEmptyShowsUnavailable` | Old broken behavior (regression guard) |
| `partialSuccessSkipsFailures` | One locale/asset fails, others succeed |
| `totalFailureSurfacesError` | Zero successes → unavailable |

## 3. Test template

```swift
@MainActor
struct FeatureColdStartDebugTests {

    @Test func coldStartRepro() async {
        FeatureDebugLog.reset()

        let vm = FeatureViewModel(
            catalog: ColdStartStubCatalog(emptyAttempts: 2, ...),
            ...
        )

        await vm.hydrate()  // expose internal step for tests, or drive via onAppear

        #expect(vm.state == .ready)
        #expect(vm.items.count > 0)

        let logs = FeatureDebugLog.readAll()
        #expect(logs.contains("stub poll"))
        #expect(logs.contains("\"returnedCount\":0"))

        print("=== Feature debug log ===")
        print(logs)
    }
}
```

## 4. Run single suite

```bash
~/.claude/skills/ios-build-test/scripts/run_tests.sh --scheme "app" unit
```

For a single test struct, use:

```bash
~/.claude/skills/ios-build-test/scripts/run_tests.sh --scheme "app" single AppTests/FeatureColdStartDebugTests
```

## 5. Log assertions

Assert on log **content**, not just VM state — encodes *why* the fix matters:

```swift
#expect(logs.contains("installAssets partial"))
#expect(logs.contains("skippedBcp47Ids"))
#expect(!logs.contains("hydrate left catalog empty"))
```

## 6. Keep tests after fix — refactor, don't delete

Debug tests become **permanent regression tests**. When removing the debug logger (step 9):

| Remove from tests | Keep in tests |
|-------------------|---------------|
| `FeatureDebugLog.reset()` | Stub catalog injection |
| `FeatureDebugLog.readAll()` assertions | VM state `#expect`s |
| `print(logs)` dumps | Stub types (`ColdStartStubCatalog`, etc.) |
| Log calls inside stubs | Behavior assertions (permission state, locale subset) |

### Refactor example

```swift
// BEFORE cleanup
#expect(logs.contains("installAssets partial"))
#expect(logs.contains("skippedBcp47Ids"))

// AFTER cleanup
#expect(vm.selectedLocales.map { $0.identifier(.bcp47) } == ["en-US"])
#expect(vm.permissionState == .granted)
```

Full cleanup steps: [cleanup-checklist.md](cleanup-checklist.md).