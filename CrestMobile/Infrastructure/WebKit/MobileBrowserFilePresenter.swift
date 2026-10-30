import UIKit

/// Hands a file to the share sheet or the Files picker, on a device without a
/// Finder, in `window`, the one showing the page the file came from. A file
/// staged in `temporaryDirectoryURL` for the export is removed once the
/// person is done with it.
struct MobileBrowserFilePresenter: BrowserFileDestinationOpener {
    // MARK: - Variables

    let temporaryDirectoryURL: URL?
    let window: UIWindow?

    // MARK: - Actions - Presenting

    /// A device without a Finder exports instead of opening.
    func openFile(_ fileURL: URL) {}

    /// A device without a Finder exports instead of revealing.
    func revealFile(_ fileURL: URL) {}

    func shareFile(_ fileURL: URL) {
        let controller = MobileBrowserExportActivityController(
            fileURL: fileURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
        MobileBrowserDialogPresenter.present(controller, in: window) {
            controller.cleanupTemporaryFiles()
        }
    }

    func saveFileToFiles(_ fileURL: URL) {
        if let temporaryDirectoryURL {
            let controller = MobileBrowserExportPickerController(
                fileURL: fileURL,
                temporaryDirectoryURL: temporaryDirectoryURL
            )
            MobileBrowserDialogPresenter.present(controller, in: window) {
                controller.cleanupTemporaryFiles()
            }
            return
        }
        let controller = UIDocumentPickerViewController(
            forExporting: [fileURL],
            asCopy: true
        )
        controller.shouldShowFileExtensions = true
        MobileBrowserDialogPresenter.present(controller, in: window, fallback: {})
    }
}
