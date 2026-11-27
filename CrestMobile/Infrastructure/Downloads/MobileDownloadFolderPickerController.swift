import UIKit
import UniformTypeIdentifiers

/// The Files picker that chooses a folder for a Space's downloads, which hands
/// the folder it opened, or nothing when the person cancels, to `choose`. The
/// picker is its own delegate, which it holds while it shows.
@MainActor
final class MobileDownloadFolderPickerController: UIDocumentPickerViewController, UIDocumentPickerDelegate {
    // MARK: - Variables

    private let choose: @MainActor (URL?) -> Void

    // MARK: - Initializers

    init(choose: @escaping @MainActor (URL?) -> Void) {
        self.choose = choose
        super.init(forOpeningContentTypes: [.folder], asCopy: false)
        allowsMultipleSelection = false
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions - Choosing

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        choose(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        choose(nil)
    }
}
