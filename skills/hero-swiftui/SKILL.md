---
name: hero-swiftui
description: Implement Hero shared-element transitions in SwiftUI apps that use a UIKit navigation wrapper (iOS). Use when the user wants views, cards, images, search bars, or any element to morph smoothly between two screens on push/pop. Triggered by keywords like "Hero animation", "shared element transition", "morph between screens", "matched geometry across navigation", "hero.id", "HeroTransitions", or references to the Hero iOS library.
---

# Hero Shared-Element Transitions in SwiftUI

Hero (https://github.com/HeroTransitions/Hero) is a UIKit library that morphs matching-ID views between two view controllers during navigation. It works at the UIView layer. In a SwiftUI app, you must bridge Hero to SwiftUI via `UIViewRepresentable` — you cannot apply `hero.id` to a SwiftUI `View` directly.

## When to reach for this skill

- Two screens show the "same" visual element at different positions/sizes, and you want it to fly smoothly between them on push and pop (search bars, card-to-detail, thumbnail-to-hero-image, tag pills, avatars).
- Works in any SwiftUI app. If the project is using pure `NavigationStack`, you first need a UIKit-backed navigation wrapper — a complete drop-in one ships with this skill at [navigation-wrapper-notes.md](navigation-wrapper-notes.md). If the project already has one (check for `UIViewControllerRepresentable` wrapping `UINavigationController` with `hero.isEnabled = true`), skip straight to `HeroContainer` usage.

## Mental model — the single most common mistake

Hero only morphs the exact UIView that carries `hero.id`. If you set the ID on a background layer only, the rest of the SwiftUI content (icons, labels, text fields) just fades in place because those SwiftUI views are rendered inside the source/destination `UIHostingController` and are *not* part of the Hero pair. The background "flies to the wrong spot" while siblings fade, which looks broken.

**Fix**: wrap the entire visual unit you want to morph (icon + text + background + whatever) inside a single UIView that carries `hero.id`. Hero snapshots and morphs the whole unit together.

## The bridging primitive — `HeroContainer`

Create a reusable generic `UIViewRepresentable` that:

1. Creates a UIView with `hero.id` and `hero.modifiers` set on it.
2. Embeds a `UIHostingController` with arbitrary SwiftUI content.
3. Pins the hosting view to its edges with Auto Layout.
4. Implements `sizeThatFits(_:uiView:context:)` to forward size to SwiftUI layout. **Without this the view balloons to fill all available space**, destroying surrounding layout.
5. Attaches the hosting controller to the nearest parent VC on `didMoveToWindow` so lifecycle/constraints behave correctly.

See [HeroContainer.swift](HeroContainer.swift) for the full reference implementation. Copy it into `Views/Components/` (or similar) in any project.

## Using `HeroContainer`

Apply the same `heroID` to the matching element on both source and destination screens:

```swift
// Source (e.g. HomeSearchBar)
HeroContainer(
    heroID: "searchBar",
    heroModifiers: [.spring(stiffness: 200, damping: 22)]
) {
    HStack {
        Image(systemName: "magnifyingglass")
        Text("Search for files")
        Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Capsule().fill(.gray.opacity(0.1)))
}
.onTapGesture { router.navigate(to: .search) }

// Destination (e.g. SearchView)
HStack {
    HeroContainer(
        heroID: "searchBar",
        heroModifiers: [.spring(stiffness: 200, damping: 22)]
    ) {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search for files", text: $searchText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(.gray.opacity(0.1)))
    }
    Button("Cancel") { router.goBack() }
}
```

Rules:

- **Put outer padding (page margins, layout spacers) OUTSIDE `HeroContainer`.** Hero measures the source/destination frame from the container's own frame. Keeping padding outside makes the morph travel between the two visible pill frames, not the outer page rectangles.
- **Put interaction gestures (`onTapGesture`, etc.) OUTSIDE the container** unless the gesture is part of the morphed element itself.
- **Source and destination hierarchies can differ** (Text vs. TextField, extra sibling Button, etc.). Hero snapshots each side — they just need matching `heroID`.
- The pill/capsule/background visual should live *inside* the HeroContainer's content so it's part of the snapshot.

## Navigation wrapper requirements

Hero requires UIKit navigation. At minimum:

```swift
// Root
let nav = UINavigationController(rootViewController: rootHostingController)
nav.hero.isEnabled = true
nav.hero.navigationAnimationType = .auto  // or .fade, .push, etc.
rootHostingController.hero.isEnabled = true

// Every pushed controller
pushedHostingController.hero.isEnabled = true
nav.pushViewController(pushedHostingController, animated: true)
```

Per-route override just before pushing:

```swift
nav.hero.navigationAnimationType = .fade  // unpaired content fades; paired pairs still morph
nav.pushViewController(hostingController, animated: true)
```

- `.fade`, `.auto`, `.push`, `.cover`, etc. control how *unpaired* content animates. Paired `hero.id` views morph regardless.
- If you forget `hero.isEnabled = true` on either the nav controller OR a hosting controller, Hero is silently disabled for that transition.

## Hero modifiers worth knowing

- `.spring(stiffness:damping:)` — physics-based morph curve. Good default.
- `.duration(_:)`, `.delay(_:)`, `.curve(_:)` — manual timing.
- `.useNoSnapshot` — Hero moves the real UIView instead of a snapshot. Needed only for views with live interactive state that break when snapshotted (rare). For a `HeroContainer` wrapping SwiftUI content, **leave this off** — the snapshot crossfade handles differing source/destination SwiftUI hierarchies gracefully.
- `.zPosition(_:)` — raise a pair above others during the transition.
- `.cascade` — for lists, offset children's animations by a delay.

## Debugging checklist when it doesn't work

1. Is `hero.isEnabled = true` on the nav controller AND both hosting controllers?
2. Do BOTH the source and destination have a `HeroContainer` with the same `heroID`?
3. Is the `heroID` unique per transition (no duplicate IDs on screen)?
4. Is the element actually on-screen at push time? (Off-screen source means nothing to morph from.)
5. Did you forget `sizeThatFits` in `HeroContainer`? Symptom: the element expands to fill all available space and surrounding layout breaks.
6. Is `.useNoSnapshot` set somewhere it shouldn't be? It can produce weird results with SwiftUI hierarchies that differ between source and destination.
7. Are the two `HeroContainer` frames at plausibly similar points on screen? Huge jumps look correct but can feel broken; consider matching outer padding between screens.

## Things that are NOT solved by Hero

- **Same-screen matched geometry** (element moves between positions on one view) → use SwiftUI's `matchedGeometryEffect` instead.
- **Sheet / modal presentations** that don't go through the UIKit navigation controller → Hero can do modal too (`modalAnimationType` on the presented VC) but requires its own wiring.
- **TabView cross-tab transitions** → no built-in support; would require custom work.

## Files in this skill

- [HeroContainer.swift](HeroContainer.swift) — copy-paste-ready bridging primitive.
- [navigation-wrapper-notes.md](navigation-wrapper-notes.md) — minimal UIKit nav wrapper snippet for SwiftUI apps that don't already have one.
