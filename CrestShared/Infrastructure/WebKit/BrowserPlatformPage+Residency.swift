import WebKit

extension BrowserPlatformPage {
    func residencyDecision(isSelected: Bool) async -> BrowserPageResidencyDecision {
        let playbackState = await withCheckedContinuation { continuation in
            webView.requestMediaPlaybackState { state in
                continuation.resume(returning: state)
            }
        }
        #if os(macOS)
            let hasPresentedVideo = pictureInPicture.protectsPageResidency
        #else
            let hasPresentedVideo = false
        #endif
        return BrowserPageResidencyDecision(
            isSelected: isSelected,
            keepsPageLoaded: navigationContext?.keepsPageLoaded == true || hasPresentedVideo,
            isPlayingMedia: playbackState == .playing,
            isCapturingMedia: webView.cameraCaptureState != .none
                || webView.microphoneCaptureState != .none
        )
    }
}
