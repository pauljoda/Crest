import SwiftUI

struct BrowserReloadFeedbackIcon: View {
    let systemName: String
    let pulse: Int
    let animates: Bool
    let pointSize: CGFloat
    let feedbackDidComplete: (Int) -> Void

    @State private var rotation = BrowserReloadFeedbackPolicy.restingRotation
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        BrowserChromeSymbolLabel(
            systemName: systemName,
            pointSize: pointSize
        )
        .rotationEffect(.degrees(rotation), anchor: .center)
        .onChange(of: pulse) {
            playFeedback()
        }
        .onChange(of: animates) {
            updateAnimationAvailability()
        }
        .onDisappear(perform: cancelFeedback)
    }

    private func playFeedback() {
        cancelFeedback()
        resetRotation()
        guard animates else {
            feedbackDidComplete(pulse)
            return
        }

        let playingPulse = pulse
        feedbackTask = Task { @MainActor in
            withAnimation(CrestMotion.reloadTurnOut) {
                rotation = BrowserReloadFeedbackPolicy.pressedRotation
            }
            try? await Task.sleep(for: BrowserReloadFeedbackPolicy.phaseDuration)
            guard !Task.isCancelled else { return }
            withAnimation(
                CrestMotion.reloadTurnIn,
                completionCriteria: .logicallyComplete
            ) {
                rotation = BrowserReloadFeedbackPolicy.restingRotation
            } completion: {
                feedbackDidComplete(playingPulse)
            }
        }
    }

    private func updateAnimationAvailability() {
        guard !animates else { return }
        cancelFeedback()
        resetRotation()
        feedbackDidComplete(pulse)
    }

    private func cancelFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
    }

    private func resetRotation() {
        withTransaction(Transaction(animation: nil)) {
            rotation = BrowserReloadFeedbackPolicy.restingRotation
        }
    }
}

#Preview("Reload Feedback Icon") {
    BrowserReloadFeedbackIcon(
        systemName: "arrow.clockwise",
        pulse: 0,
        animates: false,
        pointSize: BrowserReloadFeedbackPolicy.symbolPointSize,
        feedbackDidComplete: { _ in }
    )
    .padding()
}
