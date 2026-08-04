import Hero
import SwiftUI
import UIKit

/// Generic SwiftUI wrapper that places arbitrary SwiftUI content inside a UIView
/// carrying a Hero `hero.id`, so the whole visual unit (not just a background layer)
/// participates in a Hero shared-element transition between two screens.
///
/// Usage — apply the same `heroID` on the source and destination screens:
///
///     HeroContainer(heroID: "searchBar",
///                   heroModifiers: [.spring(stiffness: 200, damping: 22)]) {
///         HStack { Image(systemName: "magnifyingglass"); Text("Search") }
///             .padding()
///             .background(Capsule().fill(.gray.opacity(0.1)))
///     }
///
/// Important:
/// - Keep page-level padding OUTSIDE the container so Hero's source/destination
///   frames are the visible pill frames, not the outer margins.
/// - The container forwards `UIHostingController.sizeThatFits(in:)` to SwiftUI;
///   without this the container balloons to fill all available space.
struct HeroContainer<Content: View>: UIViewRepresentable {
    let heroID: String
    let heroModifiers: [HeroModifier]
    @ViewBuilder let content: () -> Content

    init(
        heroID: String,
        heroModifiers: [HeroModifier] = [],
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.heroID = heroID
        self.heroModifiers = heroModifiers
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(host: UIHostingController(rootView: content()))
    }

    func makeUIView(context: Context) -> HeroContainerUIView {
        let host = context.coordinator.host
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let container = HeroContainerUIView(host: host)
        container.hero.id = heroID
        container.hero.modifiers = heroModifiers

        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        return container
    }

    func updateUIView(_ uiView: HeroContainerUIView, context: Context) {
        context.coordinator.host.rootView = content()
        uiView.hero.id = heroID
        uiView.hero.modifiers = heroModifiers
        uiView.invalidateIntrinsicContentSize()
    }

    /// Forward the SwiftUI content's desired size so the container doesn't
    /// expand to fill all offered space.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: HeroContainerUIView,
        context: Context
    ) -> CGSize? {
        let targetSize = CGSize(
            width: proposal.width ?? UIView.layoutFittingCompressedSize.width,
            height: proposal.height ?? UIView.layoutFittingCompressedSize.height
        )
        return context.coordinator.host.sizeThatFits(in: targetSize)
    }

    @MainActor
    final class Coordinator {
        let host: UIHostingController<Content>

        init(host: UIHostingController<Content>) {
            self.host = host
        }
    }
}

final class HeroContainerUIView: UIView {
    private weak var host: UIViewController?

    init(host: UIViewController) {
        self.host = host
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        host?.view.intrinsicContentSize ?? super.intrinsicContentSize
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let host, window != nil else { return }
        if host.parent == nil, let parent = nearestViewController() {
            parent.addChild(host)
            host.didMove(toParent: parent)
        }
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let vc = current as? UIViewController {
                return vc
            }
            responder = current.next
        }
        return nil
    }
}
