import SwiftUI

/// The same sections and controls as the compact Form, laid out as cards in a
/// browser tab. Layout changes keep each section's identity and editing state.
struct BrowserSettingsSectionGrid<Content: View>: View {
    var allowsColumns = true
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        BrowserSettingsCardLayout(allowsColumns: allowsColumns && !dynamicTypeSize.isAccessibilitySize) {
            ForEach(sections: content) { section in
                VStack(alignment: .leading, spacing: 14) {
                    if !section.header.isEmpty {
                        section.header
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(subviews: section.content) { row in
                            row
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                        }
                    }
                    if !section.footer.isEmpty {
                        section.footer.font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .contain)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(BrowserSettingsCanvas.card, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.primary.opacity(0.065), lineWidth: 1)
                }
                .layoutValue(key: SettingsCardFullWidth.self, value: section.containerValues.settingsFullWidth)
            }
        }
        .toggleStyle(BrowserSettingsToggleStyle())
        .labeledContentStyle(BrowserSettingsLabeledContentStyle())
        .controlSize(.regular)
    }
}

extension ContainerValues {
    @Entry var settingsFullWidth = false
}

private struct SettingsCardFullWidth: LayoutValueKey {
    static let defaultValue = false
}

enum BrowserSettingsCanvas {
    static var background: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
        #else
            Color(uiColor: .systemGroupedBackground)
        #endif
    }
    static var card: Color {
        #if os(macOS)
            Color(nsColor: .windowBackgroundColor).mix(with: .primary, by: 0.035)
        #else
            Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}

/// Small cards alternate between columns. A list spans both columns and begins
/// below the tallest preceding card, preserving section order as content grows.
private struct BrowserSettingsCardLayout: Layout {
    var allowsColumns: Bool
    var spacing: CGFloat = 20
    @Environment(\.layoutDirection) private var layoutDirection

    private func columns(for width: CGFloat) -> Int { allowsColumns && width >= 860 ? 2 : 1 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let count = columns(for: width)
        let frames = frames(width: width, count: count, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(for: bounds.width)
        let frames = frames(width: bounds.width, count: count, subviews: subviews)
        for (view, frame) in zip(subviews, frames) {
            let x = layoutDirection == .rightToLeft ? bounds.width - frame.maxX : frame.minX
            view.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: .init(frame.size))
        }
    }

    private func frames(width: CGFloat, count: Int, subviews: Subviews) -> [CGRect] {
        let cardWidth = (width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var heights = Array(repeating: CGFloat.zero, count: count)
        var nextColumn = 0
        return subviews.map { view in
            let fullWidth = view[SettingsCardFullWidth.self]
            let column = nextColumn % count
            let proposedWidth = fullWidth ? width : cardWidth
            let y = fullWidth ? heights.max() ?? 0 : heights[column]
            let size = view.sizeThatFits(.init(width: proposedWidth, height: nil))
            let frame = CGRect(
                x: fullWidth ? 0 : CGFloat(column) * (cardWidth + spacing),
                y: y, width: proposedWidth, height: size.height)
            if fullWidth {
                heights = Array(repeating: frame.maxY + spacing, count: count)
                nextColumn = 0
            } else {
                heights[column] = frame.maxY + spacing
                nextColumn += 1
            }
            return frame
        }
    }
}

/// Form-like alignment without a Form's fixed-width, scroll-owning container.
struct BrowserSettingsLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                configuration.label.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                configuration.content.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                configuration.label
                configuration.content.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct BrowserSettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden().toggleStyle(.switch)
        }
    }
}
