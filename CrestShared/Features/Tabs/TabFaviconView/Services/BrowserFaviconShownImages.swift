import SwiftUI

/// The tab icons drawn so far, which an icon view made for an icon already
/// drawn shows at once rather than from its placeholder.
///
/// A sidebar makes each tab row as it scrolls into view. Every icon used to
/// start as the placeholder globe and wait for its render task to come back
/// from the image cache's own executor, so a fast scroll drew each row twice
/// and its icon popped in behind it. The decoded images already live in
/// `BrowserFaviconImageCache`; this keeps the ones that were drawn where the
/// main actor can read them while it lays a row out.
///
/// An icon is found by what it is drawn from: its stored image's fingerprint,
/// or, for a tab with no stored image, the site whose own icon the profile
/// fetched. Those found by site are let go with the profile's fetched icons.
@MainActor
final class BrowserFaviconShownImages {
    // MARK: - Types

    /// What an icon is drawn from, at the size it is drawn.
    private enum Key: Hashable {
        case payload(BrowserFaviconPayloadIdentity, maximumPixelSize: Int)
        case site(profileID: UUID, origin: String, maximumPixelSize: Int)
    }

    // MARK: - Static Variables

    static let shared = BrowserFaviconShownImages()

    /// As many as the decoded image cache keeps.
    private static let maximumCount = BrowserFaviconImageCache.maximumCachedImageCount

    // MARK: - Variables

    private var images: [Key: Image] = [:]
    private var recency: [Key] = []

    // MARK: - Actions - Lookup

    /// The icon `request` draws, if one drawn before is kept.
    func image(for request: BrowserFaviconRenderRequest) -> Image? {
        guard let key = Self.key(for: request), let image = images[key] else { return nil }
        return image
    }

    // MARK: - Mutators

    /// Keeps `image` as the icon `request` draws.
    func keep(_ image: Image, for request: BrowserFaviconRenderRequest) {
        guard let key = Self.key(for: request) else { return }
        if images.updateValue(image, forKey: key) == nil {
            recency.append(key)
        }
        while images.count > Self.maximumCount, !recency.isEmpty {
            images[recency.removeFirst()] = nil
        }
    }

    /// Lets go of the icons fetched for `profileID`'s sites, as the profile
    /// lets go of the icons themselves.
    func removeAll(for profileID: UUID) {
        images = images.filter { key, _ in
            if case .site(let owner, _, _) = key { return owner != profileID }
            return true
        }
        recency.removeAll { images[$0] == nil }
    }

    /// The key `request` is found by: its stored image, or the site its
    /// profile fetches an icon for. Nil for a request that draws no image.
    private static func key(for request: BrowserFaviconRenderRequest) -> Key? {
        let size = request.identity.maximumPixelSize
        if let payload = request.identity.payload, request.payload != nil {
            return .payload(payload, maximumPixelSize: size)
        }
        guard let profileID = request.fallbackProfileID, let pageURL = request.fallbackPageURL,
            let scheme = pageURL.scheme, let host = pageURL.host()
        else { return nil }
        let port = pageURL.port.map { ":\($0)" } ?? ""
        return .site(profileID: profileID, origin: "\(scheme)://\(host)\(port)", maximumPixelSize: size)
    }
}
