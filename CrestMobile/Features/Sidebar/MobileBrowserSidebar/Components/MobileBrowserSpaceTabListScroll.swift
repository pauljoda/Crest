import SwiftUI

/// The compact shell's scrolling chrome around the shared tab list.
///
/// What belongs to this shell rather than to the list is the prepositioning: the
/// page a row opens grows out of that row in place, so the row has to be on
/// screen with a real resting frame before the morph starts. The stack is eager
/// for the same reason — a row that materializes offscreen has no frame for the
/// transition to grow from.
struct MobileBrowserSpaceTabListScroll<Content: View>: View {
    let space: BrowserSpace
    let browser: BrowserStore
    let compactPageIsFullyPresented: Bool
    let tabActions: BrowserSidebarTabActions
    let openNewTab: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            content()
                        }
                        .padding(.bottom, 8)

                        Color.clear
                            .contentShape(.rect)
                            .modifier(
                                BrowserSidebarEmptySpaceNewTabGesture(
                                    tabActions: tabActions,
                                    openNewTab: openNewTab
                                )
                            )
                            .accessibilityHidden(true)
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
                .simultaneousGesture(
                    TapGesture().onEnded {
                        BrowserAddressFocusDismissal.dismiss()
                    }
                )
                .accessibilityLabel("Saved and current tabs")
                .accessibilityIdentifier(
                    BrowserSpaceAccessibilityID.tabs(space.id)
                )
                .onChange(of: selectedPromotionTarget) { previous, current in
                    guard
                        MobileTabPromotionPolicy.shouldPreposition(
                            previous: previous,
                            current: current,
                            compactPageIsFullyPresented: compactPageIsFullyPresented
                        ), let current
                    else { return }

                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(current.tabID, anchor: .center)
                    }
                }
            }
        }
    }

    private var selectedTab: BrowserTab? {
        guard let selectedTabID = space.selectedTabID else { return nil }
        return space.tabs.first { $0.id == selectedTabID }
    }

    private var selectedPromotionTarget: MobileTabPromotionTarget? {
        MobileTabPromotionPolicy.target(
            for: selectedTab,
            selectedTabID: space.selectedTabID
        )
    }
}
