import SwiftUI

struct MobileOnboardingSpaceCustomizationSheet: View {
    let spaceID: SpaceID
    @Binding var plan: BrowserManualSetupPlan
    let existingSession: BrowserSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: MobileOnboardingLayout.customizationContentSpacing
                ) {
                    if let draft {
                        BrowserSpaceSidebarPreview(
                            space: MobileOnboardingSpacePreviewFactory.preview(
                                draft: draft,
                                plan: plan,
                                existingSession: existingSession,
                                includesSamples: true
                            )
                        )
                        .frame(
                            maxWidth:
                                MobileOnboardingLayout.customizationPreviewMaximumWidth
                        )
                        .frame(
                            height: MobileOnboardingLayout.customizationPreviewHeight
                        )
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(
                            BrowserMobileAccessibilityID
                                .customizationPreview
                        )

                        BrowserSpaceBrandingEditor(
                            branding: brandingBinding,
                            symbol: symbolBinding,
                            compact: true,
                            showsPreview: false
                        )
                        .accessibilityIdentifier(
                            BrowserMobileAccessibilityID
                                .customizationControls
                        )
                    }
                }
                .padding(MobileOnboardingLayout.customizationContentPadding)
            }
            .navigationTitle("Customize Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var draft: BrowserManualSetupSpaceDraft? {
        plan.spaces.first { $0.id == spaceID }
    }

    private var brandingBinding: Binding<BrowserSpaceBranding> {
        Binding(
            get: {
                draft?.customization.branding
                    ?? .neutralImport(symbol: "square.grid.2x2")
            },
            set: { plan.setSpaceBranding($0, for: spaceID) }
        )
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { draft?.customization.symbol ?? "square.grid.2x2" },
            set: { symbol in
                plan.setSpaceIdentity(
                    name: draft?.customization.name ?? "Space",
                    symbol: symbol,
                    for: spaceID
                )
            }
        )
    }
}
