import SwiftUI

/// Where the walkthrough stands, as a bar in segments: one for each step and
/// one for starting Crest, each named beneath. The step open now fills its
/// segment in full, from its leading edge as the walkthrough reaches it, and
/// names it strongest; the steps done stay filled more faintly.
struct BrowserSetupProgressLine: View {
    // MARK: - Variables

    /// The steps the walk takes, in order.
    let steps: [BrowserSetupStep]
    /// The step open now, or nil on the welcome, before any.
    let current: BrowserSetupStep?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var titles: [LocalizedStringResource] {
        steps.map(\.title) + ["Start"]
    }

    private var reached: Int {
        current.flatMap { steps.firstIndex(of: $0) } ?? -1
    }

    // MARK: - Actions - Drawing

    var body: some View {
        HStack(alignment: .top, spacing: BrowserSetupProgressLineMetrics.gap) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                VStack(alignment: .leading, spacing: BrowserSetupProgressLineMetrics.titleSpacing) {
                    segment(index)
                    Text(title)
                        .font(.caption2.weight(index == reached ? .semibold : .medium))
                        .foregroundStyle(titleStyle(index))
                        .lineLimit(1)
                        .minimumScaleFactor(BrowserSetupProgressLineMetrics.leastTitleScale)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(BrowserSetupProgressLineMetrics.motion.unlessReducingMotion(reduceMotion), value: reached)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Setup progress"))
        .accessibilityValue(current.map { Text($0.title) } ?? Text("Welcome"))
    }

    /// A segment's track, and its fill when the walkthrough has reached it.
    private func segment(_ index: Int) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.primary.opacity(BrowserSetupProgressLineMetrics.track))
            Rectangle()
                .fill(.primary.opacity(index == reached ? 1 : BrowserSetupProgressLineMetrics.done))
                .frame(maxWidth: index <= reached ? .infinity : 0)
        }
        .frame(height: BrowserSetupProgressLineMetrics.bar)
        .clipShape(Capsule())
    }

    private func titleStyle(_ index: Int) -> AnyShapeStyle {
        if index == reached { return AnyShapeStyle(.primary) }
        return index < reached ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }
}

enum BrowserSetupProgressLineMetrics {
    static let bar: CGFloat = 3
    static let gap: CGFloat = 6
    static let titleSpacing: CGFloat = 5
    /// How strongly the empty track and a step done show.
    static let track = 0.12
    static let done = 0.4
    /// How far a step's name may shrink to stay whole.
    static let leastTitleScale: CGFloat = 0.8
    /// How a segment fills or empties as the walkthrough moves.
    static let motion = Animation.smooth(duration: 0.5)
}
