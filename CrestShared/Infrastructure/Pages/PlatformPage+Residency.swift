import Foundation

extension BrowserPlatformPage {
    /// The page's first navigation settled: a document finished, the
    /// navigation failed, or the page stopped loading a document it shows.
    /// An idle page off screen counts its idle time from then.
    var hasSettledNavigation: Bool {
        completedNavigationCount > 0 || live.failure != nil || (live.url != nil && !live.isLoading)
    }

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
                || media?.contains(.pictureInPicture) == true || media == nil,
            isPlayingMedia: media?.contains(.playing) == true,
            isCapturingMedia: media?.contains(.capturing) == true
        )
    }
}
