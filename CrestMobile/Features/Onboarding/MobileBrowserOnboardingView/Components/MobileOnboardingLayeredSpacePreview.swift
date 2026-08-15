import SwiftUI

struct MobileOnboardingLayeredSpacePreview: View {
    let previewWidth: CGFloat
    let personalSpace: BrowserSpace
    let workSpace: BrowserSpace

    var body: some View {
        ZStack {
            BrowserSpaceSidebarPreview(space: personalSpace)
                .frame(
                    width: min(
                        previewWidth,
                        MobileOnboardingLayout.sidebarPreviewMaximumWidth
                    ),
                    height: MobileOnboardingLayout.sidebarPreviewHeight
                )
                .offset(
                    x: MobileOnboardingLayout.personalPreviewHorizontalOffset,
                    y: MobileOnboardingLayout.personalPreviewVerticalOffset
                )
                .opacity(MobileOnboardingLayout.personalPreviewOpacity)

            BrowserSpaceSidebarPreview(space: workSpace)
                .frame(
                    width: min(
                        previewWidth,
                        MobileOnboardingLayout.sidebarPreviewMaximumWidth
                    ),
                    height: MobileOnboardingLayout.sidebarPreviewHeight
                )
                .offset(
                    x: MobileOnboardingLayout.workPreviewHorizontalOffset,
                    y: MobileOnboardingLayout.workPreviewVerticalOffset
                )
        }
        .frame(height: MobileOnboardingLayout.layeredPreviewHeight)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Onboarding Layered Spaces") {
    let fixture = MobileBrowserPreviewFixture()
    MobileOnboardingLayeredSpacePreview(
        previewWidth: MobileOnboardingLayout.compactPreviewWidth,
        personalSpace: fixture.alternateSpace,
        workSpace: fixture.space
    )
}
