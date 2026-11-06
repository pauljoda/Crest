import SwiftUI

/// Every popover Crest presents. A popover takes what it reads in from the
/// view it comes from, so content shown with SwiftUI's own `popover` wears
/// that view's Space ink or forced scheme on a surface that follows the
/// window, or the page behind it. These draw the content on Crest's flyout
/// surface instead, and on the Mac keep the popover open while the person
/// works in the Colors panel a color well inside it opened.
extension View {
    /// Presents `content` in a popover on Crest's flyout surface while
    /// `isPresented` is true.
    func crestPopover<Content: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge) {
            content()
                .crestFlyoutStyle()
                .modifier(CrestPlatformPopoverModifier())
        }
    }

    /// Presents `content` for `item` in a popover on Crest's flyout surface
    /// while `item` is set.
    func crestPopover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        popover(item: item, attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge) { item in
            content(item)
                .crestFlyoutStyle()
                .modifier(CrestPlatformPopoverModifier())
        }
    }
}
