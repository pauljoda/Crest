import AppKit
import SwiftUI

struct BrowserPlatformCommandPaletteHoverSelection: ViewModifier {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteItem

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.spaceContentIsInteractive) private var spaceContentIsInteractive

    func body(content: Content) -> some View {
        content.background {
            if isEnabled && spaceContentIsInteractive {
                PointerTracking {
                    guard model.selectedResultIndex != item.index else { return }
                    model.selectResult(item)
                }
                .accessibilityHidden(true)
            }
        }
    }

    private struct PointerTracking: NSViewRepresentable {
        let select: @MainActor () -> Void

        func makeNSView(context: Context) -> TrackingView {
            TrackingView(select: select)
        }

        func updateNSView(_ view: TrackingView, context: Context) {
            view.select = select
        }
    }

    /// Only movement in the visible part of this row changes the selection.
    /// Rows can appear under a resting pointer as the palette opens or scrolls.
    private final class TrackingView: NSView {
        var select: @MainActor () -> Void

        init(select: @escaping @MainActor () -> Void) {
            self.select = select
            super.init(frame: .zero)
            // In a SwiftUI scroll view, the native view otherwise inherits
            // the full scroll viewport as its visible rect.
            clipsToBounds = true
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                    owner: self, userInfo: nil
                )
            )
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func mouseMoved(with event: NSEvent) {
            guard visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return }
            select()
        }
    }
}
