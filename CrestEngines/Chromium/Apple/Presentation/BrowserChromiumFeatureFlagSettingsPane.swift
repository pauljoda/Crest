#if CREST_CHROMIUM_HOST
    import SwiftUI

    /// Chromium contributes its own privileged flags page to Crest Settings.
    /// The page stays inside the Settings detail area and uses the current Space's
    /// profile; no shared settings view knows how Chromium renders it.
    struct BrowserChromiumFeatureFlagSettingsPane: View {
        let profileID: UUID?

        var body: some View {
            if let profileID {
                ChromiumFeatureFlagsSurface(profileID: profileID)
                    .id(profileID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Feature Flags Unavailable",
                    systemImage: "flag.slash",
                    description: Text("Open Settings from an unlocked Space to view Chromium flags.")
                )
            }
        }
    }

    private struct ChromiumFeatureFlagsSurface: NSViewRepresentable {
        let profileID: UUID

        func makeCoordinator() -> Coordinator { Coordinator(profileID: profileID) }

        func makeNSView(context: Context) -> ChromiumNativePageView {
            let page = context.coordinator.page
            guard let url = URL(string: "chrome://flags/") else {
                preconditionFailure("Invalid Chromium flags address")
            }
            page.load(url)
            return page.surface
        }

        func updateNSView(_ view: ChromiumNativePageView, context: Context) {}

        static func dismantleNSView(_ view: ChromiumNativePageView, coordinator: Coordinator) {
            coordinator.page.dispose()
        }

        /// The flags page is a Settings surface, not a page a tab or a transient
        /// request owns, so it is Chromium's alone and the core never hears of it.
        @MainActor
        final class Coordinator {
            let page: ChromiumNativePage

            init(profileID: UUID) {
                page = ChromiumNativePage(
                    id: UUID(), profileID: profileID, isPrivateBrowsing: false, hostCommands: nil, binding: nil)
            }
        }
    }
#endif
