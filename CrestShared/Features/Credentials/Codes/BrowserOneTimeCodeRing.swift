import SwiftUI

/// How long a one-time code has left, as a ring that empties as it runs out
/// and the seconds beside it.
struct BrowserOneTimeCodeRing: View {
    let code: BrowserOneTimeCode
    let now: Date

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: code.remaining(at: now))
                    .stroke(CrestBrandTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text(verbatim: "\(code.secondsLeft(at: now)) s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(code.secondsLeft(at: now)) seconds left")
    }
}
