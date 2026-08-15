import SwiftUI

struct BrowserImportSpaceCustomizationView: View {
    @Binding var plan: BrowserImportReviewPlan
    let spaceID: SpaceID
    let previewSpace: BrowserSpace?
    let done: () -> Void

    @ViewBuilder
    var body: some View {
        if review != nil {
            BrowserImportSpaceCustomizationContent(
                previewSpace: previewSpace,
                name: nameBinding,
                symbol: symbolBinding,
                branding: brandingBinding,
                done: done
            )
        }
    }

    private var review: BrowserImportSpaceReview? {
        plan.spaces.first { $0.id == spaceID }
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { review?.customization.name ?? previewSpace?.name ?? "" },
            set: { value in
                guard let review else { return }
                plan.setSpaceIdentity(
                    name: value,
                    symbol: review.customization.symbol,
                    for: spaceID
                )
            }
        )
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: { review?.customization.symbol ?? previewSpace?.symbol ?? "" },
            set: { value in
                guard let review else { return }
                plan.setSpaceIdentity(
                    name: review.customization.name,
                    symbol: value,
                    for: spaceID
                )
            }
        )
    }

    private var brandingBinding: Binding<BrowserSpaceBranding> {
        Binding(
            get: {
                review?.customization.branding
                    ?? previewSpace?.branding
                    ?? .initial(accent: .indigo, symbol: "square.grid.2x2")
            },
            set: { branding in
                guard review != nil else { return }
                plan.setSpaceBranding(branding, for: spaceID)
            }
        )
    }
}

#Preview("Space Customization") {
    @Previewable @State var plan = BrowserImportPreviewFixture.plan

    BrowserImportSpaceCustomizationView(
        plan: $plan,
        spaceID: BrowserImportPreviewFixture.review.id,
        previewSpace: BrowserImportPreviewFixture.sourceSpace,
        done: {}
    )
    .frame(width: 1_080, height: 720)
}
