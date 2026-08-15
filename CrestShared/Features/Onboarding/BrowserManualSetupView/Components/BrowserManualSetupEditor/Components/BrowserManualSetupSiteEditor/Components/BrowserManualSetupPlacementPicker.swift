import SwiftUI

struct BrowserManualSetupPlacementPicker: View {
    @Bindable var model: BrowserManualSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("Put new sites in")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Picker("Put new sites in", selection: $model.placement) {
                ForEach(
                    BrowserManualSetupPlacementPresentation.choices,
                    id: \.self
                ) { choice in
                    Label(
                        BrowserManualSetupPlacementPresentation.label(for: choice),
                        systemImage:
                            BrowserManualSetupPlacementPresentation
                            .symbol(for: choice)
                    )
                    .tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .tint(CrestBrandTheme.accent)
            .accessibilityLabel("Put new sites in")
        }
    }
}

#Preview("Manual Setup Placement Picker") {
    BrowserManualSetupPlacementPicker(
        model: BrowserManualSetupPreviewFixture.model()
    )
    .frame(width: 420)
    .padding()
}
