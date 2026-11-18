import SwiftUI

/// The pages of setup's steps that `MobileSetupView` does not draw: the
/// tour of Crest's features, and bringing tabs in on a Mac.
struct MobileOnboardingCurrentPage: View, BrowserOnboardingPages {
    let context: MobileOnboardingPageContext

    var body: some View {
        context.step.page(in: self)
    }

    // MARK: - Pages

    /// `MobileSetupView` draws the welcome.
    func welcomePage() -> some View { EmptyView() }

    func featureSpacesPage() -> some View {
        MobileOnboardingSpacesFeaturePage(
            previewWidth: context.previewWidth,
            personalSpace: context.personalSpace,
            workSpace: context.workSpace,
            secondaryTitle: context.featureCloseTitle,
            secondaryAction: context.featureCloseAction,
            primaryAction: context.advance
        )
    }

    func featureTabsPage() -> some View {
        MobileOnboardingTabsFeaturePage(
            workSpace: context.workSpace,
            secondaryTitle: context.featureCloseTitle,
            secondaryAction: context.featureCloseAction,
            primaryAction: context.advance
        )
    }

    func featureSyncPage() -> some View {
        MobileOnboardingSyncFeaturePage(
            secondaryTitle: context.featureCloseTitle,
            secondaryAction: context.featureCloseAction,
            primaryAction: context.advance
        )
    }

    func importBrowserPage() -> some View {
        MobileOnboardingMacImportPage(
            close: context.close,
            reviewFeatures: context.reviewFeatures
        )
    }

    /// `MobileSetupView` draws the look.
    func lookPage() -> some View { EmptyView() }

    /// Touch setup has no page for reviewing an import.
    func reviewPage() -> some View { EmptyView() }

    /// `MobileSetupView` draws the manual setup.
    func manualSetupPage() -> some View { EmptyView() }

    /// Touch setup has no completion page.
    func completePage() -> some View { EmptyView() }
}
