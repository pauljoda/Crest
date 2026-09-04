import Foundation

/// The JavaScript dialogs a debugger session can answer for the page.
enum BrowserExtensionDebuggerDialogKind: String, Sendable {
    case alert
    case confirm
    case prompt
    case beforeunload
}

struct BrowserExtensionDebuggerDialog: Sendable {
    let kind: BrowserExtensionDebuggerDialogKind
    let message: String
    let defaultPrompt: String?
    let url: URL?
}

/// A page that can hand its JavaScript dialogs to an attached debugger session
/// instead of presenting them. The page keeps ownership of the panel: an
/// interceptor either takes the dialog whole or declines it, so a page never
/// ends up with both a Crest sheet and a protocol client waiting on the answer.
@MainActor
protocol BrowserExtensionDebuggerDialogHosting: AnyObject {
    var debuggerDialogInterceptor: BrowserExtensionDebuggerDialogInterceptor? { get set }
}

/// Holds a page's JavaScript dialog open until a protocol client answers it.
///
/// WebKit blocks the page on the completion handler, so an unanswered dialog is
/// a hung page. Every path that ends a session must therefore run through
/// `cancelAll`, which dismisses whatever is waiting as a rejection.
@MainActor
final class BrowserExtensionDebuggerDialogInterceptor {
    /// Emitted for each dialog taken, and once more when one is answered.
    var onEvent: ((String, [String: Any]) -> Void)?
    /// The frame the events report. WebKit gives no frame identity with a
    /// dialog, so a session reports the page's main frame.
    var frameIdentifier: () -> String = { "" }

    private struct Pending {
        let kind: BrowserExtensionDebuggerDialogKind
        let resolve: (Bool, String?) -> Void
    }

    private var pending: [Pending] = []

    var hasPendingDialog: Bool { !pending.isEmpty }

    /// Takes the dialog for the debugger. Returns false when the caller must
    /// present it itself, which is what an interceptor with no listener means.
    func intercept(_ dialog: BrowserExtensionDebuggerDialog, resolve: @escaping (Bool, String?) -> Void) -> Bool {
        guard let onEvent else { return false }
        pending.append(Pending(kind: dialog.kind, resolve: resolve))
        var parameters: [String: Any] = [
            "url": dialog.url?.absoluteString ?? "",
            "frameId": frameIdentifier(),
            "message": dialog.message,
            "type": dialog.kind.rawValue,
            "hasBrowserHandler": true,
        ]
        if let defaultPrompt = dialog.defaultPrompt { parameters["defaultPrompt"] = defaultPrompt }
        onEvent("Page.javascriptDialogOpening", parameters)
        return true
    }

    /// Answers the oldest waiting dialog. Chrome's `handleJavaScriptDialog`
    /// carries no dialog identity, so the queue is strictly first in, first out.
    @discardableResult
    func handle(accept: Bool, promptText: String?) -> Bool {
        guard !pending.isEmpty else { return false }
        let dialog = pending.removeFirst()
        // A prompt WebKit cancels must report nil, not an empty string: an
        // empty string is a real answer the page can act on.
        let text = dialog.kind == .prompt ? (accept ? promptText ?? "" : nil) : promptText
        dialog.resolve(accept, text)
        onEvent?(
            "Page.javascriptDialogClosed",
            ["frameId": frameIdentifier(), "result": accept, "userInput": text ?? ""])
        return true
    }

    /// Releases every waiting dialog as a rejection. Used when the session
    /// detaches, which must never leave the page blocked on a dead client.
    func cancelAll() {
        let waiting = pending
        pending.removeAll()
        for dialog in waiting {
            dialog.resolve(false, nil)
            onEvent?("Page.javascriptDialogClosed", ["frameId": frameIdentifier(), "result": false, "userInput": ""])
        }
    }
}
