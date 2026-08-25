import AppKit
import SwiftUI

struct BrowserRootUtilityFanLayer: View {
    let model: BrowserRootModel

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { proxy in
            if let triggerFrame = model.chrome.utilityPresentation
                .triggerFrameInGlobal,
                model.sidebarPresentation.showsSidebar
            {
                BrowserRootUtilityFanControl(
                    model: model,
                    proxy: proxy,
                    triggerFrame: triggerFrame,
                    layoutDirection: layoutDirection
                )

                BrowserDownloadFeedbackLayer(
                    events: model.pages.downloadCenter.feedbackEvents,
                    profileID: model.browser.selectedSpace?.profile.id,
                    spaceID: model.browser.selectedSpace?.id,
                    destinationFrameInGlobal: triggerFrame
                )
                .zIndex(1)
            }
        }
    }
}

struct BrowserDownloadFeedbackWindowIdentityReader: NSViewRepresentable {
    @Binding var identifier: ObjectIdentifier?

    func makeCoordinator() -> Coordinator {
        Coordinator(identifier: $identifier)
    }

    func makeNSView(context: Context) -> WindowIdentityView {
        let view = WindowIdentityView()
        view.windowDidChange = { [weak coordinator = context.coordinator] window in
            coordinator?.set(window.map(ObjectIdentifier.init))
        }
        return view
    }

    func updateNSView(_ nsView: WindowIdentityView, context: Context) {
        context.coordinator.identifier = $identifier
    }

    final class Coordinator {
        var identifier: Binding<ObjectIdentifier?>

        init(identifier: Binding<ObjectIdentifier?>) {
            self.identifier = identifier
        }

        func set(_ value: ObjectIdentifier?) {
            guard identifier.wrappedValue != value else { return }
            identifier.wrappedValue = value
        }
    }

    final class WindowIdentityView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }
}
