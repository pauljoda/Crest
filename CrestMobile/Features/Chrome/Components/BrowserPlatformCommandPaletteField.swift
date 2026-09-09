import SwiftUI
import UIKit

struct BrowserPlatformCommandPaletteField: UIViewRepresentable {
    let model: BrowserCommandPaletteModel
    let presentation: BrowserCommandPalettePresentation
    let identifier: String
    let focused: Bool

    func makeUIView(context: Context) -> CompletionField {
        makeField(coordinator: context.coordinator)
    }

    func makeField(coordinator: Coordinator) -> CompletionField {
        let field = CompletionField()
        field.text = model.query
        field.font = .preferredFont(forTextStyle: .title2)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = String(localized: "Search or Enter URL…")
        field.keyboardType = presentation == .embedded ? .default : .URL
        field.textContentType = presentation == .embedded ? nil : .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .go
        field.accessibilityLabel = String(localized: "Command Palette")
        field.accessibilityIdentifier = identifier
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = coordinator
        field.model = model
        field.addTarget(coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        coordinator.field = field
        model.applyCompletion = { [weak coordinator = coordinator] text, range in
            coordinator?.insert(text, replacementRange: range)
        }
        return field
    }

    func updateUIView(_ field: CompletionField, context: Context) {
        if !field.isFirstResponder, field.text != model.query { field.text = model.query }
        field.refreshSuffix()
        if focused, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async { [weak field] in
                guard let field else { return }
                field.becomeFirstResponder()
                field.selectAll(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        let model: BrowserCommandPaletteModel
        weak var field: CompletionField?
        var didRequestFocus = false

        init(model: BrowserCommandPaletteModel) { self.model = model }

        @objc func editingChanged() {
            guard let field, let range = field.selectedTextRange else { return }
            model.updateCompletionEditing(
                text: field.text ?? "",
                selection: NSRange(
                    location: field.offset(from: field.beginningOfDocument, to: range.start),
                    length: field.offset(from: range.start, to: range.end)),
                isComposing: field.markedTextRange != nil
            )
            field.refreshSuffix()
        }

        func textFieldDidChangeSelection(_ textField: UITextField) { editingChanged() }
        func textFieldDidBeginEditing(_ textField: UITextField) { editingChanged() }
        func textFieldDidEndEditing(_ textField: UITextField) {
            model.rejectURLCompletion()
            field?.refreshSuffix()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField.markedTextRange == nil else { return false }
            model.activateSelectedResult()
            return false
        }

        func insert(_ text: String, replacementRange: NSRange) {
            guard let field, field.markedTextRange == nil, field.text == model.query,
                let range = field.selectedTextRange, range.isEmpty,
                field.compare(range.end, to: field.endOfDocument) == .orderedSame
            else { return }
            guard let start = field.position(from: field.beginningOfDocument, offset: replacementRange.location),
                let end = field.position(from: start, offset: replacementRange.length),
                let replacement = field.textRange(from: start, to: end)
            else { return }
            field.selectedTextRange = replacement
            field.insertText(text)
            editingChanged()
        }
    }

    final class CompletionField: UITextField {
        weak var model: BrowserCommandPaletteModel?
        private let suffixLabel = UIHostingConfiguration {
            BrowserURLCompletionSuffix(text: "", font: .title2, isVisible: false)
        }.margins(.all, 0).makeContentView()
        private var renderedSuffix = ""
        private var renderedFont: UIFont?

        override init(frame: CGRect) {
            super.init(frame: frame)
            suffixLabel.isAccessibilityElement = false
            suffixLabel.isUserInteractionEnabled = false
            suffixLabel.isHidden = true
            addSubview(suffixLabel)
            clipsToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var keyCommands: [UIKeyCommand]? {
            guard markedTextRange == nil, model?.urlCompletion != nil else { return super.keyCommands }
            let commands = ["\t", UIKeyCommand.inputRightArrow].map { input in
                let accept = UIKeyCommand(input: input, modifierFlags: [], action: #selector(acceptCompletion))
                accept.discoverabilityTitle = String(localized: "Accept URL completion")
                accept.wantsPriorityOverSystemBehavior = true
                return accept
            }
            return (super.keyCommands ?? []) + commands
        }

        @objc private func acceptCompletion() {
            model?.acceptURLCompletion()
            refreshSuffix()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            refreshSuffix()
        }

        func refreshSuffix() {
            guard isFirstResponder, markedTextRange == nil,
                let proposal = model?.urlCompletion, let range = selectedTextRange
            else {
                if !suffixLabel.isHidden {
                    suffixLabel.isHidden = true
                    suffixLabel.configuration = UIHostingConfiguration {
                        BrowserURLCompletionSuffix(text: "", font: .title2, isVisible: false)
                    }.margins(.all, 0)
                }
                accessibilityHint = nil
                return
            }
            let caret = caretRect(for: range.end)
            if suffixLabel.isHidden || renderedSuffix != proposal.suffix || renderedFont != font {
                renderedSuffix = proposal.suffix
                renderedFont = font
                let suffixFont = Font(font ?? .preferredFont(forTextStyle: .title2))
                suffixLabel.configuration = UIHostingConfiguration {
                    BrowserURLCompletionSuffix(text: proposal.suffix, font: suffixFont)
                }.margins(.all, 0)
            }
            suffixLabel.frame = CGRect(
                x: caret.maxX, y: caret.minY, width: max(0, bounds.maxX - caret.maxX), height: caret.height)
            suffixLabel.isHidden = false
            accessibilityHint = String(
                localized: "URL completion: \(proposal.acceptedQuery). Press Tab or Right Arrow to accept.")
        }
    }
}
