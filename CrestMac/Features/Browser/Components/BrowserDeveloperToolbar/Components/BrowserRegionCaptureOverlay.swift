import SwiftUI

struct BrowserRegionCaptureOverlay: View {
    let page: BrowserPage

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(.rect)
            .gesture(captureGesture(in: proxy.frame(in: .local)))
            .overlay(alignment: .bottom) {
                BrowserRegionCaptureInstruction()
            }
        }
        .onExitCommand(perform: page.cancelRegionCapture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page capture selection")
        .accessibilityHint("Drag a rectangle to copy that part of the page")
        .accessibilityIdentifier("developer-region-capture")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        var mask = Path(bounds)
        if let selection = selectionRect(in: bounds) {
            mask.addRect(selection)
        }
        context.fill(
            mask,
            with: .color(.black.opacity(0.46)),
            style: FillStyle(eoFill: true)
        )
        if let selection = selectionRect(in: bounds) {
            context.stroke(
                Path(roundedRect: selection, cornerRadius: 4),
                with: .color(.white),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        }
    }

    private func captureGesture(in bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                }
                dragEnd = value.location
            }
            .onEnded { value in
                let start = dragStart ?? value.startLocation
                let rect = BrowserDeveloperCapturePolicy.captureRect(
                    from: start,
                    to: value.location,
                    in: bounds
                )
                dragStart = nil
                dragEnd = nil
                if let rect {
                    page.captureRegion(rect)
                }
            }
    }

    private func selectionRect(in bounds: CGRect) -> CGRect? {
        guard let dragStart, let dragEnd else { return nil }
        return BrowserDeveloperCapturePolicy.captureRect(
            from: dragStart,
            to: dragEnd,
            in: bounds
        )
    }
}

#Preview("Region Capture Overlay") {
    let preview = BrowserDetailPreviewFixture.makeWebContent()
    BrowserRegionCaptureOverlay(page: preview.page)
        .frame(width: 600, height: 360)
}
