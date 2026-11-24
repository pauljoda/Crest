import SwiftUI

/// The page's connection: whether it is secure, the origin it reached, and
/// its certificate where the platform shows one.
struct SiteControlsConnectionPage: View {
    let model: SiteControlsModel

    var body: some View {
        SiteControlsPageSection(footer: model.security.detail.map { Text($0) }) {
            SiteControlsRowLabel(
                title: Text(model.connectionTitle), symbol: model.connectionSymbol,
                subtitle: model.origin.map { Text(verbatim: $0.displayName).monospaced() },
                symbolTint: model.connectionTint, titleTint: model.connectionTint
            ) { EmptyView() }
            if let review = model.platform.certificateReview {
                SiteControlsRow("Review Certificate", symbol: "checkmark.seal") {
                    model.platform.dismiss()
                    Task { @MainActor in
                        await Task.yield()
                        review()
                    }
                }
                .accessibilityIdentifier("site-control-review-certificate")
            }
        }
    }
}
