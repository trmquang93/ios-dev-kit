# UIVisualEffectView with Adjustable Blur Intensity

## Problem

SwiftUI's built-in `Material` types (`.ultraThinMaterial`, `.regularMaterial`, etc.) are fixed presets with no way to control blur intensity. Setting `alpha` on `UIVisualEffectView` does NOT reduce blur strength — Apple warns against it and it causes rendering artifacts.

## Solution: UIViewPropertyAnimator + fractionComplete

Use a `UIViewPropertyAnimator` that transitions from "no effect" to "full blur effect", then pause it at the desired fraction. The blur never actually animates — it stays frozen at the specified intensity.

### SwiftUI Wrapper

```swift
import SwiftUI
import UIKit

struct SubtleBlurView: UIViewRepresentable {
    var intensity: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let effectView = UIVisualEffectView()
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            effectView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = intensity
        context.coordinator.animator = animator
        return effectView
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        context.coordinator.animator?.fractionComplete = intensity
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var animator: UIViewPropertyAnimator?

        // REQUIRED: a running/paused UIViewPropertyAnimator raises
        // NSInternalInconsistencyException in -dealloc. Stop it before
        // the Coordinator is released (e.g. on SwiftUI Preview reload).
        deinit {
            animator?.stopAnimation(true)
        }
    }
}
```

> **Important:** Always stop the animator in `Coordinator.deinit`. `UIViewPropertyAnimator` traps in `dealloc` if it is still active or paused, which crashes SwiftUI Previews on reload and can crash the app on view teardown. `stopAnimation(true)` cancels without finishing — no `finishAnimation(at:)` call needed.

### Usage Examples

```swift
// Subtle glass background (20% blur)
SubtleBlurView(intensity: 0.2)
    .clipShape(RoundedRectangle(cornerRadius: 16))

// Capsule-shaped tab bar glass
SubtleBlurView(intensity: 0.2)
    .clipShape(Capsule())
    .overlay(
        Capsule()
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.1), radius: 12, y: -4)

// Half-strength blur overlay
SubtleBlurView(intensity: 0.5)
    .clipShape(RoundedRectangle(cornerRadius: 12))
```

## How It Works

1. `UIVisualEffectView()` starts with no effect (fully transparent).
2. The animator's closure sets the target state: full `UIBlurEffect`.
3. `fractionComplete` controls where the animation is "paused" — 0.0 = no blur, 1.0 = full blur, 0.2 = 20% blur.
4. `pausesOnCompletion = true` prevents the animator from cleaning up after reaching its fraction, keeping the partial blur alive.
5. The `Coordinator` holds a strong reference to the animator to prevent deallocation.

## Common Blur Styles

You can swap `UIBlurEffect(style:)` depending on the desired look:

| Style | Description |
|-------|-------------|
| `.systemUltraThinMaterial` | Thinnest blur, most transparent |
| `.systemThinMaterial` | Slightly more opaque |
| `.systemMaterial` | Standard material blur |
| `.systemThickMaterial` | Heavy blur |
| `.systemChromeMaterial` | Chrome-like, for navigation bars |

## Anti-Patterns

- **Do NOT set `UIVisualEffectView.alpha`** — This makes the entire view (including content) semi-transparent rather than reducing blur strength. Apple explicitly warns against this in their documentation.
- **Do NOT use SwiftUI `.opacity()` on a Material** — Same problem as setting alpha.

## iOS Version Compatibility

- `UIViewPropertyAnimator` is available from iOS 10+.
- `UIBlurEffect` material styles (`.system*Material`) are available from iOS 13+.
- For iOS 26+, prefer native `.glassEffect()` modifier instead.

### Version-Gated Glass Pattern

```swift
.background {
    Group {
        if #available(iOS 26.0, *) {
            Color.clear
        } else {
            SubtleBlurView(intensity: 0.2)
                .clipShape(Capsule())
        }
    }
}
.modifier(GlassEffectModifier())

// Separate modifier for availability check
struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: .capsule)
        } else {
            content
        }
    }
}
```
