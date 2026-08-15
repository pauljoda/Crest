import SwiftUI

struct BrowserOnboardingReviewDestinationPicker: View {
    let spaces: [BrowserSpace]
    @Binding var destination: BrowserImportDestination
    let destinationName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Into Crest")
                .font(.caption)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

            Picker("Destination Space", selection: $destination) {
                Text("New Space").tag(BrowserImportDestination.newSpace)
                ForEach(spaces) { space in
                    Text(space.name).tag(
                        BrowserImportDestination.existing(space.id)
                    )
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.regular)
            .tint(BrowserOnboardingPalette.coral)
            .frame(width: 80)
            .accessibilityValue(destinationName)
        }
    }
}

#Preview("Review Destination Picker") {
    @Previewable @State var destination = BrowserImportDestination.newSpace

    BrowserOnboardingReviewDestinationPicker(
        spaces: BrowserOnboardingWindowPreviewFixture.session.spaces,
        destination: $destination,
        destinationName: "New Space"
    )
    .padding()
}
