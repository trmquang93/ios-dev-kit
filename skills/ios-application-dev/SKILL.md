---
name: ios-application-dev
description: |
  iOS application development guide covering UIKit, SnapKit, and SwiftUI. Includes touch targets, safe areas, navigation patterns, Dynamic Type, Dark Mode, accessibility, collection views, common UI components, SwiftUI design guidelines, and the latest Apple platform features (Liquid Glass, Foundation Models on-device LLM, AppIntents, AlarmKit, Visual Intelligence, Swift 6.2 concurrency, SwiftData inheritance, StoreKit, Swift Charts 3D, visionOS widgets). For detailed references on specific topics, see the reference files.
  Use when: developing iOS apps, implementing UI, reviewing iOS code, working with UIKit/SnapKit/SwiftUI layouts, building iPhone interfaces, Swift mobile development, Apple HIG compliance, iOS accessibility implementation, adopting iOS 26 / Xcode 26 APIs, Liquid Glass design, Apple Intelligence / Foundation Models, App Intents, alarms, in-app purchases, 3D charts, or visionOS widgets.
license: MIT
metadata:
  author: MiniMax-OpenSource
  version: "1.1.0"
  category: mobile
  sources:
    - Apple Human Interface Guidelines
    - Apple Developer Documentation
    - Xcode IDEIntelligenceChat AdditionalDocumentation (iOS 26 / Xcode 26)
---

# iOS Application Development Guide

A practical guide for building iOS applications using UIKit, SnapKit, and SwiftUI. Focuses on proven patterns and Apple platform conventions.

## Quick Reference

### UIKit

| Purpose | Component |
|---------|-----------|
| Main sections | `UITabBarController` |
| Drill-down | `UINavigationController` |
| Focused task | Sheet presentation |
| Critical choice | `UIAlertController` |
| Secondary actions | `UIContextMenuInteraction` |
| List content | `UICollectionView` + `DiffableDataSource` |
| Sectioned list | `DiffableDataSource` + `headerMode` |
| Grid layout | `UICollectionViewCompositionalLayout` |
| Search | `UISearchController` |
| Share | `UIActivityViewController` |
| Location (once) | `CLLocationButton` |
| Feedback | `UIImpactFeedbackGenerator` |
| Linear layout | `UIStackView` |
| Custom shapes | `CAShapeLayer` + `UIBezierPath` |
| Gradients | `CAGradientLayer` |
| Modern buttons | `UIButton.Configuration` |
| Dynamic text | `UIFontMetrics` + `preferredFont` |
| Dark mode | Semantic colors (`.systemBackground`, `.label`) |
| Permissions | Contextual request + `AVCaptureDevice` |
| Lifecycle | `UIApplication` notifications |

### SwiftUI

| Purpose | Component |
|---------|-----------|
| Main sections | `TabView` + `tabItem` |
| Drill-down | `NavigationStack` + `NavigationPath` |
| Focused task | `.sheet` + `presentationDetents` |
| Critical choice | `.alert` |
| Secondary actions | `.contextMenu` |
| List content | `List` + `.insetGrouped` |
| Search | `.searchable` |
| Share | `ShareLink` |
| Location (once) | `LocationButton` |
| Feedback | `UIImpactFeedbackGenerator` |
| Progress (known) | `ProgressView(value:total:)` |
| Progress (unknown) | `ProgressView()` |
| Dynamic text | `.font(.body)` semantic styles |
| Dark mode | `.primary`, `.secondary`, `Color(.systemBackground)` |
| Scene lifecycle | `@Environment(\.scenePhase)` |
| Reduce motion | `@Environment(\.accessibilityReduceMotion)` |
| Dynamic type | `@Environment(\.dynamicTypeSize)` |
| Glass material (iOS 26) | `.glassEffect()`, `.buttonStyle(.glass)`, `GlassEffectContainer` |

## Core Principles

### Layout
- Touch targets >= 44pt
- Content within safe areas (SwiftUI respects by default, use `.ignoresSafeArea()` only for backgrounds)
- Use 8pt spacing increments (8, 16, 24, 32, 40, 48)
- Primary actions in thumb zone
- Support all screen sizes (iPhone SE 375pt to Pro Max 430pt)

### Typography
- UIKit: `preferredFont(forTextStyle:)` + `adjustsFontForContentSizeCategory = true`
- SwiftUI: semantic text styles `.headline`, `.body`, `.caption`
- Custom fonts: `UIFontMetrics` / `Font.custom(_:size:relativeTo:)`
- Adapt layout at accessibility sizes (minimum 11pt)

### Colors
- Use semantic system colors (`.systemBackground`, `.label`, `.primary`, `.secondary`)
- Asset catalog variants for custom colors (Any/Dark Appearance)
- No color-only information (pair with icons or text)
- Contrast ratio >= 4.5:1 for normal text, 3:1 for large text

### Accessibility
- Labels on icon buttons (`.accessibilityLabel()`)
- Reduce motion respected (`@Environment(\.accessibilityReduceMotion)`)
- Logical reading order (`.accessibilitySortPriority()`)
- Support Bold Text, Increase Contrast preferences

### Navigation
- Tab bar (3-5 sections) stays visible during navigation
- Back swipe works (never override system gestures)
- State preserved across tabs (`@SceneStorage`, `@State`)
- Never use hamburger menus

### Privacy & Permissions
- Request permissions in context (not at launch)
- Custom explanation before system dialog
- Support Sign in with Apple
- Respect ATT denial

## Checklist

### Layout
- [ ] Touch targets >= 44pt
- [ ] Content within safe areas
- [ ] Primary actions in thumb zone (bottom half)
- [ ] Flexible widths for all screen sizes (SE to Pro Max)
- [ ] Spacing aligns to 8pt grid

### Typography
- [ ] Semantic text styles or UIFontMetrics-scaled custom fonts
- [ ] Dynamic Type supported up to accessibility sizes
- [ ] Layouts reflow at large sizes (no truncation)
- [ ] Minimum text size 11pt

### Colors
- [ ] Semantic system colors or light/dark asset variants
- [ ] Dark Mode is intentional (not just inverted)
- [ ] No color-only information
- [ ] Text contrast >= 4.5:1 (normal) / 3:1 (large)
- [ ] Single accent color for interactive elements

### Accessibility
- [ ] VoiceOver labels on all interactive elements
- [ ] Logical reading order
- [ ] Bold Text preference respected
- [ ] Reduce Motion disables decorative animations
- [ ] All gestures have alternative access paths

### Navigation
- [ ] Tab bar for 3-5 top-level sections
- [ ] No hamburger/drawer menus
- [ ] Tab bar stays visible during navigation
- [ ] Back swipe works throughout
- [ ] State preserved across tabs

### Components
- [ ] Alerts for critical decisions only
- [ ] Sheets have dismiss path (button and/or swipe)
- [ ] List rows >= 44pt tall
- [ ] Destructive buttons use `.destructive` role

### Privacy
- [ ] Permissions requested in context (not at launch)
- [ ] Custom explanation before system permission dialog
- [ ] Sign in with Apple offered with other providers
- [ ] Basic features usable without account
- [ ] ATT prompt shown if tracking, denial respected

### System Integration
- [ ] App handles interruptions gracefully (calls, background, Siri)
- [ ] App content indexed for Spotlight
- [ ] Share Sheet available for shareable content

## References

| Topic | Reference |
|-------|-----------|
| Touch Targets, Safe Area, CollectionView | [Layout System](references/layout-system.md) |
| TabBar, NavigationController, Modal | [Navigation Patterns](references/navigation-patterns.md) |
| StackView, Button, Alert, Search, ContextMenu | [UIKit Components](references/uikit-components.md) |
| CAShapeLayer, CAGradientLayer, Core Animation | [Graphics & Animation](references/graphics-animation.md) |
| Dynamic Type, Semantic Colors, VoiceOver | [Accessibility](references/accessibility.md) |
| Permissions, Location, Share, Lifecycle, Haptics | [System Integration](references/system-integration.md) |
| Metal Shaders & GPU | [Metal Shader Reference](references/metal-shader.md) |
| SwiftUI HIG, Components, Patterns, Anti-Patterns | [SwiftUI Design Guidelines](references/swiftui-design-guidelines.md) |
| Optionals, Protocols, async/await, ARC, Error Handling | [Swift Coding Standards](references/swift-coding-standards.md) |

### New Platform Features (iOS 26 / Xcode 26)

| Topic | Reference |
|-------|-----------|
| Liquid Glass material in SwiftUI (`.glassEffect`, containers, morphing) | [SwiftUI Liquid Glass](references/swiftui-liquid-glass.md) |
| Liquid Glass in UIKit (`UIGlassEffect`, containers, scroll edges) | [UIKit Liquid Glass](references/uikit-liquid-glass.md) |
| Liquid Glass in AppKit (`NSGlassEffectView`, containers) | [AppKit Liquid Glass](references/appkit-liquid-glass.md) |
| Liquid Glass & rendering modes in WidgetKit | [WidgetKit Liquid Glass](references/widgetkit-liquid-glass.md) |
| On-device LLM (Apple Intelligence) sessions, guided generation, tools, streaming | [Foundation Models: On-Device LLM](references/foundation-models-on-device-llm.md) |
| AppIntents: visual intelligence, intent modes, snippets, Spotlight, macros | [AppIntents Updates](references/appintents-updates.md) |
| Visual Intelligence camera/onscreen search integration | [Visual Intelligence in iOS](references/visual-intelligence-ios.md) |
| Custom alarms & timers, Live Activities (`AlarmManager`, `AlarmAttributes`) | [SwiftUI AlarmKit Integration](references/swiftui-alarmkit.md) |
| Assistive Access scene, simplified UI for cognitive disabilities | [Assistive Access in iOS](references/assistive-access-ios.md) |
| Swift 6.2 approachable concurrency, `@concurrent`, isolated conformances, default actor isolation | [Swift Concurrency Updates](references/swift-concurrency-updates.md) |
| `InlineArray` (fixed-size inline storage) and `Span` (safe contiguous memory) | [Swift InlineArray & Span](references/swift-inlinearray-span.md) |
| `@Model` class inheritance, type-based queries, polymorphic relationships | [SwiftData Class Inheritance](references/swiftdata-class-inheritance.md) |
| AttributedString text alignment, writing direction, line height, selection | [Foundation AttributedString Updates](references/foundation-attributedstring-updates.md) |
| Styled text editing: `TextEditor`, `AttributedString`, formatting definitions | [SwiftUI Styled Text Editing](references/swiftui-styled-text-editing.md) |
| Customizable toolbars, spacers, search behavior, placements, transitions | [SwiftUI New Toolbar Features](references/swiftui-toolbar-features.md) |
| `WebView` / `WebPage` for embedding web content, JS, navigation, PDFs | [SwiftUI WebKit Integration](references/swiftui-webkit-integration.md) |
| `PlaceDescriptor` / GeoToolbox with MapKit, geocoding, multi-service IDs | [MapKit GeoToolbox PlaceDescriptors](references/mapkit-geotoolbox-place-descriptors.md) |
| StoreKit: `AppTransaction`/`Transaction` fields, `SubscriptionOfferView`, JWS signing | [StoreKit Updates](references/storekit-updates.md) |
| `Chart3D`, `SurfacePlot`, pose, camera projection, surface styling | [Swift Charts 3D Visualization](references/swift-charts-3d.md) |
| visionOS widgets: mounting styles, textures, proximity awareness, families | [Widgets for visionOS](references/widgets-visionos.md) |

---

Swift, SwiftUI, UIKit, SF Symbols, Metal, and Apple are trademarks of Apple Inc. SnapKit is a trademark of its respective owners.
