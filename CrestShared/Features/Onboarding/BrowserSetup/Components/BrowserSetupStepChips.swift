import SwiftUI

/// The walk's steps as chips of colored paper, numbered, each in its step's
/// brand color and set at a slight angle, as Crest's website names its
/// sections. On the welcome every chip shows whole, as what setup will do.
/// Once the walk starts, the chip of the step open now names it and lifts,
/// the steps done keep their color, and the steps ahead wait as plain paper,
/// so the row reads as how far the walk has come. Where the steps can be
/// opened, each chip opens its step.
struct BrowserSetupStepChips: View {
    // MARK: - Types

    /// How large the chips are, and whether every chip names its step.
    struct Size {
        /// Every chip whole and large, as the welcome shows them.
        static let welcome = Size(
            height: 46, title: 16, number: 12, radius: 16, padding: 18, gap: 10, namesEvery: true)
        /// Small chips over the steps, only the step open now named.
        static let compact = Size(
            height: 30, title: 13, number: 11, radius: 10, padding: 11, gap: 6, namesEvery: false)

        let height: CGFloat
        let title: CGFloat
        let number: CGFloat
        let radius: CGFloat
        let padding: CGFloat
        let gap: CGFloat
        /// Whether every chip names its step, rather than only the one open.
        let namesEvery: Bool
    }

    // MARK: - Variables

    /// The steps the walk takes, in order, ending with starting Crest.
    let steps: [BrowserSetupStep]
    /// The step open now, or nil on the welcome, before any.
    let current: BrowserSetupStep?
    let size: Size
    /// Opens a step, when the chips lead to their steps.
    var open: ((BrowserSetupStep) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reached: Int {
        current.flatMap { steps.firstIndex(of: $0) } ?? -1
    }

    // MARK: - Actions - Drawing

    var body: some View {
        if let open {
            chips { index, step in
                Button {
                    open(step)
                } label: {
                    chip(step, at: index)
                }
                .buttonStyle(BrowserSetupStepChipButtonStyle())
                .accessibilityLabel(Text(step.title))
                .accessibilityAddTraits(index == reached ? .isSelected : [])
                .accessibilityIdentifier("setup-step-\(step.name)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Setup steps"))
        } else {
            chips { index, step in chip(step, at: index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Setup progress"))
                .accessibilityValue(current.map { Text($0.title) } ?? Text("Welcome"))
        }
    }

    /// The chips in a row, each as `content` draws it, set at its angle.
    private func chips<Chip: View>(@ViewBuilder _ content: @escaping (Int, BrowserSetupStep) -> Chip) -> some View {
        BrowserSetupStepChipsFlow(gap: size.gap) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, step in
                content(index, step)
                    .rotationEffect(.degrees(BrowserSetupStepChipsMetrics.tilt(at: index)))
            }
        }
        .animation(BrowserSetupStepChipsMetrics.motion.unlessReducingMotion(reduceMotion), value: reached)
    }

    /// A step's chip: its number, and its name where the chip names it, on
    /// its color once the walk has reached it, or on paper while it waits.
    private func chip(_ step: BrowserSetupStep, at index: Int) -> some View {
        let isOpen = index == reached
        let isColored = size.namesEvery || index <= reached
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        return HStack(spacing: BrowserSetupStepChipsMetrics.numberSpacing) {
            Text(verbatim: String(format: "%02d", index + 1))
                .font(CrestTypography.display(size.number))
                .fixedSize()
                .opacity(BrowserSetupStepChipsMetrics.numberOpacity)
            if size.namesEvery || isOpen {
                Text(step.title)
                    .font(CrestTypography.display(size.title))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: CrestMotion.entranceScale, anchor: .leading)))
            }
        }
        .foregroundStyle(isColored ? AnyShapeStyle(CrestBrandPalette.ink) : AnyShapeStyle(.secondary))
        .padding(.horizontal, size.padding)
        .frame(height: size.height)
        .background {
            if isColored {
                shape.fill(step.color)
            } else {
                shape.fill(CrestBrandTheme.surface)
                    .overlay { shape.strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
            }
        }
        .crestElevation(isOpen ? .lifted : .control)
        .scaleEffect(isOpen && !size.namesEvery ? BrowserSetupStepChipsMetrics.liftedScale : 1)
        .zIndex(isOpen ? 1 : 0)
    }
}

enum BrowserSetupStepChipsMetrics {
    /// The angles the chips sit at, in turn, as if laid down by hand.
    static let tilts: [Double] = [-2, 1.5, -1, 2]
    static let numberSpacing: CGFloat = 8
    static let numberOpacity = 0.7
    static let liftedScale: CGFloat = 1.06
    /// How the chips move as the walk does.
    static let motion = Animation.smooth(duration: 0.45)
    static let pressedScale: CGFloat = 0.95
    static let hoveredScale: CGFloat = 1.04
    static let pressMotion = Animation.smooth(duration: 0.15)

    static func tilt(at index: Int) -> Double {
        tilts[index % tilts.count]
    }
}

/// Lays the chips out in rows no wider than the room offered, each row
/// centered, so the welcome's chips wrap on a phone rather than run off it.
private struct BrowserSetupStepChipsFlow: Layout {
    // MARK: - Types

    /// The chips one row holds, and how wide and tall the row is.
    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    // MARK: - Variables

    let gap: CGFloat

    // MARK: - Actions - Layout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, within: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + gap * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + gap
            }
            y += row.height + gap
        }
    }

    // MARK: - Actions - Reading

    /// The chips in rows, each taking chips while they fit within `width`.
    private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let widened = row.indices.isEmpty ? size.width : row.width + gap + size.width
            if !row.indices.isEmpty, widened > width {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = widened
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// A chip that opens its step: it sinks a little while pressed and, under a
/// pointer, rises a little.
private struct BrowserSetupStepChipButtonStyle: ButtonStyle {
    // MARK: - Actions - Drawing

    func makeBody(configuration: Configuration) -> some View {
        BrowserSetupStepChipButton(configuration: configuration)
    }
}

private struct BrowserSetupStepChipButton: View {
    // MARK: - Variables

    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat {
        configuration.isPressed
            ? BrowserSetupStepChipsMetrics.pressedScale : isHovered ? BrowserSetupStepChipsMetrics.hoveredScale : 1
    }

    // MARK: - Actions - Drawing

    var body: some View {
        configuration.label
            .scaleEffect(scale)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(BrowserSetupStepChipsMetrics.pressMotion.unlessReducingMotion(reduceMotion), value: scale)
    }
}
