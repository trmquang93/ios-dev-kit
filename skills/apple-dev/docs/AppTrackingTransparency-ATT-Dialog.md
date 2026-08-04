# App Tracking Transparency (ATT) — Implementation Guide

## Overview

The App Tracking Transparency framework (`AppTrackingTransparency`) requires apps to request user permission before tracking them across apps and websites owned by other companies. This is mandatory for accessing the device's IDFA (Identifier for Advertisers), which ad networks like Google AdMob use to serve personalized ads.

**Minimum deployment target:** iOS 14.0+

## Key API

```swift
import AppTrackingTransparency

// Check current status (synchronous, no prompt)
let status = ATTrackingManager.trackingAuthorizationStatus

// Request authorization (async, shows system dialog)
let status = await ATTrackingManager.requestTrackingAuthorization()
```

### Authorization Status Values

| Status | Raw Value | Meaning |
|--------|-----------|---------|
| `.notDetermined` | 0 | User has not been asked yet (or system not ready) |
| `.restricted` | 1 | Device-level restriction (e.g., parental controls) |
| `.denied` | 2 | User tapped "Ask App Not to Track" |
| `.authorized` | 3 | User tapped "Allow" |

## Required Info.plist Key

You must add `NSUserTrackingUsageDescription` to your Info.plist. iOS displays this string in the ATT dialog below the standard prompt text.

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>
```

For localization, add the key to `InfoPlist.xcstrings` (not `Localizable.xcstrings`):

```json
"NSUserTrackingUsageDescription" : {
  "comment" : "Privacy - Tracking Usage Description",
  "localizations" : {
    "en" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "This identifier will be used to deliver personalized ads to you."
      }
    }
  }
}
```

## Timing: When to Request

**Critical rule:** The app's main window must be fully visible before calling `requestTrackingAuthorization()`. If called too early (e.g., in `application(_:didFinishLaunchingWithOptions:)` or before the first frame renders), iOS silently returns `.notDetermined` without showing the dialog.

### Recommended placement

- **SwiftUI:** Inside a `.task` or `.onAppear` modifier on the splash/landing screen
- **UIKit:** In `viewDidAppear(_:)` of the first visible view controller (not `viewDidLoad`)

### Ordering with ad SDKs

ATT status must be resolved **before** initializing or loading ads. If ads load before ATT resolves, ad networks default to non-personalized ads for the entire session.

```
1. App launches, splash screen appears
2. Request ATT authorization → wait for user response
3. Initialize/load ads (AdMob, etc.)
```

## Implementation Pattern: Retry Loop

`requestTrackingAuthorization()` can return `.notDetermined` if the system is not ready to present the dialog (window not fully presented, app transitioning, etc.). Use a retry loop to handle this edge case:

```swift
import AppTrackingTransparency

private func requestTrackingPermission() async {
    var status = ATTrackingManager.trackingAuthorizationStatus
    while status == .notDetermined {
        try? await Task.sleep(for: .seconds(1))
        status = await ATTrackingManager.requestTrackingAuthorization()
    }
    print("ATT status: \(status.rawValue)")
}
```

### Why the while loop?

- On first call, if the window isn't ready, iOS returns `.notDetermined` immediately
- The 1-second sleep gives the system time to finish presenting
- On subsequent iterations, `requestTrackingAuthorization()` shows the actual dialog
- Once the user responds, status changes to `.authorized`, `.denied`, or `.restricted`
- The loop exits naturally with a definitive status

## Full SwiftUI Example (Splash Screen with Ads)

```swift
import AppTrackingTransparency
import SwiftUI

struct SplashView: View {
    @Environment(StoreManager.self) private var storeManager
    @Environment(AdManager.self) private var adManager

    var body: some View {
        // ... splash UI ...
        .task {
            // 1. Check subscription status first
            await storeManager.updatePurchasedProducts()

            // 2. Skip ATT for subscribers (they don't see ads)
            if storeManager.isProUser {
                proceedToMain()
                return
            }

            // 3. Request tracking permission before loading ads
            await requestTrackingPermission()

            // 4. Now load ads — AdMob will use the ATT status
            adManager.preloadAll()
            await adManager.loadAndShowInterstitial()
            proceedToMain()
        }
    }

    private func requestTrackingPermission() async {
        var status = ATTrackingManager.trackingAuthorizationStatus
        while status == .notDetermined {
            try? await Task.sleep(for: .seconds(1))
            status = await ATTrackingManager.requestTrackingAuthorization()
        }
    }
}
```

## Best Practices

1. **Skip for subscribers** — Users who pay for an ad-free experience should never see the ATT prompt. There is nothing to personalize.

2. **Request only once per install** — After the user responds, the status is persisted. Subsequent calls to `requestTrackingAuthorization()` return the stored status without showing a dialog. Users can change their choice in Settings > Privacy > Tracking.

3. **Do not gate functionality on the response** — Apple requires that your app works the same regardless of whether the user allows or denies tracking. Show non-personalized ads if denied.

4. **Do not use custom pre-prompts** — Apple has rejected apps that show a custom alert before the ATT dialog to "prime" users. Go directly to the system dialog.

5. **Test on device** — The ATT dialog does not appear in the iOS Simulator. You must test on a physical device. In the simulator, `requestTrackingAuthorization()` immediately returns `.authorized` without showing UI.

## App Store Review Notes

- Apps that access IDFA without showing the ATT prompt will be rejected
- The `NSUserTrackingUsageDescription` must clearly explain why tracking is needed
- Apple reviewers check that the prompt appears before any tracking occurs
- The Privacy Nutrition Label in App Store Connect must declare "Advertising" under "Data Used to Track You" if ATT is used
