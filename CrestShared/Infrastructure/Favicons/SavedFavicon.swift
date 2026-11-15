import Foundation

/// The image a saved or pinned tab keeps for the page at its saved address,
/// with the favicon address of the page it came from, so a tab returning
/// there wears it only when the core names that same page. Kept with the
/// tab's own image and never synced.
struct BrowserSavedFavicon: Codable, Equatable, Sendable {
    /// The address of the page the image came from, as the core spells the
    /// tab's saved favicon address.
    let address: String
    let data: Data
}
