# Custom Page Control with Pill-Shape Animation in SwiftUI

## Overview

SwiftUI's `TabView` with `.tabViewStyle(.page)` provides a built-in `UIPageControl`, but it offers limited customization. For richer designs — pill-shaped active indicators, custom colors, size transitions, or spring animations — build a custom page control using SwiftUI shape primitives.

## Technique: Capsule-Based Page Dots

### Core Concept

Use `Capsule()` as the dot shape. A `Capsule` automatically rounds its corners to half its height. When width equals height, it renders as a circle (inactive dot). When width exceeds height, it renders as a pill (active dot). Animating between these two states produces a smooth stretch/shrink effect.

### Minimal Implementation

```swift
struct PageDotsView: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.accentColor : Color.gray.opacity(0.5))
                    .frame(width: index == currentPage ? 22 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentPage)
            }
        }
    }
}
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| `Capsule()` over `Circle()` | A single shape handles both circle and pill states — no conditional shape swapping needed |
| Implicit `.animation(_:value:)` | Cleaner than wrapping every page change in `withAnimation {}`. The animation triggers only when `currentPage` changes |
| Fixed `height: 8` | Keeps vertical layout stable; only width animates |
| `ForEach(0..<pageCount, id: \.self)` | Stable identity for each dot — SwiftUI can animate individual dot transitions |

### Hiding the Built-in Page Control

When using a custom page control with `TabView`, hide the native dots:

```swift
TabView(selection: $currentPage) {
    // pages...
}
.tabViewStyle(.page(indexDisplayMode: .never))
```

## Variations

### Spring Animation

Replace the easing curve with a spring for a bouncier feel:

```swift
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
```

### Interpolated Width (Smooth Scrolling)

For page controls that respond to scroll position (not just discrete page index), use `GeometryReader` on the `TabView` content to derive a continuous offset, then interpolate dot widths:

```swift
struct SmoothPageDotsView: View {
    let pageCount: Int
    let progress: CGFloat // 0.0 to CGFloat(pageCount - 1)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                let distance = abs(progress - CGFloat(index))
                let scale = max(0, 1 - distance)
                Capsule()
                    .fill(Color.accentColor.opacity(0.3 + 0.7 * scale))
                    .frame(width: 8 + 14 * scale, height: 8)
            }
        }
        .animation(.interactiveSpring, value: progress)
    }
}
```

### Expanding Active Dot with Label

Embed text inside the active dot for a labeled indicator:

```swift
Capsule()
    .fill(isActive ? Color.accentColor : Color.gray.opacity(0.5))
    .frame(width: isActive ? 48 : 8, height: 24)
    .overlay {
        if isActive {
            Text("\(index + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .transition(.opacity)
        }
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)
```

### Multi-Color Theme

Use an array of colors for each dot:

```swift
let dotColors: [Color] = [.blue, .green, .orange]

Capsule()
    .fill(index == currentPage ? dotColors[index] : dotColors[index].opacity(0.3))
```

### Accessibility Scaling

Respect Dynamic Type by using `@ScaledMetric`:

```swift
@ScaledMetric(relativeTo: .caption) private var dotHeight: CGFloat = 8
@ScaledMetric(relativeTo: .caption) private var activeWidth: CGFloat = 22
@ScaledMetric(relativeTo: .caption) private var inactiveWidth: CGFloat = 8
```

## Integration Pattern

### With TabView

```swift
struct OnboardingView: View {
    @State private var currentPage = 0
    let pages: [OnboardingPage]

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    PageContentView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDotsView(pageCount: pages.count, currentPage: currentPage)
                .padding(.vertical, 12)

            Button(currentPage == pages.count - 1 ? "Get Started" : "Next") {
                if currentPage < pages.count - 1 {
                    withAnimation { currentPage += 1 }
                } else {
                    // finish onboarding
                }
            }
        }
    }
}
```

### With ScrollView + Paging (iOS 17+)

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(pages.indices, id: \.self) { index in
            PageContentView(page: pages[index])
                .containerRelativeFrame(.horizontal)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)
.scrollPosition(id: $currentPage)
```

## Performance Notes

- `Capsule()` is a lightweight SwiftUI shape — no UIKit bridging overhead.
- Implicit animation on each dot is efficient; SwiftUI only re-renders dots whose properties actually change.
- For large page counts (10+), consider showing only a window of dots around the active page (e.g., 5 visible dots with scaling) to avoid horizontal overflow.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Dots don't animate | Ensure `.animation(_:value:)` references the correct state variable (`currentPage`) |
| All dots flash on appear | Use `.animation(_:value:)` (implicit, tied to specific value) instead of `.animation(_:)` (deprecated, animates all changes) |
| Dots reorder on page change | Use `id: \.self` with a stable integer range, not dynamic array elements |
| Layout jumps when active dot stretches | Wrap the `HStack` in a fixed-height frame so surrounding content doesn't shift |
