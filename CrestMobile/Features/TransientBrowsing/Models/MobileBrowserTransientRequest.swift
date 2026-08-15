import Foundation

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

    var renderIdentity: MobileBrowserTransientRenderIdentity {
        MobileBrowserTransientRenderIdentity(
            requestID: id,
            url: url,
            assignment: spaceAssignment,
            isQuickWindow: isQuickWindow
        )
    }
}
