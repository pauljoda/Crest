import WebKit

extension BrowserPlatformPage {
    func residencyDecision(isSelected: Bool) async -> BrowserPageResidencyDecision {
        let media = await pageEngine.mediaActivity()
        #if os(macOS)
        let hasPresentedVideo = pictureInPicture?.protectsPageResidency == true
        #else
        let hasPresentedVideo = false
        #endif
        return BrowserPageResidencyDecision(
            isSelected: isSelected,
            keepsPageLoaded: navigationContext?.keepsPageLoaded == true || hasPresentedVideo
                || media?.hasPictureInPicture == true || media == nil,
            isPlayingMedia: media?.isPlaying == true,
            isCapturingMedia: media?.isCapturing == true
        )
    }
}
