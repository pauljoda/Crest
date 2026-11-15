import QuickLook
import UIKit

/// Hands a file to Quick Look, the Files app, the share sheet or the Files
/// picker, on a device without a Finder. A file staged in
/// `temporaryDirectoryURL` for the export is removed once the person is done
/// with it.
struct MobileBrowserFilePresenter: BrowserFileDestinationOpener {
    // MARK: - Static Variables

    static let downloadDestinations: [BrowserUtilityDownloadDestination] = [.quickLook, .revealInFiles, .share, .files]

    // MARK: - Variables

    let temporaryDirectoryURL: URL?

    // MARK: - Actions - Presenting

    /// A device without a Finder previews instead of opening.
    func openFile(_ fileURL: URL) {}

    func revealFile(_ fileURL: URL) {
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "shareddocuments"
        guard let filesURL = components.url else { return }
        UIApplication.shared.open(filesURL) { opened in
            guard !opened else { return }
            BrowserNoticeCenter.shared.post(.failure(String(localized: "Files couldn’t show this file.")))
        }
    }

    /// A file Quick Look cannot show goes to the share sheet, where another
    /// app can open it.
    func previewFile(_ fileURL: URL) {
        guard QLPreviewController.canPreview(fileURL as NSURL) else {
            shareFile(fileURL)
            return
        }
        MobileBrowserDialogPresenter.present(
            MobileBrowserFilePreviewController(fileURL: fileURL), fallback: {})
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
