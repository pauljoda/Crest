import SwiftUI

/// A display heading and decorative symbol for a settings section.
struct CrestSettingsSectionHeading: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CrestBrandTheme.accent)
                .frame(width: 34, height: 34)
                .background(CrestBrandTheme.accent.opacity(0.10), in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title)
                .font(CrestTypography.displaySection)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .textCase(nil)
    }
}

// Keep native Form sections and settings cards on the same heading treatment.
extension Section where Parent == CrestSettingsSectionHeading, Footer == EmptyView {
    @MainActor
    init(
        _ title: LocalizedStringKey, systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.init(content: content) {
            CrestSettingsSectionHeading(title: title, systemImage: systemImage)
        }
    }
}

extension View {
    func crestSettingsCardHeader() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                .primary.opacity(0.025),
                in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(.primary.opacity(0.065)).frame(height: 1).allowsHitTesting(false)
            }
    }
}
