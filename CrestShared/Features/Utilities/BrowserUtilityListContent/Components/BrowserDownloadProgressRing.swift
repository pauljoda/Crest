import SwiftUI

/// A download's progress drawn as a ring: an arc that fills while the size is
/// known, and a quarter arc that turns while it is not, so a download of
/// unknown size never reads as stuck at its start. With Reduce Motion the
/// quarter arc holds still.
struct BrowserDownloadProgressRing: View {
    // MARK: - Static Variables

    /// How much of the ring the arc of an unknown size covers.
    private static let indeterminateArc = 0.25

    /// The shortest arc a known progress draws, so a download that has just
    /// begun still shows one.
    private static let minimumArc = 0.03

    /// How long the arc of an unknown size takes to go round once.
    private static let revolution: TimeInterval = 1

    // MARK: - Variables

    /// The finished fraction, or nil while it cannot be known.
    let fraction: Double?
    let tint: Color
    let lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(CrestOpacity.border), lineWidth: lineWidth)
            if let fraction {
                arc(to: max(min(fraction, 1), Self.minimumArc))
                    .animation(CrestMotion.loadingProgress.unlessReducingMotion(reduceMotion), value: fraction)
            } else if reduceMotion {
                arc(to: Self.indeterminateArc)
            } else {
                TimelineView(.animation) { context in
                    arc(to: Self.indeterminateArc)
                        .rotationEffect(.degrees(turn(at: context.date)))
                }
            }
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }

    // MARK: - Actions - Drawing

    /// The tinted arc from the top of the ring to `end`, a fraction of the way
    /// round.
    private func arc(to end: Double) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    /// The angle, in degrees, the arc of an unknown size has turned to at
    /// `date`.
    private func turn(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.revolution) / Self.revolution * 360
    }
}

#if DEBUG
    #Preview("Known and unknown size") {
        HStack(spacing: CrestSpacing.large) {
            BrowserDownloadProgressRing(fraction: 0.4, tint: .accentColor, lineWidth: 2.5)
                .frame(width: 32, height: 32)
            BrowserDownloadProgressRing(fraction: nil, tint: .accentColor, lineWidth: 2.5)
                .frame(width: 32, height: 32)
        }
        .padding()
    }
#endif
