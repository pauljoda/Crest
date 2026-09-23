#if CREST_CHROMIUM_HOST
    import Foundation

    /// The page observations the engine host reports, in the host's spelling. The
    /// host names each one in `crest_chrome_host.mm`; `creationFailed` and
    /// `developerPanel` are also raised by `ChromiumNativePage` itself.
    enum ChromiumPageEvent: String, Sendable {
        case created
        case creationFailed = "creation_failed"
        case navigationStarted = "navigation_started"
        case changed
        case contentMessage = "content_message"
        case infoBarAdded = "infobar_added"
        case infoBarRemoved = "infobar_removed"
        case mediaSession = "media_session"
        case fullscreenChanged = "fullscreen_changed"
        case userActivity = "user_activity"
        case linkHover = "link_hover"
        case popupBlocked = "popup_blocked"
        case favicon
        case developerPanel = "developer_panel"
        case storeInstall = "store_install"
        case storeRemove = "store_remove"
        case closeCanceled = "close_canceled"
        case closed
        case openRequested = "open_requested"
    }

    /// One observation of a page, decoded once where the host delivers it.
    struct ChromiumPageReport {
        let event: ChromiumPageEvent
        /// The event's own values, for events whose payload carries engine objects
        /// such as image data and so has no wire model. URLs are in Crest's
        /// address namespace.
        let values: [String: Any]
        /// The navigation state a `changed` report carries.
        let change: ChromiumPageChange?

        init(_ event: ChromiumPageEvent, values: [String: Any] = [:], change: ChromiumPageChange? = nil) {
            self.event = event
            self.values = values
            self.change = change
        }
    }

    /// The navigation state the host reports in every `changed` observation.
    /// Every field is optional on the wire; the accessors supply the values an
    /// absent field means.
    struct ChromiumPageChange: Decodable {
        // MARK: - Types

        struct HistoryEntry: Decodable {
            let depth: Int
            let title: String?
            let url: String
        }

        // MARK: - Variables

        var url: String?
        var title: String?
        var isLoading: Bool?
        var canGoBack: Bool?
        var canGoForward: Bool?
        var backHistory: [HistoryEntry]?
        var forwardHistory: [HistoryEntry]?
        var committed: Bool?
        /// A `ChromiumPageFailure`, or a notice that is not a failure of the page's
        /// own navigation, such as the one a stale staged link carries.
        var failure: String?
        var errorCode: Int?
        var security: String?
        /// The page's declared theme colour as 0xAARRGGBB.
        var themeColor: UInt32?

        var pageFailure: ChromiumPageFailure? { failure.flatMap(ChromiumPageFailure.init(rawValue:)) }
        /// The engine's verdict; a spelling this build does not know claims nothing.
        var securityState: BrowserPageSecurityState {
            security.flatMap(BrowserPageSecurityState.init(rawValue:)) ?? .none
        }

        // MARK: - Actions - Namespace

        /// The same report with its URL in Crest's address namespace.
        func presented() -> ChromiumPageChange {
            var result = self
            result.url = url.map(ChromiumInternalURL.presented)
            return result
        }
    }

    /// A failure a `changed` report names.
    enum ChromiumPageFailure: String, Sendable {
        case processTerminated = "process_terminated"
        case navigationFailed = "navigation_failed"
    }

    /// The `content_message` payload: one message a Crest content bridge posted
    /// from a frame, with that frame's origin.
    struct ChromiumContentMessagePayload: Decodable {
        let handler: String
        /// The message body as JSON.
        let body: String
        let frame: String
        let isMainFrame: Bool?
        let `protocol`: String
        let host: String
        let port: Int?
    }

    /// The JavaScript dialogs the host routes to Crest's presenter.
    enum ChromiumJavaScriptDialogKind: String, Sendable {
        case alert
        case confirm
        case prompt
        case beforeUnload
    }

    /// The HTTP authentication schemes the host routes to Crest's prompt.
    enum ChromiumAuthenticationMethod: String, Decodable, Sendable {
        case basic
        case digest
    }

    /// The HTTP authentication challenge the host hands to Crest.
    struct ChromiumAuthenticationChallenge: Decodable {
        let url: String
        let host: String
        let port: Int
        let realm: String?
        let method: ChromiumAuthenticationMethod
        let isProxy: Bool?
        let previousFailureCount: Int?
    }

    /// Decodes a host payload with a wire model. Only payloads made of JSON
    /// values (strings, numbers, booleans, null, arrays and dictionaries of them)
    /// have one.
    enum ChromiumHostPayload {
        static func decode<Payload: Decodable>(_ type: Payload.Type, from values: [String: Any]) -> Payload? {
            guard JSONSerialization.isValidJSONObject(values),
                let data = try? JSONSerialization.data(withJSONObject: values)
            else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }
#endif
