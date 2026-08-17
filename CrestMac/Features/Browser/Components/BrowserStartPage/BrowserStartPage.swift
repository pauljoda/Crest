import SwiftUI

struct BrowserStartPage: View {
    let space: BrowserSpace?
    let isPrivateBrowsing: Bool
    let selectedTabID: TabID?
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab:
        (
            BrowserTabRuntimeAssignment,
            BrowserTabRuntimeAssignment
        ) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let promotionNamespace: Namespace.ID
    let promotionID: String
    let isCommandPaletteObscured: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.clear
                .accessibilityHidden(true)

            VStack(spacing: 28) {
                CrestStartPageMark()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text("Start Page")
                    .font(.largeTitle.weight(.semibold))
                if isPrivateBrowsing {
                    BrowserPrivateBrowsingNotice()
                }
                BrowserStartPageCommandPalette(
                    space: space,
                    selectedTabID: selectedTabID,
                    isSourceAvailable: isSourceAvailable,
                    selectTab: selectTab,
                    openURL: openURL,
                    promotionNamespace: promotionNamespace,
                    promotionID: promotionID,
                    isObscured: isCommandPaletteObscured,
                    reduceMotion: reduceMotion
                )
            }
            .padding(40)
            .frame(maxWidth: 820)
        }
    }
}
