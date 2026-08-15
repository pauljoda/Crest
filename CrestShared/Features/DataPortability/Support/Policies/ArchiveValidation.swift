import Foundation

enum ArchiveValidation {
    static func requireText(
        _ value: String,
        maximumLength: Int
    ) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            value.count <= maximumLength
        else {
            throw BrowserPortableArchiveError.invalidContents
        }
    }

    static func requireDate(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw BrowserPortableArchiveError.invalidContents
        }
    }

    static func sanitizedURL(
        _ url: URL?,
        removesFragment: Bool
    ) -> URL? {
        guard let url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false
        else {
            return nil
        }
        components.user = nil
        components.password = nil
        if removesFragment {
            components.fragment = nil
        }
        return components.url
    }

    static func materializeURL(
        _ source: String?,
        removesFragment: Bool
    ) throws -> URL? {
        guard let source else { return nil }
        guard source.count <= ArchiveLimits.maximumURLLength,
            let url = URL(string: source),
            let sanitized = sanitizedURL(url, removesFragment: removesFragment),
            sanitized.absoluteString == source
        else {
            throw BrowserPortableArchiveError.invalidContents
        }
        return sanitized
    }
}
