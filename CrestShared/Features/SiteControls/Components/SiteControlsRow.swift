import SwiftUI

/// A row of Site Controls that runs something or opens a page: a symbol, a
/// title with an optional line under it, and what it shows on its trailing
/// side, such as its value and a chevron.
struct SiteControlsRow<Trailing: View>: View {
    let title: Text
    var symbol: String?
    var subtitle: Text?
    var symbolTint: Color?
    var titleTint: Color?
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        Button(action: action) {
            SiteControlsRowLabel(
                title: title, symbol: symbol, subtitle: subtitle, symbolTint: symbolTint, titleTint: titleTint,
                trailing: trailing)
        }
        .buttonStyle(SiteControlsRowButtonStyle())
    }
}

/// A row's button: the design system's hover and press surface over the
/// whole row, reaching past its content on either side so the row's text
/// stays in line with the rest, and no further than the row's own height, so
/// rows stacked together never overlap.
struct SiteControlsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, CrestFormRowButtonStyle.reach)
            .contentShape(.rect)
            .crestHoverSurface(cornerRadius: CrestRadius.compact, isPressed: configuration.isPressed)
            .padding(.horizontal, -CrestFormRowButtonStyle.reach)
    }
}

extension SiteControlsRow where Trailing == SiteControlsRowValue {
    /// A row that opens a page, showing `value` before its chevron, or
    /// `compactValue` where `value` does not fit.
    init(
        _ title: LocalizedStringResource, symbol: String, value: String? = nil, compactValue: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(title: Text(title), symbol: symbol, action: action) {
            SiteControlsRowValue(value: value, compactValue: compactValue, showsChevron: true)
        }
    }
}

/// A row's content, laid out the same whether it is pressed or only read,
/// with room above and below it inside the row for a hover surface.
struct SiteControlsRowLabel<Trailing: View>: View {
    let title: Text
    var symbol: String?
    var subtitle: Text?
    var symbolTint: Color?
    var titleTint: Color?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        HStack(spacing: CrestSpacing.small + 1) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: metrics.glyphSize * 0.9, weight: .regular))
                    .foregroundStyle(symbolTint ?? .secondary)
                    .frame(width: metrics.glyphSize + 4)
            }
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(metrics.rowFont)
                    .foregroundStyle(titleTint ?? .primary)
                    .lineLimit(1)
                if let subtitle {
                    subtitle
                        .font(metrics.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: metrics.rowHeight - metrics.rowInset * 2)
        .padding(.vertical, metrics.rowInset)
        .contentShape(.rect)
    }
}

/// What a row shows on its trailing side: its value in the secondary color,
/// or a shorter one where it does not fit, then a chevron when it opens a
/// page.
struct SiteControlsRowValue: View {
    let value: String?
    var compactValue: String?
    var showsChevron = false

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall + 2) {
            if let value {
                ViewThatFits(in: .horizontal) {
                    text(value)
                    if let compactValue { text(compactValue) }
                }
            }
            if showsChevron {
                CrestFormDisclosureChevron()
            }
        }
    }

    private func text(_ value: String) -> some View {
        Text(verbatim: value)
            .font(metrics.valueFont)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A label over a section of Site Controls, in the same type as the text
/// button on its trailing side, which may stand a little taller.
struct SiteControlsSectionHeader<Trailing: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        HStack {
            Text(title)
                .font(metrics.sectionFont)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: CrestSpacing.small)
            trailing()
        }
        .padding(.leading, 2)
        .frame(height: metrics.sectionHeight)
    }
}

extension SiteControlsSectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringResource) {
        self.init(title: title) { EmptyView() }
    }
}

/// A text button in Crest blue, such as Edit, Manage or Back, with the
/// design system's hover and press surface.
struct SiteControlsTextButtonStyle: ButtonStyle {
    @Environment(\.siteControlsMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(metrics.sectionFont)
            .foregroundStyle(CrestBrandTheme.accentText)
            .padding(.horizontal, 5)
            .frame(minHeight: 20)
            .contentShape(.rect)
            .crestHoverSurface(cornerRadius: 5, isPressed: configuration.isPressed)
    }
}

/// A switch in Site Controls, tinted Crest blue while it is on.
struct SiteControlsSwitch: View {
    let title: Text
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) { title }
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(CrestBrandTheme.accent)
            #if os(macOS)
                .controlSize(.mini)
            #endif
    }
}

/// A group of a page's rows under an optional caps label, with an optional
/// line under them.
struct SiteControlsPageSection<Content: View>: View {
    var title: LocalizedStringResource?
    var footer: Text?
    @ViewBuilder var content: () -> Content

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                SiteControlsSectionHeader(title: title)
                    .padding(.horizontal, CrestFormRowButtonStyle.reach)
                    .padding(.bottom, 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, CrestFormRowButtonStyle.reach)
            if let footer {
                footer
                    .font(metrics.detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, CrestFormRowButtonStyle.reach)
                    .padding(.top, 2)
            }
        }
    }
}
