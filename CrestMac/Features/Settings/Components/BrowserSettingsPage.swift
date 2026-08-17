import AppKit
import SwiftUI

struct BrowserSettingsPage<Content: View>: View {
    let destination: BrowserSettingsDestination
    let scrollsContent: Bool
    let maximumContentWidth: CGFloat
    let contentHorizontalPadding: CGFloat
    let showsPageIdentity: Bool
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        scrollsContent: Bool = true,
        maximumContentWidth: CGFloat = BrowserSettingsVisualPolicy.maximumReadableContentWidth,
        contentHorizontalPadding: CGFloat = CrestSpacing.section,
        showsPageIdentity: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.scrollsContent = scrollsContent
        self.maximumContentWidth = maximumContentWidth
        self.contentHorizontalPadding = contentHorizontalPadding
        self.showsPageIdentity = showsPageIdentity
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPageIdentity {
                BrowserSettingsPaneHeader(
                    destination: destination,
                    identifier: "settings-page-header",
                    layout: .macOSPage
                )
            }

            if scrollsContent {
                ScrollView {
                    content
                        .frame(
                            maxWidth: maximumContentWidth,
                            alignment: .topLeading
                        )
                        .padding(.horizontal, contentHorizontalPadding)
                        .padding(.bottom, CrestSpacing.section)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                content
                    .frame(
                        maxWidth: maximumContentWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.bottom, CrestSpacing.section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .controlSize(.regular)
    }
}
