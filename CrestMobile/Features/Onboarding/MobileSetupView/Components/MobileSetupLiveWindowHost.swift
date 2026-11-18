import SwiftUI

/// Hosts the copy's browser in a controller of its own, apart from setup's
/// SwiftUI hierarchy: no safe area of the screen reaches it, so the browser
/// lays out from its own top, and only what `content` carries of the
/// environment reaches it. Its layer rounds its corners, which clips the
/// browser's own UIKit views too.
struct MobileSetupLiveWindowHost<Content: View>: UIViewControllerRepresentable {
    // MARK: - Variables

    let content: Content
    let cornerRadius: CGFloat

    // MARK: - Actions - Hosting

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.layer.masksToBounds = true
        controller.view.layer.cornerCurve = .continuous
        controller.view.layer.cornerRadius = cornerRadius
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        controller.rootView = content
        controller.view.layer.cornerRadius = cornerRadius
    }
}
