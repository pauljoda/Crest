import SwiftUI

struct BrowserCredentialImportWarningRows: View {
    let warnings: [CredentialRowWarning]

    var body: some View {
        CrestSettingsGroup(
            "Warnings",
            footnote:
                "These credentials are valid and will be imported. Review the security limitation before continuing."
        ) {
            ForEach(warnings, id: \.rowNumber) { warning in
                BrowserCredentialImportNoticeRow(
                    rowNumber: warning.rowNumber,
                    message: String(localized: warning.caution.message),
                    tint: CrestColor.warning,
                    fill: CrestColor.warningFill
                )
            }
        }
    }
}
