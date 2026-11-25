import SwiftUI

/// The downloads started in a Quick Window, which has no sidebar for them to
/// fly to, as cards in its bottom-leading corner. Each shows its file's
/// progress and, once finished, says so as the window's notice does and shows
/// the file in Finder when pressed, until it leaves a moment after its
/// download ends.
struct BrowserMacDownloadTrayLayer: View {
    // MARK: - Variables

    /// The downloads the window shows.
    let tray: BrowserMacDownloadTrayState
    /// The downloads of the window's browsing mode, whose records say how far
    /// each one is.
    let downloadCenter: BrowserDownloadCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            ForEach(shownDownloads) { download in
                BrowserMacDownloadTrayCard(download: download) { tray.dismiss(download.id) }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: CrestMotion.entranceScale, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .padding(CrestSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(CrestMotion.floatingPane.unlessReducingMotion(reduceMotion), value: tray.downloadIDs)
        .onChange(of: tray.downloadIDs) { shown, showing in
            // Tells VoiceOver a download started.
            guard showing.contains(where: { !shown.contains($0) }) else { return }
            AccessibilityNotification.Announcement(String(localized: "Download started")).post()
        }
    }

    /// The records of the downloads the tray shows, oldest first. One whose
    /// record is gone is no longer drawn.
    private var shownDownloads: [DownloadState] {
        tray.downloadIDs.compactMap(downloadCenter.item)
    }
}
