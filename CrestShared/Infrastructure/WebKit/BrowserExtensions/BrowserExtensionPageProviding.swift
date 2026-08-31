import WebKit

enum BrowserExtensionDownloadRequestError: LocalizedError, Equatable {
    case invalidRequest
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The extension supplied an invalid download request."
        case .unsupportedURL:
            "Crest can download web, data, or owning-extension URLs only."
        }
    }
}

enum BrowserExtensionDownloadExecutionError: LocalizedError, Equatable {
    case unavailable

    var errorDescription: String? {
        "Crest could not start this extension download in its owning tab."
    }
}

enum BrowserExtensionOffscreenDocumentError: LocalizedError, Equatable {
    case invalidRequest
    case alreadyExists
    case unavailable
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The extension supplied an invalid offscreen document request."
        case .alreadyExists:
            "This extension already has an offscreen document in this Space."
        case .unavailable:
            "Crest could not create this extension's offscreen document in its owning Space."
        case .loadFailed(let message):
            "Crest could not load this extension's offscreen document: \(message)"
        }
    }
}

struct BrowserExtensionOffscreenDocumentRequest: Equatable, Sendable {
    let url: URL
    let reasons: [String]
    let justification: String

    init(
        message: [String: Any],
        extensionBaseURL: URL
    ) throws {
        guard message["api"] as? String == "offscreen.createDocument",
            let rawURL = message["url"] as? String,
            !rawURL.isEmpty,
            let reasons = message["reasons"] as? [String],
            !reasons.isEmpty,
            reasons.allSatisfy({ !$0.isEmpty }),
            let justification = message["justification"] as? String,
            !justification.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
            let url = URL(
                string: rawURL,
                relativeTo: extensionBaseURL
            )?.absoluteURL,
            url.scheme?.lowercased()
                == extensionBaseURL.scheme?.lowercased(),
            url.host?.lowercased()
                == extensionBaseURL.host?.lowercased(),
            url.port == extensionBaseURL.port
        else {
            throw BrowserExtensionOffscreenDocumentError.invalidRequest
        }
        self.url = url
        self.reasons = reasons
        self.justification = justification
    }
}

struct BrowserExtensionDownloadRequest: Equatable, Sendable {
    let url: URL
    let filename: String?
    let saveAs: Bool

    init(
        message: [String: Any],
        extensionBaseURL: URL
    ) throws {
        guard message["api"] as? String == "downloads.download",
            let rawURL = message["url"] as? String,
            !rawURL.isEmpty,
            let url = URL(string: rawURL),
            let scheme = url.scheme?.lowercased()
        else {
            throw BrowserExtensionDownloadRequestError.invalidRequest
        }
        let ownsExtensionURL =
            scheme == extensionBaseURL.scheme?.lowercased()
            && url.host?.lowercased()
                == extensionBaseURL.host?.lowercased()
            && url.port == extensionBaseURL.port
        guard
            ["http", "https", "data"].contains(scheme)
                || ownsExtensionURL
        else {
            throw BrowserExtensionDownloadRequestError.unsupportedURL
        }
        if message.keys.contains("filename"),
            !(message["filename"] is String)
        {
            throw BrowserExtensionDownloadRequestError.invalidRequest
        }
        if message.keys.contains("saveAs"),
            !(message["saveAs"] is Bool)
        {
            throw BrowserExtensionDownloadRequestError.invalidRequest
        }
        self.url = url
        filename = (message["filename"] as? String).flatMap {
            $0.isEmpty ? nil : $0
        }
        saveAs = message["saveAs"] as? Bool ?? false
    }
}

struct BrowserExtensionWindowPresentationRequest {
    let url: URL
    let title: String
    let frame: CGRect
    let windowType: WKWebExtension.WindowType
    let windowState: WKWebExtension.WindowState
    let shouldFocus: Bool
}

@MainActor
protocol BrowserExtensionWindowPresentation: AnyObject {
    var extensionTabID: TabID { get }
    var geometry: BrowserExtensionWindowGeometry { get }

    func focus()
    func close()
}

@MainActor
protocol BrowserExtensionPageProviding:
    BrowserExtensionPageSelectionProviding,
    AnyObject
{
    func extensionWebView(for tabID: TabID, in spaceID: SpaceID) -> WKWebView?

    /// Loads an extension-requested URL into the tab runtime appropriate for
    /// that URL. Extension documents require their context's WebKit
    /// configuration, so a provider that owns page lifecycles may swap the
    /// tab's active web view before loading.
    func loadExtensionURL(
        _ url: URL,
        for tabID: TabID,
        in spaceID: SpaceID,
        session: BrowserSession
    )

    /// The tab's last known reader-mode state. Reading it must never start a
    /// probe, so a tab whose page has not been examined reports `.unavailable`.
    func extensionReaderModeState(
        for tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserReaderModeState

    func setExtensionReaderModeActive(
        _ isActive: Bool,
        for tabID: TabID,
        in spaceID: SpaceID
    ) async throws

    func startExtensionDownload(
        _ request: BrowserExtensionDownloadRequest,
        for tabID: TabID,
        in spaceID: SpaceID,
        isUserInitiated: Bool
    ) async throws -> Int

    func createExtensionOffscreenDocument(
        at url: URL,
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) async throws

    func closeExtensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    )

    func hasExtensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) -> Bool

    /// The placement of the real window presenting the Space, or
    /// `.unavailable` when no window is hosting it.
    func extensionWindowGeometry(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowGeometry

    /// Presents a browser-owned native window for a one-page WebExtension
    /// popup. The page must use the owning Space's extension controller and
    /// data store, and must be announced as a tab before its first navigation.
    func presentExtensionWindow(
        _ request: BrowserExtensionWindowPresentationRequest,
        in space: BrowserSpace,
        didFocus: @escaping (TabID) -> Void,
        didClose: @escaping (TabID) -> Void
    ) -> (any BrowserExtensionWindowPresentation)?
}

extension BrowserExtensionPageProviding {
    func createExtensionOffscreenDocument(
        at url: URL,
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) async throws {
        throw BrowserExtensionOffscreenDocumentError.unavailable
    }

    func closeExtensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) {}

    func hasExtensionOffscreenDocument(
        extensionBaseURL: URL,
        in spaceID: SpaceID
    ) -> Bool {
        false
    }

    func startExtensionDownload(
        _ request: BrowserExtensionDownloadRequest,
        for tabID: TabID,
        in spaceID: SpaceID,
        isUserInitiated: Bool
    ) async throws -> Int {
        throw BrowserExtensionDownloadExecutionError.unavailable
    }

    func loadExtensionURL(
        _ url: URL,
        for tabID: TabID,
        in spaceID: SpaceID,
        session: BrowserSession
    ) {
        extensionWebView(for: tabID, in: spaceID)?
            .load(URLRequest(url: url))
    }

    func presentExtensionWindow(
        _ request: BrowserExtensionWindowPresentationRequest,
        in space: BrowserSpace,
        didFocus: @escaping (TabID) -> Void,
        didClose: @escaping (TabID) -> Void
    ) -> (any BrowserExtensionWindowPresentation)? {
        nil
    }
}
