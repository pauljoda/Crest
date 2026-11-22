import SwiftUI

/// One of the review's totals, as a settings row: what it counts, and the
/// count beside its status glyph.
struct BrowserCredentialImportMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        CrestSettingRow(title) {
            Label {
                Text("\(value)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("Import totals") {
        Form {
            BrowserCredentialImportMetric(
                title: "Accounts", value: 24, systemImage: "person.crop.circle", color: CrestColor.success)
            BrowserCredentialImportMetric(
                title: "Warnings", value: 2, systemImage: "exclamationmark.triangle", color: CrestColor.warning)
        }
        .crestSettingsForm()
        .frame(width: 420, height: 200)
    }
#endif
