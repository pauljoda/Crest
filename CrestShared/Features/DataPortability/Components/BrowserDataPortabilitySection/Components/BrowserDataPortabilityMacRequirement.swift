import SwiftUI

struct BrowserDataPortabilityMacRequirement: View {
    var body: some View {
        HStack(alignment: .top, spacing: CrestSpacing.medium) {
            CrestIconTile(
                systemImage: "macbook.and.iphone",
                color: .blue,
                size: 40,
                symbolSize: 18,
                cornerRadius: CrestRadius.control
            )
            .accessibilityHidden(true)

            Text(
                "Import from another browser requires Crest for macOS. Once imported, your Spaces and tabs sync to this device with iCloud."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("browser-import-macos-requirement")
        }
        .padding(.vertical, CrestSpacing.extraSmall)
    }
}

#Preview("macOS Import Requirement") {
    Form {
        BrowserDataPortabilityMacRequirement()
    }
    .frame(width: 620)
}
