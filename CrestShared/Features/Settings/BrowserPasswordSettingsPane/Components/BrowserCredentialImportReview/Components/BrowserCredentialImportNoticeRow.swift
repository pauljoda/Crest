import SwiftUI

/// A row of the file the review warns about or rejects: the row's number on
/// a tag washed in its status, then what is wrong with it.
struct BrowserCredentialImportNoticeRow: View {
    let rowNumber: Int
    let message: String
    /// The status's colour, which the row's number is written in.
    let tint: Color
    /// The status's wash, under the row's number.
    let fill: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
            Text("Row \(rowNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, CrestSpacing.small)
                .padding(.vertical, CrestSpacing.extraExtraSmall)
                .background(fill, in: .capsule)
                .frame(
                    minWidth: BrowserCredentialImportReviewMetrics.rowNumberWidth,
                    alignment: .leading
                )
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCredentialImportNoticeRow(
            rowNumber: 3, message: "This account already has a saved password.", tint: CrestColor.warning,
            fill: CrestColor.warningFill
        ).padding().frame(width: 400)
    }
#endif
