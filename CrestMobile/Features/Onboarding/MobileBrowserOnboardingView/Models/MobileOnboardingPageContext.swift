import SwiftUI

struct MobileOnboardingPageContext {
    let step: MobileBrowserOnboardingStep
    let welcomeAction: BrowserOnboardingWelcomeAction
    let welcomePrimaryTitle: String
    let welcomeStatus: String
    let previewWidth: CGFloat
    let personalSpace: BrowserSpace
    let workSpace: BrowserSpace
    let featureCloseTitle: String?
    let featureCloseAction: (() -> Void)?
    let plan: Binding<BrowserManualSetupPlan>
    let selectedSpaceID: Binding<SpaceID?>
    let existingSession: BrowserSession
    let horizontalSizeClass: UserInterfaceSizeClass?
    let errorMessage: String?
    let setupSecondaryTitle: String
    let welcomePrimaryAction: () -> Void
    let advance: () -> Void
    let setupSecondaryAction: () -> Void
    let finish: () -> Void
    let addSpace: () -> Void
    let customize: (SpaceID) -> Void
    let remove: (SpaceID) -> Void
    let close: () -> Void
    let reviewFeatures: () -> Void
}
