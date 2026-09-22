import Foundation

/// A bar the engine raised for the page — "Stop sharing" while a tab is
/// shared, an extension debugging the browser. It asks for a decision, so
/// Crest shows it in the page until the person answers or the engine
/// withdraws it.
struct BrowserEngineInfoBar: Identifiable, Equatable {
    let id: Int
    let message: String
    let acceptTitle: String
    let cancelTitle: String
    let isCloseable: Bool

    enum Response: String {
        case accept, cancel, dismiss
    }

    init?(values: [String: Any]) {
        guard let id = values["id"] as? Int, let message = values["message"] as? String,
            !message.isEmpty else { return nil }
        self.id = id
        self.message = message
        acceptTitle = values["ok"] as? String ?? ""
        cancelTitle = values["cancel"] as? String ?? ""
        isCloseable = values["closeable"] as? Bool ?? true
    }
}
