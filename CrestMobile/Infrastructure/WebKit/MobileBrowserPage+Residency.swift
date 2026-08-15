import WebKit

extension MobileBrowserPage {
    func residencyDecision(isSelected: Bool) async -> BrowserPageResidencyDecision {
        let playbackState = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { state in
                continuation.resume(returning: state)
            }
        }
        return BrowserPageResidencyDecision(
            isSelected: isSelected,
            keepsPageLoaded: navigationContext?.keepsPageLoaded == true,
            isPlayingMedia: playbackState == .playing,
            isCapturingMedia: webView.cameraCaptureState != .none
                || webView.microphoneCaptureState != .none
        )
    }
}
