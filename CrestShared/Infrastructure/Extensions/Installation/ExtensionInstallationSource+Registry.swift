import Foundation
import Observation

extension BrowserExtensionInstallationSource {
    /// A matching declared identifier is never evidence of publisher continuity.
    func authenticatesContinuity(from previous: Self?) -> Bool {
        switch (self, previous) {
        case (.chromeWebStore(let next), .chromeWebStore(let old)):
            return next.extensionID == old.extensionID && next.publisherKeyHashHex == old.publisherKeyHashHex
        case (.mozillaAddons(let next), .mozillaAddons(let old)):
            return next.extensionID == old.extensionID && next.slug == old.slug
        case (.localPackage(let next), .localPackage(let old)):
            // CRX IDs are derived from the key validated by BrowserCRX3Verifier.
            return next.format == .chromeCRX3 && old.format == .chromeCRX3 && next.extensionID == old.extensionID
        case (.safariWebExtension(let next), .safariWebExtension(let old)):
            return next.extensionBundleIdentifier == old.extensionBundleIdentifier
                && next.developerTeamIdentifier != nil && next.developerTeamIdentifier == old.developerTeamIdentifier
        default:
            return false
        }
    }

    func permitsReplacement(of previous: Self?) -> Bool {
        if authenticatesContinuity(from: previous) { return true }
        guard case .localPackage(let next) = self, case .localPackage(let old) = previous else { return false }
        // Custom Safari directories have an existing explicit editing workflow.
        return next.format == .safariCustom && old.format == .safariCustom && next.extensionID == old.extensionID
    }

    var isChromeWebStore: Bool {
        if case .chromeWebStore = self { return true }
        return false
    }

    var isLocalPackage: Bool {
        if case .localPackage = self { return true }
        return false
    }
}
