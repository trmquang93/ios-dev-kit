# Detecting the iOS "Wireless Data" Permission Prompt

## Problem

On first launch or reinstall, iOS shows a system alert: **"Allow [App] to use wireless data?"** While this prompt is visible, all networking is blocked — `NWPathMonitor` reports `.unsatisfied`. If your app has a splash screen with a network timeout (e.g., 10 seconds), the timeout can expire before the user responds, causing the app to skip network-dependent setup.

## Why Other Approaches Fail

### CTCellularData (CoreTelephony) — Unreliable

`CTCellularData.restrictedState` was the commonly suggested approach:

```swift
// DON'T rely on this alone
let cellularData = CTCellularData()
cellularData.cellularDataRestrictionDidUpdateNotifier = { state in
    switch state {
    case .restrictedStateUnknown: // prompt might be showing
    case .restricted:             // user denied
    case .notRestricted:          // user allowed
    }
}
```

**Problems:**
- On first install, state starts `.restrictedStateUnknown` — works as expected
- On **reinstall** (delete + reinstall), state can be `.restricted` OR `.notRestricted` unpredictably — iOS does not guarantee a specific initial state after reinstall
- Cannot reliably distinguish "prompt is showing" from "no prompt will appear"

### Window Hierarchy Check — Does Not Work

```swift
// DON'T use this — system alerts are NOT in the app's window hierarchy
UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .contains { $0.windowLevel > .normal }
```

**Problem:** The wireless data prompt is a system-level dialog managed by **SpringBoard** (a separate process). It never appears in the app's `UIWindowScene.windows` collection.

## Correct Approach: App Active-State Transitions

When any system alert covers the app (wireless data, phone call, Siri, etc.), iOS sends `UIApplication.willResignActiveNotification`. The app is still in the foreground but stops receiving events (state becomes `.inactive`). When the alert is dismissed, `UIApplication.didBecomeActiveNotification` fires.

### Key Design Points

1. **Track `hasActivatedOnce`** — The app briefly passes through `.inactive` during initial launch before becoming `.active`. Only treat resignation as "alert showing" after the first activation.
2. **Track `isResignedActive`** — Set on `willResignActive` (after first activation), cleared on `didBecomeActive`.
3. **Fresh timeout after dismissal** — When the alert is dismissed, the network stack needs time to establish connectivity. Give a fresh timeout window instead of using the original deadline (which has likely expired).

### Implementation

```swift
import Foundation
import Network
import UIKit

final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var isConnected = false
    private let lock = NSLock()

    // Alert detection state
    private var hasActivatedOnce = false
    private var isResignedActive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            isConnected = path.status == .satisfied
            lock.unlock()
        }
        monitor.start(queue: queue)
        isConnected = monitor.currentPath.status == .satisfied

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        lock.lock()
        hasActivatedOnce = true
        isResignedActive = false
        lock.unlock()
    }

    @objc private func appWillResignActive() {
        lock.lock()
        if hasActivatedOnce {
            isResignedActive = true
        }
        lock.unlock()
    }

    // MARK: - Synchronous accessors (safe from async contexts)

    private func checkConnected() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isConnected
    }

    private func isSystemAlertVisible() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasActivatedOnce && isResignedActive
    }

    // MARK: - Async waiters

    /// Waits for network connectivity with system-alert awareness.
    ///
    /// While a system alert is visible (app is inactive), the timeout is
    /// suspended. Once dismissed, a fresh timeout window starts.
    func waitForConnection(timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var wasWaitingForAlert = false
        var alertDismissedDate: Date?

        while !Task.isCancelled {
            if checkConnected() { return true }

            if isSystemAlertVisible() {
                wasWaitingForAlert = true
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }

            // Alert just dismissed — start fresh timeout
            if wasWaitingForAlert, alertDismissedDate == nil {
                alertDismissedDate = Date()
            }

            let effectiveDeadline = alertDismissedDate
                .map { $0.addingTimeInterval(timeout) } ?? deadline

            if Date() >= effectiveDeadline {
                return false
            }

            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func stop() {
        monitor.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
```

### Usage in a Splash Screen

```swift
struct SplashView: View {
    let onFinish: () -> Void

    var body: some View {
        SplashContent()
            .task {
                let hasNetwork = await NetworkMonitor.shared.waitForConnection()

                guard hasNetwork else {
                    // No internet — skip network-dependent setup
                    onFinish()
                    return
                }

                // Proceed with consent, remote config, ads, etc.
                await performNetworkSetup()
                onFinish()
            }
    }
}
```

## Behavior by Scenario

| Scenario | Behavior |
|---|---|
| Prompt shows (first install or reinstall) | `willResignActive` fires, waits indefinitely until dismissed, then fresh timeout |
| No prompt (subsequent launches) | No resignation detected, normal timeout applies |
| User taps "Allow" | `didBecomeActive` fires, fresh timeout, network connects |
| User taps "Don't Allow" but has WiFi | `didBecomeActive` fires, NWPathMonitor reports `.satisfied` via WiFi |
| User taps "Don't Allow", no WiFi | `didBecomeActive` fires, fresh timeout expires, returns `false` |
| Airplane mode (no prompt) | No alert detected, normal timeout, returns `false` |
| Simulator | No prompt shown, normal timeout behavior |

## Swift 6 Concurrency Note

`NSLock.lock()` and `unlock()` cannot be called directly inside `async` functions in Swift 6 strict concurrency mode. Wrap locked reads in synchronous helper methods:

```swift
// Compiler error in Swift 6:
func waitForConnection() async -> Bool {
    lock.lock()        // error: unavailable from async contexts
    let c = isConnected
    lock.unlock()      // error: unavailable from async contexts
    return c
}

// Correct — synchronous helper:
private func checkConnected() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return isConnected
}

func waitForConnection() async -> Bool {
    return checkConnected()  // no error
}
```

## References

- [StackOverflow: Ask wireless data permission before using it](https://stackoverflow.com/questions/78997566/ask-wireless-data-permission-before-using-it)
- `UIApplication.willResignActiveNotification` — [Apple Documentation](https://developer.apple.com/documentation/uikit/uiapplication/1622973-willresignactivenotification)
- `NWPathMonitor` — [Apple Documentation](https://developer.apple.com/documentation/network/nwpathmonitor)
