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
                VStack(alignment: .leading, spacing: 0) {
                    if !section.header.isEmpty {
                        section.header
                            .font(CrestTypography.displaySection)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                            .crestSettingsCardHeader()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(subviews: section.content) { row in
                            row
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                        }
                        if !section.footer.isEmpty {
                            section.footer
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .accessibilityElement(children: .contain)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(BrowserSettingsCanvas.card, in: .rect(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.primary.opacity(0.065), lineWidth: 1)
                        .allowsHitTesting(false)
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

    struct Cache {
        var width: CGFloat?
        var columns = 0
        var spacing: CGFloat = 0
        var frames: [CGRect] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = Cache()
    }

    private func columns(for width: CGFloat) -> Int { allowsColumns && width >= 860 ? 2 : 1 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 600
        let count = columns(for: width)
        let frames = measuredFrames(width: width, count: count, subviews: subviews, cache: &cache)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let count = columns(for: bounds.width)
        let frames = measuredFrames(width: bounds.width, count: count, subviews: subviews, cache: &cache)
        for (view, frame) in zip(subviews, frames) {
            let x = layoutDirection == .rightToLeft ? bounds.width - frame.maxX : frame.minX
            view.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: .init(frame.size))
        }
    }

    // Measurement and placement share frames until SwiftUI invalidates the
    // children or the available width changes. Scrolling only changes origin.
    private func measuredFrames(width: CGFloat, count: Int, subviews: Subviews, cache: inout Cache) -> [CGRect] {
        if cache.width != width || cache.columns != count || cache.spacing != spacing {
            cache.frames = frames(width: width, count: count, subviews: subviews)
            cache.width = width
            cache.columns = count
            cache.spacing = spacing
        }
        return cache.frames
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
