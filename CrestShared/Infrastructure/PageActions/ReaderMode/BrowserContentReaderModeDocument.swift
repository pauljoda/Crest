import Foundation

// MARK: - Types

enum BrowserReaderModeAction: String, CaseIterable, Sendable {
    case availability
    case activate
    case deactivate
    case snapshot
}

/// Engine-neutral Reader Mode bridge over any page whose main document can
/// evaluate Crest's core-owned Reader Mode script (WebKit or Chromium).
@MainActor
final class BrowserContentReaderModeDocument: BrowserReaderModeDocument {
    // MARK: - Types

    /// Runs `body` as the body of an async function with `arguments` bound as
    /// constants in the page's main document.
    typealias Evaluate = @MainActor (_ body: String, _ arguments: [String: Any]) async throws -> Any?

    // MARK: - Variables

    private let documentURL: @MainActor () -> URL?
    private let translation: BrowserPageTranslation
    private let evaluate: Evaluate

    var url: URL? { documentURL() }

    // MARK: - Initializers

    init(
        url: @escaping @MainActor () -> URL?,
        translation: BrowserPageTranslation,
        evaluate: @escaping Evaluate
    ) {
        documentURL = url
        self.translation = translation
        self.evaluate = evaluate
    }

    /// The main document of a page whose engine runs Crest's content scripting
    /// itself (such as Chromium).
    convenience init(
        mainFrameOf scripting: any BrowserPageContentScripting,
        url: @escaping @MainActor () -> URL?,
        translation: BrowserPageTranslation
    ) {
        self.init(url: url, translation: translation) { [weak scripting] body, arguments in
            try await scripting?.callAsyncJavaScriptInMainFrame(body, arguments: arguments)
        }
    }

    // MARK: - Actions - Reader Mode

    func prepareForReaderMode() async throws {
        try await translation.prepareForReaderMode()
    }

    func readerModeIsAvailable() async throws -> Bool {
        try await Self.isAvailable(evaluate: evaluate)
    }

    func activateReaderMode() async throws {
        try await Self.activate(evaluate: evaluate)
    }

    func deactivateReaderMode() async throws {
        try await Self.deactivate(evaluate: evaluate)
    }

    static func isAvailable(evaluate: Evaluate) async throws -> Bool {
        try await perform(.availability, evaluate: evaluate) as? Bool == true
    }

    static func activate(evaluate: Evaluate) async throws {
        guard try await perform(.activate, evaluate: evaluate) as? Bool == true else {
            throw BrowserReaderModeError.articleUnavailable
        }
    }

    static func deactivate(evaluate: Evaluate) async throws {
        guard try await perform(.deactivate, evaluate: evaluate) as? Bool == true else {
            throw BrowserReaderModeError.presentationFailed
        }
    }

    static func snapshot(evaluate: Evaluate) async throws -> BrowserReaderModeSnapshot {
        try BrowserReaderModeSnapshotDecoder.decode(
            try await perform(.snapshot, evaluate: evaluate)
        )
    }

    private static func perform(
        _ action: BrowserReaderModeAction,
        evaluate: Evaluate
    ) async throws -> Any? {
        try await evaluate(
            BrowserReaderModeJavaScriptBridge.source,
            [
                "action": action.rawValue,
                "readerModeLabel": String(
                    localized: BrowserReaderModePresentation.accessibilityLabel
                ),
            ]
        )
    }
}
