import SwiftUI

/// A full-width native button row whose activation presents or navigates.
struct CrestFormActionRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    let systemImage: String
    var tint: Color = CrestBrandTheme.accent
    /// Already-resolved state summary such as a count or selected preset name.
    var value: String?
    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tint: Color = CrestBrandTheme.accent,
        value: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: CrestFormRowMetrics.contentSpacing) {
                CrestFormRowLabel(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    tint: tint
                )
                Spacer(minLength: CrestSpacing.small)
                if let value {
                    Text(value)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                        .lineLimit(1)
                }
                CrestFormDisclosureChevron()
            }
            .frame(minHeight: CrestFormRowMetrics.minimumHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Form Action Row") {
    Form {
        CrestFormActionRow(
            "Default Space",
            subtitle: "Choose where links open",
            systemImage: "square.grid.2x2",
            value: "Personal"
        ) {}
    }
    .formStyle(.grouped)
}
