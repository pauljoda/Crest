import SwiftUI

extension BrowserRootModel {
    func presentURLCopyFeedback(revision: Int, reduceMotion: Bool) {
        guard revision > 0 else { return }
        withAnimation(
            accessibleAnimation(CrestMotion.feedbackPresentation, reduceMotion)
        ) {
            visiblePageZoomFeedbackLabel = nil
            isURLCopiedFeedbackVisible = true
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserRootMetrics.urlCopyFeedbackDuration)
            guard let self,
                self.chrome.urlCopyFeedbackRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.dismissal, reduceMotion)
            ) {
                self.isURLCopiedFeedbackVisible = false
            }
        }
    }

    func presentPageZoomFeedback(revision: Int, reduceMotion: Bool) {
        guard revision > 0 else { return }
        withAnimation(
            accessibleAnimation(CrestMotion.feedbackPresentation, reduceMotion)
        ) {
            isURLCopiedFeedbackVisible = false
            visiblePageZoomFeedbackLabel = chrome.pageZoomFeedbackLabel
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserRootMetrics.urlCopyFeedbackDuration)
            guard let self,
                self.chrome.pageZoomFeedbackRevision == revision
            else { return }
            withAnimation(
                self.accessibleAnimation(CrestMotion.dismissal, reduceMotion)
            ) {
                self.visiblePageZoomFeedbackLabel = nil
            }
        }
    }
}
