import QuickLook
import UIKit

/// Shows one finished download in Quick Look. Quick Look holds its data
/// source weakly, so the controller is its own.
@MainActor
final class MobileBrowserFilePreviewController: QLPreviewController, QLPreviewControllerDataSource {
    // MARK: - Variables

    private let fileURL: URL

    // MARK: - Initializers

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
        dataSource = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Previewing

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        fileURL as NSURL
    }
}
