import SwiftUI

/// A Space as Crest will show it once setup finishes, in a sheet: Crest's
/// own browser over a copy of what setup would leave, open on the Space's
/// tabs, for steps with no copy beside them. The copy opens with the sheet
/// and goes with it, and it only shows: nothing done in it carries into
/// Crest.
struct MobileSetupPreviewSheet: View {
    // MARK: - Variables

    let browser: BrowserStore
    let setup: BrowserManualSetupModel
    let spaceID: UUID

    @State private var draftPreview = BrowserSetupDraftPreview()
    @State private var live = MobileSetupLiveSession()
    @Environment(\.dismiss) private var dismiss

    // MARK: - Actions - Drawing

    /// The sheet's own heading rather than a navigation bar's, which would
    /// take the copy's toolbar for its own.
    var body: some View {
        VStack(spacing: MobileSetupPreviewSheetMetrics.inset) {
            HStack {
                Text("Preview")
                    .font(CrestTypography.display(MobileSetupPreviewSheetMetrics.titleSize))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: CrestSpacing.small)
                Button("Done") { dismiss() }
                    .buttonStyle(.crestSecondary)
                    .accessibilityIdentifier(BrowserSetupAccessibilityID.previewDone)
            }
            .padding(.horizontal, CrestSpacing.small)
            MobileSetupLiveWindow(session: live, cornerRadius: MobileSetupPreviewSheetMetrics.cornerRadius)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(MobileSetupPreviewSheetMetrics.inset)
        .background { BrowserSetupPaper().ignoresSafeArea() }
        .tint(CrestBrandTheme.accent)
        .onAppear(perform: open)
        .onDisappear(perform: live.close)
    }

    // MARK: - Mutators

    /// Opens the copy on what setup would leave, showing the Space.
    private func open() {
        guard let preview = draftPreview.preview(of: setup, in: browser) else { return }
        live.show(preview.seed(wearing: nil), images: preview.images, spaceID: spaceID)
    }
}

enum MobileSetupPreviewSheetMetrics {
    static let cornerRadius: CGFloat = 28
    static let inset: CGFloat = 16
    static let titleSize: CGFloat = 24
}
