import Foundation
import os

/// Which authority applies a Space command issued from a workspace.
enum BrowserWorkspaceCommandRoute: String {
    case local
    case source
    case rejected
}

/// Page presentation, content blocking, branding and workspace routing rules
/// owned by the portable core.
extension BrowserCorePolicy {
    private static let pagePresentations = OSAllocatedUnfairLock(initialState: [BrowserPagePresentationInput: BrowserPagePresentation]())

    /// What a page surface shows for its selected tab. Views ask while they
    /// render, so each distinct input is answered by the core once. A core that
    /// cannot answer shows no selection rather than a page it did not choose.
    static func pagePresentation(_ input: BrowserPagePresentationInput) -> BrowserPagePresentation {
        if let known = pagePresentations.withLock({ $0[input] }) { return known }
        guard let presentation = (evaluate([
            "version": 1, "operation": "page.presentation", "selection": input.selection.rawValue,
            "hasActivePage": input.hasActivePage, "hasNavigationFailure": input.hasNavigationFailure,
            "hasProcessFailure": input.hasProcessFailure, "unloadedBehavior": input.unloadedBehavior.rawValue,
        ])?["presentation"] as? String).flatMap(BrowserPagePresentation.init(rawValue:))
        else { return .noSelection }
        pagePresentations.withLock { $0[input] = presentation }
        return presentation
    }

    /// Crest's bundled Balanced rule list: its versioned identifier and WebKit
    /// content-rule source. Nil when the core cannot answer, so nothing is
    /// compiled under a stale identifier.
    static func balancedContentBlockingRules() -> (identifier: String, source: String)? {
        guard let response = evaluate(["version": 1, "operation": "content_blocking.rules"]),
            let identifier = response["identifier"] as? String, let source = response["source"] as? String
        else { return nil }
        return (identifier, source)
    }

    /// Branding with the core's range rules applied. The native decoder then
    /// applies the crest's heraldic vocabulary. A core that cannot answer
    /// keeps the value as it is.
    static func normalizedBranding(_ branding: BrowserSpaceBranding) -> BrowserSpaceBranding {
        guard let encoded = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(branding)),
            let normalized = evaluate(["version": 1, "operation": "branding.normalize", "branding": encoded])?["branding"],
            let data = try? JSONSerialization.data(withJSONObject: normalized),
            let decoded = try? JSONDecoder().decode(BrowserSpaceBranding.self, from: data)
        else { return branding }
        return decoded
    }

    /// Which authority applies `command`: a borrowed workspace sends profile
    /// settings to its source and cannot reorganize Spaces. Nil when the core
    /// cannot answer, and the caller applies nothing.
    static func workspaceCommandRoute(_ command: String, borrowed: Bool) -> BrowserWorkspaceCommandRoute? {
        (evaluate(["version": 1, "operation": "workspace.command_route", "command": command, "borrowed": borrowed])?["route"]
            as? String).flatMap(BrowserWorkspaceCommandRoute.init(rawValue:))
    }
}
