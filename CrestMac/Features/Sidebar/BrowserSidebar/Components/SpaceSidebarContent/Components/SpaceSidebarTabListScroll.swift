import SwiftUI

/// The windowed shell's scrolling chrome around the shared tab list.
///
/// Two things here belong to this shell and not to the list. The list is laid
/// out lazily and pinned to the top of a region at least as tall as the sidebar,
/// so the space below the last row is real and can be handed to `background` —
/// which is what makes the empty sidebar draggable and right-clickable. And a
/// tap anywhere over the region gives up address focus, because on this shell
/// the address field keeps it until something takes it away.
struct SpaceSidebarTabListScroll<Background: View, Content: View>: View {
    let browser: BrowserStore
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(spacing: 0) {
                        content()
                    }

                    background()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollClipDisabled(
                !BrowserSidebarReorderVisuals.clipsScrollableRegion(
                    clipsWhenIdle: BrowserSidebarScrollLayoutPolicy
                        .clipsScrollableRegion,
                    isDragging: browser.sidebarReorderState.isDragging
                )
            )
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                BrowserAddressFocusDismissal.dismiss()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved and current tabs")
    }
}
