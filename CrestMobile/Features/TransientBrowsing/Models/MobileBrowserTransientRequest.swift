import SwiftUI

enum MobileBrowserTransientRequest: Identifiable, Equatable {
    case peek(BrowserPeekRequest)
    case quickWindow(BrowserQuickWindowRequest)

    var id: UUID {
        switch self {
        case .peek(let request): request.id
        case .quickWindow(let request): request.id
        }
    }

    var url: URL {
        switch self {
        case .peek(let request): request.url
        case .quickWindow(let request): request.url
        }
    }

    var spaceID: SpaceID {
        spaceAssignment.spaceID
    }

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        switch self {
        case .peek(let request): request.assignment
        case .quickWindow(let request): request.assignment
        }
    }

    var sourcePresentation: BrowserPeekSourcePresentation {
        switch self {
        case .peek(let request):
            BrowserPeekSourcePresentation.resolved(request.sourcePresentation)
        case .quickWindow(let request):
            BrowserPeekSourcePresentation.resolved(request.sourcePresentation)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .peek(let request): "Peek from \(request.sourceTitle)"
        case .quickWindow: "Quick Window"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .peek: "mobile-peek-overlay"
        case .quickWindow: "mobile-quick-window-overlay"
        }
    }

    var isQuickWindow: Bool {
        if case .quickWindow = self { return true }
        return false
    }

    /// What this shell calls the shared overlay presenting this request.
    ///
    /// One card serves both, so the words are the only thing that separates a
    /// Peek from a Quick Window here. The restore button stays neutral because
    /// what it brings back is the page, under either name.
    var overlayVocabulary: BrowserTransientOverlayVocabulary {
        BrowserTransientOverlayVocabulary(
            closeAccessibilityLabel: isQuickWindow
                ? "Close Quick Window"
                : "Close Peek",
            closeHelp: isQuickWindow
                ? "Close Quick Window (Esc or ⌘W)"
                : "Close Peek (Esc or ⌘W)",
            loadingTitle: isQuickWindow
                ? "Opening Quick Window…"
                : "Opening Peek…",
            releasedTitle: isQuickWindow
                ? "Quick Window Released"
                : "Peek Released",
            releasedDescription:
                "Crest released this temporary page to reduce memory use.",
            restoreTitle: "Reload Page"
        )
    }

    var renderIdentity: MobileBrowserTransientRenderIdentity {
        MobileBrowserTransientRenderIdentity(
            requestID: id,
            url: url,
            assignment: spaceAssignment,
            isQuickWindow: isQuickWindow
        )
    }
}
