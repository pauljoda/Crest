import QuickLook
import UIKit

/// Hands a file to Quick Look, the share sheet or the Files picker, on a
/// device without a Finder. A file staged in `temporaryDirectoryURL` for the
/// export is removed once the person is done with it.
struct MobileBrowserFilePresenter: BrowserFileDestinationOpener {
    // MARK: - Static Variables

    /// Where a finished download can go from its row, the first being where
    /// the row itself takes it.
    static let downloadDestinations: [BrowserUtilityDownloadDestination] = [.quickLook, .share, .files]

    // MARK: - Variables

    let temporaryDirectoryURL: URL?

    // MARK: - Actions - Presenting

    /// A device without a Finder previews instead of opening.
    func openFile(_ fileURL: URL) {}

    /// A device without a Finder previews instead of revealing.
    func revealFile(_ fileURL: URL) {}

    /// Shows the file in Quick Look, or offers it in the share sheet, where
    /// another app can open it, when Quick Look cannot show it.
    func previewFile(_ fileURL: URL) {
        guard QLPreviewController.canPreview(fileURL as NSURL) else {
            shareFile(fileURL)
            return
        }
        MobileBrowserDialogPresenter.present(MobileBrowserFilePreviewController(fileURL: fileURL), fallback: {})
    }

    func shareFile(_ fileURL: URL) {
        let controller = MobileBrowserExportActivityController(
            fileURL: fileURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
        MobileBrowserDialogPresenter.present(controller) {
            controller.cleanupTemporaryFiles()
        }
    }

    func saveFileToFiles(_ fileURL: URL) {
        if let temporaryDirectoryURL {
            let controller = MobileBrowserExportPickerController(
                fileURL: fileURL,
                temporaryDirectoryURL: temporaryDirectoryURL
            )
            MobileBrowserDialogPresenter.present(controller) {
                controller.cleanupTemporaryFiles()
            }
            return
        }
        let controller = UIDocumentPickerViewController(
            forExporting: [fileURL],
            asCopy: true
        )
        controller.shouldShowFileExtensions = true
        MobileBrowserDialogPresenter.present(controller, fallback: {})
    }
}
