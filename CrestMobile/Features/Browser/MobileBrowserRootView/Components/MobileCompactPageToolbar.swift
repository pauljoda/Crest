import SwiftUI

struct MobileCompactPageToolbar: View {
    let browser: BrowserStore
    let pageActions: MobileSelectedPageActionPort?
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    let showTabViewer: () -> Void
    let hideToolbar: () -> Void
    let handleSwipe: (BrowserSpaceSwipeDirection) -> Void
    let compactTransitionEnded: (CGSize) -> Void

    var body: some View {
        HStack(spacing: MobileBrowserChromeLayout.compactToolbarSpacing) {
            GlassEffectContainer(spacing: 0) {
                MobilePageHistoryControls(pageActions: pageActions)
            }

            GlassEffectContainer(spacing: 0) {
                MobileCompactAddressBar(
                    browser: browser,
                    text: $address,
                    isEditing: $isAddressEditing,
                    isSecure: pageActions?.activeURL?.scheme?.lowercased() == "https",
                    progress: pageActions?.activePage?.estimatedProgress ?? 0,
                    isLoading: pageActions?.activePage?.isLoading == true,
                    pageActions: pageActions,
                    hideToolbar: hideToolbar,
                    reloadOrStop: reloadOrStop,
                    transition: .revealTabViewer,
                    transitionEnded: compactTransitionEnded,
                    beginNewTab: beginNewTab,
                    submit: submitAddress
                )
            }

            GlassEffectContainer(spacing: 0) {
                MobileCompactIconButton(
                    title: "Tabs",
                    systemImage: "square.on.square",
                    action: showTabViewer
                )
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityIdentifier("tab-viewer-button")
            }
        }
        .labelStyle(.iconOnly)
        .font(
            .system(
                size: MobileBrowserChromeLayout.compactToolbarSymbolSize,
                weight: .semibold
            )
        )
        .padding(
            .horizontal,
            MobileBrowserChromeLayout.compactToolbarHorizontalPadding
        )
        .padding(
            .vertical,
            MobileBrowserChromeLayout.compactToolbarVerticalPadding
        )
        .frame(maxWidth: .infinity)
        .browserSpaceSwipeGesture(handleSwipe)
    }

    private func reloadOrStop() {
        pageActions?.reloadOrStop()
    }
}

#Preview("Mobile Browser — Page Toolbar", traits: .fixedLayout(width: 390, height: 88)) {
    @Previewable @State var address = "developer.apple.com"
    @Previewable @State var isAddressEditing = false
    let fixture = MobileBrowserPreviewFixture()
    MobileCompactPageToolbar(
        browser: fixture.browser,
        pageActions: nil,
        address: $address,
        isAddressEditing: $isAddressEditing,
        submitAddress: {},
        beginNewTab: {},
        showTabViewer: {},
        hideToolbar: {},
        handleSwipe: { _ in },
        compactTransitionEnded: { _ in }
    )
    .padding()
}
