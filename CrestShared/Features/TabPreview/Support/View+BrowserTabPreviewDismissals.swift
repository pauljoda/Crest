import SwiftUI

extension View {
    // MARK: - Actions - Tab Preview

    /// Takes `preview`'s card down when the window shows another Space or the
    /// one it shows locks, and has `pictures` keep no picture of a locked
    /// Space's tabs, the same on every platform.
    func browserTabPreviewDismissals(
        _ preview: BrowserTabPreviewState, browser: BrowserStore, spaceAccess: BrowserSpaceAccessController,
        pictures: BrowserTabPictures
    ) -> some View {
        onChange(of: browser.shownSpace?.id) { preview.dismiss() }
            .onChange(of: browser.shownSpace.map(spaceAccess.isLocked) ?? false) { _, isLocked in
                if isLocked { preview.dismiss() }
            }
            .onAppear {
                pictures.follow { spaceAccess.isLocked($0) }
            }
    }
}
