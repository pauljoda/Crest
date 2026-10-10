import Foundation

extension ShowPictureInPictureCaption {
    /// macOS presents WebKit's Picture in Picture with its own controls, which
    /// take no caption from Crest.
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        false
    }
}
