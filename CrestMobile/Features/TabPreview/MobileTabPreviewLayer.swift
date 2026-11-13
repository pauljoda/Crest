import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A sidebar's tab preview on an iPhone or iPad: the shared layer, drawing
/// the pictures the scene's pages keep, which it starts them keeping. A
/// pointer resting on a row shows its card beside the sidebar's edge, and a
/// finger holding a folder shows the folder's card over a scrim.
///
/// A tap or a click anywhere outside the card takes it down, or the card on
/// its way, as does Escape, the scene leaving the screen, the window showing
/// another Space or its Space locking. A drag that starts takes a held card
/// down, as the drag is what the hold went on to.
struct MobileTabPreviewLayer: View {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    @Environment(\.scenePhase) private var scenePhase

    let preview: BrowserTabPreviewState
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    /// How far the sidebar's page edge is from its side of the layer, or nil
    /// where the sidebar fills the layer.
    var sidebarEdge: CGFloat?

    // MARK: - Actions - Presentation

    var body: some View {
        let pictures = pages.tabPictures
        BrowserTabPreviewLayer(preview: preview, sidebarEdge: sidebarEdge) { pictures.previewPicture(of: $0) }
            .background {
                MobileTabPreviewDismissal(preview: preview)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                if preview.shown != nil {
                    Button("Close", action: preview.dismiss)
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: pages.browser.shownSpace?.id) { preview.dismiss() }
            .onChange(of: pages.browser.shownSpace.map(spaceAccess.isLocked) ?? false) { _, isLocked in
                if isLocked { preview.dismiss() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { preview.dismiss() }
            }
            .onChange(of: sidebarInteraction.sidebarReorderState.isDragging) { _, isDragging in
                if isDragging, preview.shown?.isHeldByTouch == true { preview.dismiss() }
            }
            .onAppear {
                let spaceAccess = spaceAccess
                pictures.follow { spaceAccess.isLocked($0) }
            }
    }
}

/// Takes the card down, or the card on its way, when a finger or a pointer
/// touches the window outside it. A held card's scrim answers its own taps.
private struct MobileTabPreviewDismissal: UIViewRepresentable {
    let preview: BrowserTabPreviewState

    func makeUIView(context: Context) -> MobileTabPreviewDismissalView {
        let view = MobileTabPreviewDismissalView()
        view.preview = preview
        return view
    }

    func updateUIView(_ view: MobileTabPreviewDismissalView, context: Context) {
        view.preview = preview
    }
}

/// Watches every touch in its window without taking any, and draws nothing.
final class MobileTabPreviewDismissalView: UIView {
    // MARK: - Variables

    weak var preview: BrowserTabPreviewState?
    private lazy var observer = MobileTouchObserver { [weak self] location in self?.touched(at: location) }

    // MARK: - Initializers

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Actions - Hosting

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observer.view?.removeGestureRecognizer(observer)
        window?.addGestureRecognizer(observer)
    }

    // MARK: - Actions - Touches

    private func touched(at location: CGPoint) {
        guard let preview, preview.isEngaged, preview.shown?.isHeldByTouch != true else { return }
        let cards = [preview.cardFrame, preview.inner.cardFrame].compactMap(\.self)
        guard !cards.contains(where: { $0.contains(location) }) else { return }
        preview.dismiss()
    }
}

/// Tells where each touch in its view begins, and never recognizes, so the
/// touch goes on to whatever it was for.
private final class MobileTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let touched: (CGPoint) -> Void

    init(touched: @escaping (CGPoint) -> Void) {
        self.touched = touched
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view { touched(touch.location(in: view)) }
        state = .failed
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
