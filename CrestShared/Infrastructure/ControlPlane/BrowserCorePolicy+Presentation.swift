import Foundation
import os

/// Page presentation and branding rules owned by the portable core.
extension BrowserCorePolicy {
    // MARK: - Types

    private struct PresentationAnswer: Decodable {
        let presentation: BrowserPagePresentation
    }

    private struct BrandingRequest: Encodable {
        let branding: BrowserSpaceBranding
    }

    private struct BrandingAnswer: Decodable {
        let branding: BrowserSpaceBranding
    }

    // MARK: - Static Variables

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

    /// Branding with the core's range rules applied. The native decoder then
    /// applies the crest's heraldic vocabulary. A core that cannot answer
    /// keeps the value as it is.
    static func normalizedBranding(_ branding: BrowserSpaceBranding) -> BrowserSpaceBranding {
        evaluate(.brandingNormalize, BrandingRequest(branding: branding), answer: BrandingAnswer.self)?.branding
            ?? branding
    }
}
