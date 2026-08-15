import Foundation

struct BrowserPageResidencyDecision: Equatable, Sendable {
    let isSelected: Bool
    let keepsPageLoaded: Bool
    let isPlayingMedia: Bool
    let isCapturingMedia: Bool

    init(
        isSelected: Bool,
        keepsPageLoaded: Bool,
        isPlayingMedia: Bool,
        isCapturingMedia: Bool
    ) {
        self.isSelected = isSelected
        self.keepsPageLoaded = keepsPageLoaded
        self.isPlayingMedia = isPlayingMedia
        self.isCapturingMedia = isCapturingMedia
    }

    var allowsAutomaticUnload: Bool {
        !isSelected && !keepsPageLoaded && !isPlayingMedia && !isCapturingMedia
    }
}
