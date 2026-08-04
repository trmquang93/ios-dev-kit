# UIKit Navigation Wrapper for SwiftUI + Hero

Hero hooks into `UINavigationController`. Pure SwiftUI `NavigationStack` does not expose the UIKit nav controller, so you need a `UIViewControllerRepresentable` that hosts a real `UINavigationController` and drives it from a SwiftUI router.

If your project already has such a wrapper, skip to the "Animation type cheat sheet" at the bottom. If not, this file contains a complete drop-in implementation.

## Drop-in implementation

Three files. Copy them into your project (adjust module/type names to taste).

### 1. `AppRoute.swift`

```swift
import Foundation

enum AppRoute: Hashable {
    case home
    case detail(id: String)
    case search
    // add your routes here

    /// Whether the UIKit nav bar should be hidden while this route is on top.
    var hidesNavigationBar: Bool { true }

    var pushAnimation: HeroNavigationAnimation { .push(direction: .left) }
    var popAnimation: HeroNavigationAnimation { .pull(direction: .right) }
}

/// Thin enum wrapper so routes don't leak the Hero type into non-UI code.
enum HeroNavigationAnimation {
    case auto
    case fade
    case push(direction: HeroDirection)
    case pull(direction: HeroDirection)
    case cover(direction: HeroDirection)
    case none
}

enum HeroDirection { case left, right, up, down }
```

### 2. `AppRouter.swift`

```swift
import Observation
import SwiftUI
import UIKit

@Observable
@MainActor
final class AppRouter {
    /// SwiftUI-side source of truth. The wrapper diffs nav stack against this.
    var history: [AppRoute] = []

    /// Populated by the wrapper at startup so the router can resolve frames for
    /// interactive gestures if you later add them. Optional.
    weak var navigationController: UINavigationController?

    func navigate(to route: AppRoute) {
        history.append(route)
    }

    func goBack() {
        guard !history.isEmpty else { return }
        history.removeLast()
    }

    func popToRoot() {
        history.removeAll()
    }
}
```

### 3. `UINavigationControllerWrapper.swift`

```swift
import Hero
import SwiftUI
import UIKit

/// Associates an AppRoute with each pushed UIViewController so we can diff
/// the UIKit stack against the SwiftUI-side `AppRouter.history`.
private enum RouteAssociatedKey {
    static var route = "AppRouteAssociatedKey"
}

extension UIViewController {
    fileprivate var associatedRoute: AppRoute? {
        get {
            objc_getAssociatedObject(self, &RouteAssociatedKey.route) as? AppRoute
        }
        set {
            objc_setAssociatedObject(
                self,
                &RouteAssociatedKey.route,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

struct UINavigationControllerWrapper<Root: View>: UIViewControllerRepresentable {
    let rootView: Root
    let router: AppRouter
    let destinationBuilder: (AppRoute) -> AnyView

    func makeUIViewController(context: Context) -> UINavigationController {
        let rootHost = UIHostingController(rootView: rootView)
        rootHost.hero.isEnabled = true
        rootHost.associatedRoute = nil

        let nav = UINavigationController(rootViewController: rootHost)
        nav.setNavigationBarHidden(true, animated: false)
        nav.hero.isEnabled = true
        nav.hero.navigationAnimationType = .auto
        nav.delegate = context.coordinator

        context.coordinator.nav = nav
        router.navigationController = nav
        return nav
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncStack()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate {
        var parent: UINavigationControllerWrapper
        weak var nav: UINavigationController?
        private var isProgrammatic = false

        init(_ parent: UINavigationControllerWrapper) { self.parent = parent }

        func syncStack() {
            guard let nav else { return }
            let desired = parent.router.history
            let current = nav.viewControllers
                .dropFirst()
                .compactMap { $0.associatedRoute }

            if Array(current) == desired { return }
            isProgrammatic = true

            if desired.count > current.count {
                for route in desired.suffix(desired.count - current.count) {
                    push(route)
                }
            } else if desired.count < current.count {
                configurePop()
                if desired.isEmpty {
                    nav.popToRootViewController(animated: true)
                } else {
                    let target = nav.viewControllers[desired.count]
                    nav.popToViewController(target, animated: true)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.isProgrammatic = false
            }
        }

        private func push(_ route: AppRoute) {
            guard let nav else { return }
            let vc = UIHostingController(rootView: parent.destinationBuilder(route))
            vc.hero.isEnabled = true
            vc.associatedRoute = route
            nav.hero.navigationAnimationType = heroType(for: route.pushAnimation)
            nav.setNavigationBarHidden(route.hidesNavigationBar, animated: true)
            nav.pushViewController(vc, animated: true)
        }

        private func configurePop() {
            guard let nav else { return }
            if let top = parent.router.history.last ?? nav.topViewController?.associatedRoute {
                nav.hero.navigationAnimationType = heroType(for: top.popAnimation)
            }
        }

        // Sync SwiftUI history when the user pops via the back gesture.
        func navigationController(
            _ nav: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            nav.setNavigationBarHidden(
                viewController.associatedRoute?.hidesNavigationBar ?? true,
                animated: animated
            )
            guard !isProgrammatic else { return }

            let stackRoutes = nav.viewControllers.dropFirst().compactMap { $0.associatedRoute }
            if stackRoutes.count < parent.router.history.count {
                parent.router.history = Array(stackRoutes)
            }
        }

        private func heroType(for animation: HeroNavigationAnimation) -> HeroDefaultAnimationType {
            switch animation {
            case .auto: return .auto
            case .fade: return .fade
            case .push(let dir): return .push(direction: dir.heroDirection)
            case .pull(let dir): return .pull(direction: dir.heroDirection)
            case .cover(let dir): return .cover(direction: dir.heroDirection)
            case .none: return .none
            }
        }
    }
}

private extension HeroDirection {
    var heroDirection: HeroDefaultAnimationType.Direction {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        }
    }
}
```

### 4. Mount at the app root

```swift
@main
struct MyApp: App {
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            UINavigationControllerWrapper(
                rootView: HomeView().environment(router),
                router: router,
                destinationBuilder: { route in
                    AnyView(destination(for: route).environment(router))
                }
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .home: HomeView()
        case .detail(let id): DetailView(id: id)
        case .search: SearchView()
        }
    }
}
```

Now `router.navigate(to: .search)` pushes via UIKit, and any `HeroContainer` with matching `heroID` on the two screens will morph.

## Installation

Add Hero via Swift Package Manager:

```
https://github.com/HeroTransitions/Hero
```

In Xcode: File → Add Package Dependencies → paste URL → choose the main product.

## Animation type cheat sheet

| Type | Unpaired content | Hero pairs (same `hero.id`) |
|------|------------------|------------------------------|
| `.auto` | Default push slide | Morph |
| `.fade` | Cross-fade | Still morph |
| `.push(direction:)` | Slides in specified direction | Still morph |
| `.pull(direction:)` | Slides out opposite way (typical for pop) | Still morph |
| `.cover(direction:)` | New VC covers old | Still morph |
| `.none` | No animation | Morph still runs |

Paired `hero.id` views always morph — the `navigationAnimationType` only governs what happens to *unpaired* content.

## Gotchas

- **Forgetting `hero.isEnabled = true` on a child VC silently disables Hero for that transition.** Set it every time you create a `UIHostingController` you're about to push.
- **Per-route animation type bleeds**: setting `nav.hero.navigationAnimationType` before one push persists for the next push. Either set it before every push (recommended, the snippet above does this) or reset to a default after navigation completes.
- **Swipe-back gesture**: interactive pop works if `hero.isEnabled = true` on both sides. Hero replaces the default interactive pop automatically.
- **Safe area**: the wrapper has `.ignoresSafeArea()` at the root so UIKit manages insets. Your SwiftUI views should handle their own top/bottom safe areas.
- **Sheets / modals** bypass the nav controller. Use `presentedVC.hero.isEnabled = true` and `presentedVC.hero.modalAnimationType = .auto` on the presented controller — or present as a child on the same nav.
- **`associatedRoute` + `UIHostingController`**: the Objective-C associated object keeps the route alive without subclassing. If you use `onAppear` inside the SwiftUI root to drive routing, you can read `viewController.associatedRoute` from a delegate to reconcile.
