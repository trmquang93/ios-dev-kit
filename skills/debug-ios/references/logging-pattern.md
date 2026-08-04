# iOS Debug Logging Pattern

Drop-in template for feature-scoped debug logging **during investigation only**.

> **Lifecycle:** Add at step 3 of `debug-ios` → use for device repro → **delete entirely at step 9** after user confirms fix. Do not ship verbose debug loggers in production. See [cleanup-checklist.md](cleanup-checklist.md).

## Swift template

```swift
import Foundation
import os

enum FeatureDebugLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app",
        category: "FeatureName"  // filter in Console.app
    )

    private static var memory: [String] = []
    private static let lock = NSLock()

    static var logURL: URL {
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            return docs.appendingPathComponent("feature-debug.log")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("feature-debug.log")
    }

    static func reset() {
        lock.lock(); memory = []; lock.unlock()
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }

    static func log(
        _ message: String,
        hypothesisId: String = "",
        data: [String: Any] = [:],
        location: String = #function
    ) {
        var payload: [String: Any] = [
            "sessionId": "feature-debug",
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "location": location,
            "message": message,
        ]
        if !hypothesisId.isEmpty { payload["hypothesisId"] = hypothesisId }
        if !data.isEmpty { payload["data"] = data }

        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }

        lock.lock(); memory.append(line); lock.unlock()

        print("[FeatureDebug] \(line)")           // user copies from Xcode
        logger.info("\(message, privacy: .public)") // Console.app
        appendToFile(line)
    }

    static func readAll() -> String {
        lock.lock()
        defer { lock.unlock() }
        if !memory.isEmpty { return memory.joined(separator: "\n") }
        return (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    }

    static func flushToConsole() {
        let lines = readAll()
        guard !lines.isEmpty else {
            print("[FeatureDebug] (no logs)")
            return
        }
        print("[FeatureDebug] —— session dump ——")
        for line in lines.split(separator: "\n", omittingEmptySubsequences: true) {
            print("[FeatureDebug] \(line)")
        }
        print("[FeatureDebug] —— end dump ——")
    }

    private static func appendToFile(_ line: String) {
        let url = logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        h.write(Data("\n".utf8))
        try? h.close()
    }
}
```

## Where to log

| Event | hypothesisId example |
|-------|---------------------|
| Init / hydration | H1 |
| SDK poll / catalog load | H2 |
| Asset install | H3 |
| Per-locale skip / partial success | H4 |
| Permission result | H5 |

## When to call `flushToConsole()`

- Permission denied / unavailable
- Install failure (all locales failed)
- User dismisses sheet (cancel)
- Any path that sets a terminal error state

## Naming convention

Use `[FeatureDebug]` prefix consistently — user filters on this string.
Rename to match feature: `[TalkToMeDebug]`, `[CaptureDebug]`, etc.

---

## Cleanup (after fix confirmed)

1. Delete this logger file from the app target
2. Remove every `FeatureDebugLog.log(...)` and `flushToConsole()` at call sites
3. Grep: `DebugLog|FeatureDebug|hypothesisId|flushToConsole`
4. Optionally keep **error-only** `os.Logger` lines for real failures — no JSON, no per-poll spam:

```swift
logger.error("installAssets failed: \(error.localizedDescription, privacy: .public)")
```

Tests that used `readAll()` must assert on VM state instead — see [cleanup-checklist.md](cleanup-checklist.md).