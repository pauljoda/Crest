import Foundation
import os

/// Which authority applies a Space command issued from a workspace.
enum BrowserWorkspaceCommandRoute: String, Decodable {
    case local
    case source
    case rejected
}

/// Page presentation, content blocking, branding and workspace routing rules
/// owned by the portable core.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct PresentationAnswer: Decodable {
        let presentation: BrowserPagePresentation
    }

    private struct ContentBlockingAnswer: Decodable {
        let identifier: String
        let source: String
    }

    private struct BrandingRequest: Encodable {
        let branding: BrowserSpaceBranding
    }

    private struct BrandingAnswer: Decodable {
        let branding: BrowserSpaceBranding
    }

    private struct CommandRouteRequest: Encodable {
        let command: BrowserSessionOperation
        let borrowed: Bool
    }

    private struct CommandRouteAnswer: Decodable {
        let route: BrowserWorkspaceCommandRoute
    }

    // MARK: - Variables

    private static let pagePresentations = OSAllocatedUnfairLock(
        initialState: [BrowserPagePresentationInput: BrowserPagePresentation]())

    // MARK: - Actions - Presentation

    /// What a page surface shows for its selected tab. Views ask while they
    /// render, so each distinct input is answered by the core once. A core that
    /// cannot answer shows no selection rather than a page it did not choose.
    static func pagePresentation(_ input: BrowserPagePresentationInput) -> BrowserPagePresentation {
        if let known = pagePresentations.withLock({ $0[input] }) { return known }
        guard let presentation = evaluate(.pagePresentation, input, answer: PresentationAnswer.self)?.presentation
        else { return .noSelection }
        pagePresentations.withLock { $0[input] = presentation }
        return presentation
    }

    /// Crest's bundled Balanced rule list: its versioned identifier and WebKit
    /// content-rule source. Nil when the core cannot answer, so nothing is
    /// compiled under a stale identifier.
    static func balancedContentBlockingRules() -> (identifier: String, source: String)? {
        guard let answer = evaluate(.contentBlockingRules, answer: ContentBlockingAnswer.self) else { return nil }
        return (answer.identifier, answer.source)
    }

    /// Branding with the core's range rules applied. The native decoder then
    /// applies the crest's heraldic vocabulary. A core that cannot answer
    /// keeps the value as it is.
    static func normalizedBranding(_ branding: BrowserSpaceBranding) -> BrowserSpaceBranding {
        evaluate(.brandingNormalize, BrandingRequest(branding: branding), answer: BrandingAnswer.self)?.branding
            ?? branding
    }

    /// Which authority applies `command`: a borrowed workspace sends profile
    /// settings to its source and cannot reorganize Spaces. Nil when the core
    /// cannot answer, and the caller applies nothing.
    static func workspaceCommandRoute(_ command: BrowserSessionOperation, borrowed: Bool)
        -> BrowserWorkspaceCommandRoute?
    {
        evaluate(
            .workspaceCommandRoute, CommandRouteRequest(command: command, borrowed: borrowed),
            answer: CommandRouteAnswer.self)?.route
    }
}
