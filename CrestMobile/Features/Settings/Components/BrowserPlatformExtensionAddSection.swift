import SwiftUI

/// Browser extensions are a macOS-only feature for now.
///
/// This section exists only so the shared `BrowserExtensionsView` compiles for
/// the mobile target. Mobile Settings never offers the Extensions destination,
/// so this renders nothing and no mobile control can begin an installation. Do
/// not grow this into a working adapter: mobile support needs a deliberate
/// product decision first, not an installation entry point here.
struct BrowserPlatformExtensionAddSection: View {
    init(model _: BrowserExtensionsModel) {}

    var body: some View {
        EmptyView()
    }
}

/// Renders nothing by design. The preview exists to show that the mobile shell
/// contributes no install control, not to demonstrate one.
#Preview("Mobile Extension Add Section (Intentionally Empty)") {
    Form {
        BrowserPlatformExtensionAddSection(
            model: BrowserExtensionsPreviewFixture.model
        )
    }
}
