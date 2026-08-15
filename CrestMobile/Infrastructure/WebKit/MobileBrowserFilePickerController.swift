import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MobileBrowserFilePickerController: UIDocumentPickerViewController,
    UIDocumentPickerDelegate
{
    private var selectionCompletion: (@MainActor @Sendable ([URL]?) -> Void)?

    init(
        contentTypes: [UTType],
        allowsMultipleSelection: Bool,
        completion: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        selectionCompletion = completion
        super.init(forOpeningContentTypes: contentTypes, asCopy: true)
        self.allowsMultipleSelection = allowsMultipleSelection
        shouldShowFileExtensions = true
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finish(with: urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(with: nil)
    }

    private func finish(with urls: [URL]?) {
        guard let selectionCompletion else { return }
        self.selectionCompletion = nil
        selectionCompletion(urls)
    }
}
