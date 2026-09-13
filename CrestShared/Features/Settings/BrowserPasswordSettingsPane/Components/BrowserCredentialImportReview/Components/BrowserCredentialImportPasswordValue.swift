import SwiftUI

struct BrowserCredentialImportPasswordValue: View {
    let label: LocalizedStringKey
    let password: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(
                    minWidth: BrowserCredentialImportReviewMetrics.passwordLabelWidth,
                    alignment: .leading
                )
            Text(verbatim: password)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .privacySensitive()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password value shown visually")
    }
}
