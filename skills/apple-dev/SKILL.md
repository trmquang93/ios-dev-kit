---
name: apple-dev
description: Apple-platform development reference (Swift, SwiftUI, UIKit, AppKit, SwiftData, WidgetKit, AppIntents, StoreKit, MapKit, FoundationModels, visionOS). Use whenever writing, reviewing, or migrating code that targets an Apple platform — including resolving iOS/macOS deprecation warnings, adopting modern API replacements, implementing Liquid Glass or other Apple UI patterns, or answering any "how do I do X on iOS/macOS/visionOS" question. Prefer the bundled docs in this skill over general knowledge for Apple APIs.
allowed-tools: Read, Glob, Grep
---

# Apple Ecosystem Development

You have access to Apple's official documentation for the latest frameworks and APIs. These are reference documents inside Xcode — treat them as authoritative.

## Documentation Location

All reference files are bundled with this skill at:
`${CLAUDE_SKILL_DIR}/docs/`

## Available Topics

| File | Topic |
|------|-------|
| `SwiftUI-Implementing-Liquid-Glass-Design.md` | Liquid Glass design in SwiftUI |
| `UIKit-Implementing-Liquid-Glass-Design.md` | Liquid Glass design in UIKit |
| `AppKit-Implementing-Liquid-Glass-Design.md` | Liquid Glass design in AppKit |
| `WidgetKit-Implementing-Liquid-Glass-Design.md` | Liquid Glass design in WidgetKit |
| `SwiftUI-New-Toolbar-Features.md` | New toolbar APIs in SwiftUI |
| `SwiftUI-Styled-Text-Editing.md` | Styled text editing in SwiftUI |
| `SwiftUI-WebKit-Integration.md` | WebKit integration in SwiftUI |
| `SwiftUI-AlarmKit-Integration.md` | AlarmKit integration |
| `Swift-Concurrency-Updates.md` | Swift concurrency updates |
| `Swift-InlineArray-Span.md` | InlineArray and Span types |
| `Swift-Charts-3D-Visualization.md` | 3D charts with Swift Charts |
| `SwiftData-Class-Inheritance.md` | Class inheritance in SwiftData |
| `AppIntents-Updates.md` | App Intents framework updates |
| `FoundationModels-Using-on-device-LLM-in-your-app.md` | On-device LLM with Foundation Models |
| `Foundation-AttributedString-Updates.md` | AttributedString updates |
| `StoreKit-Updates.md` | StoreKit updates |
| `MapKit-GeoToolbox-PlaceDescriptors.md` | MapKit GeoToolbox and PlaceDescriptors |
| `Implementing-Assistive-Access-in-iOS.md` | Assistive Access in iOS |
| `Implementing-Visual-Intelligence-in-iOS.md` | Visual Intelligence in iOS |
| `Widgets-for-visionOS.md` | Widgets for visionOS |
| `UIKit-Adjustable-Blur-Intensity.md` | Adjustable blur intensity with UIViewPropertyAnimator (glass effect fallback for iOS <26) |
| `AppTrackingTransparency-ATT-Dialog.md` | ATT dialog implementation for IDFA access and personalized ads |
| `SwiftUI-Custom-Page-Control.md` | Custom page control with pill-shape animation using Capsule |
| `iOS-Wireless-Data-Permission-Detection.md` | Detecting and waiting for the iOS "wireless data" permission prompt via app active-state transitions |
| `UIKit-UIButton-Configuration.md` | Modern UIButton.Configuration (iOS 15+) — replaces deprecated `contentEdgeInsets`/`titleEdgeInsets`/`imageEdgeInsets`/`setImage(_:for:)`/`setTitle(_:for:)`. Covers mapping from legacy setter API, raster image sizing via pre-resize, SF Symbol sizing via `preferredSymbolConfigurationForImage`, hit-target-bigger-than-icon patterns, and `configurationUpdateHandler` for state. |

## How to Use

When the user asks about any Apple framework topic:

1. **Read the relevant file** using the Read tool before answering
2. **Base your answer on the file content** — it is the most current Apple documentation
3. **Reference specific APIs, modifiers, and code patterns** from the docs
4. **Do not guess** — if the docs don't cover it, say so clearly

### Example workflow

User asks: "How do I implement Liquid Glass in SwiftUI?"

1. Read `${CLAUDE_SKILL_DIR}/docs/SwiftUI-Implementing-Liquid-Glass-Design.md`
2. Answer based on the documented APIs and code examples

User asks: "How do I use on-device LLM?"

1. Read `${CLAUDE_SKILL_DIR}/docs/FoundationModels-Using-on-device-LLM-in-your-app.md`
2. Answer based on the FoundationModels framework documentation

## Guidelines

- Always check the docs first before answering Apple API questions
- Prefer the exact API names and parameter labels from the documentation
- When showing code examples, use Swift syntax consistent with the docs
- If multiple files are relevant, read all of them
- Mention when an API requires a minimum OS version if stated in the docs
