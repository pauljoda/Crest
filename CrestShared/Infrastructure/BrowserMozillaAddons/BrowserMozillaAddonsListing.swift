import Foundation

/// The parts of an addons.mozilla.org listing Crest relies on to acquire and
/// verify an add-on package.
struct BrowserMozillaAddonsListing: Equatable, Sendable {
    let slug: BrowserMozillaAddonSlug
    let extensionID: BrowserMozillaExtensionID
    let displayName: String
    let summary: String?
    let version: String
    let downloadURL: URL
    let xpiSHA256Hex: String
    let byteCount: Int

    /// True when Mozilla lists the add-on as Recommended, which means its code
    /// passed Mozilla's manual review rather than automated review alone.
    let isMozillaRecommended: Bool
}
