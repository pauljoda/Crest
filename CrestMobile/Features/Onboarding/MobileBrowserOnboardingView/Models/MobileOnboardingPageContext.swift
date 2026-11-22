import SwiftUI

struct MobileOnboardingPageContext {
    let step: SetupStep
    let previewWidth: CGFloat
    let personalSpace: SpaceModel
    let workSpace: SpaceModel
    let featureCloseTitle: String?
    let featureCloseAction: (() -> Void)?
    let advance: () -> Void
    let close: () -> Void
    let reviewFeatures: () -> Void
}
