import AppKit
import SwiftUI

/// The desktop's page chrome: a destination's identity header above its pane,
/// on the window's own background.
///
/// How much chrome a destination gets is the destination's own business rather
/// than the caller's, so it comes from ``BrowserSettingsPageLayout``.
struct BrowserSettingsPage<Content: View>: View {
    let destination: BrowserSettingsDestination
    @ViewBuilder let content: Content

    init(
        destination: BrowserSettingsDestination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if layout.showsPageIdentity {
                BrowserSettingsPaneHeader(
                    destination: destination,
                    identifier: "settings-page-header",
                    layout: .macOSPage
                )
            }

            if layout.scrollsContent {
                ScrollView {
                    content
                        .frame(
                            maxWidth: layout.maximumContentWidth,
                            alignment: .topLeading
                        )
                        .padding(.horizontal, layout.contentHorizontalPadding)
                        .padding(.bottom, CrestSpacing.section)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                content
                    .frame(
                        maxWidth: layout.maximumContentWidth,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(.horizontal, layout.contentHorizontalPadding)
                    .padding(.bottom, CrestSpacing.section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .controlSize(.regular)
    }

    private var layout: BrowserSettingsPageLayout {
        .page(for: destination)
    }
}
