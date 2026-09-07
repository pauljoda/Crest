import SwiftUI

struct MobileOnboardingCurrentPage: View {
    let context: MobileOnboardingPageContext

    @ViewBuilder
    var body: some View {
        switch context.step {
        case .welcome:
            MobileOnboardingWelcomePage(
                action: context.welcomeAction,
                primaryTitle: context.welcomePrimaryTitle,
                status: context.welcomeStatus,
                primaryAction: context.welcomePrimaryAction
            )
        case .featureSpaces:
            MobileOnboardingSpacesFeaturePage(
                previewWidth: context.previewWidth,
                personalSpace: context.personalSpace,
                workSpace: context.workSpace,
                secondaryTitle: context.featureCloseTitle,
                secondaryAction: context.featureCloseAction,
                primaryAction: context.advance
            )
        case .featureTabs:
            MobileOnboardingTabsFeaturePage(
                workSpace: context.workSpace,
                secondaryTitle: context.featureCloseTitle,
                secondaryAction: context.featureCloseAction,
                primaryAction: context.advance
            )
        case .featureSync:
            MobileOnboardingSyncFeaturePage(
                secondaryTitle: context.featureCloseTitle,
                secondaryAction: context.featureCloseAction,
                primaryAction: context.advance
            )
        case .manualSetup:
            BrowserSpaceSetupWizard(
                plan: context.plan,
                selectedSpaceID: context.selectedSpaceID,
                errorMessage: context.errorMessage,
                opensGettingStarted: context.opensGettingStarted,
                back: context.setupSecondaryAction,
                finish: context.finish
            )
        case .macImport:
            MobileOnboardingMacImportPage(
                close: context.close,
                reviewFeatures: context.reviewFeatures
            )
        }
    }
}
