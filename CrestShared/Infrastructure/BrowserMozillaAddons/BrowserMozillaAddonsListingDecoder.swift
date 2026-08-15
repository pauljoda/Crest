import Foundation

/// Reads an addons.mozilla.org v5 detail response into the narrow value Crest
/// installs from.
///
/// Every field the installer later trusts is validated here, so a listing that
/// names an untrusted download host, a non-extension add-on type, or a digest
/// Crest cannot check never becomes a candidate.
enum BrowserMozillaAddonsListingDecoder {
    static let digestPrefix = "sha256:"

    static func listing(
        from data: Data
    ) throws -> BrowserMozillaAddonsListing {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw BrowserMozillaAddonsListingError.malformedPayload
        }
        if payload.slug == nil, payload.guid == nil, payload.detail != nil {
            throw BrowserMozillaAddonsListingError.unknownAddon
        }
        guard let rawSlug = payload.slug,
            let slug = BrowserMozillaAddonSlug(rawSlug)
        else {
            throw BrowserMozillaAddonsListingError.invalidSlug
        }
        guard let rawGUID = payload.guid,
            let extensionID = BrowserMozillaExtensionID(rawGUID)
        else {
            throw BrowserMozillaAddonsListingError.invalidExtensionID
        }
        guard payload.type == "extension" else {
            throw BrowserMozillaAddonsListingError.unsupportedAddonType
        }
        guard payload.isDisabled != true, payload.status == "public" else {
            throw BrowserMozillaAddonsListingError.unavailableAddon
        }
        guard let currentVersion = payload.currentVersion,
            let file = currentVersion.file
        else {
            throw BrowserMozillaAddonsListingError.missingCurrentVersion
        }
        guard let downloadURL = URL(string: file.url),
            downloadURL.scheme?.lowercased() == "https",
            downloadURL.host?.lowercased()
                == BrowserMozillaAddonsListingRequest.host,
            downloadURL.port == nil,
            downloadURL.user == nil,
            downloadURL.password == nil
        else {
            throw BrowserMozillaAddonsListingError.invalidDownloadURL
        }
        guard let digest = xpiSHA256Hex(from: file.hash) else {
            throw BrowserMozillaAddonsListingError.unsupportedDigest
        }
        guard file.size > 0 else {
            throw BrowserMozillaAddonsListingError.malformedPayload
        }
        return BrowserMozillaAddonsListing(
            slug: slug,
            extensionID: extensionID,
            displayName: payload.name?.resolved ?? slug.rawValue,
            summary: payload.summary?.resolved,
            version: currentVersion.version,
            downloadURL: downloadURL,
            xpiSHA256Hex: digest,
            byteCount: file.size,
            isMozillaRecommended: payload.promoted?.isRecommended ?? false
        )
    }

    private static func xpiSHA256Hex(from value: String?) -> String? {
        guard let value,
            value.hasPrefix(digestPrefix)
        else {
            return nil
        }
        let digest = String(value.dropFirst(digestPrefix.count)).lowercased()
        guard digest.utf8.count == 64,
            digest.utf8.allSatisfy({ byte in
                (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
            })
        else {
            return nil
        }
        return digest
    }

    private struct Payload: Decodable {
        let slug: String?
        let guid: String?
        let type: String?
        let status: String?
        let isDisabled: Bool?
        let name: LocalizedText?
        let summary: LocalizedText?
        let currentVersion: Version?
        let promoted: Promotion?
        let detail: String?

        private enum CodingKeys: String, CodingKey {
            case slug
            case guid
            case type
            case status
            case isDisabled = "is_disabled"
            case name
            case summary
            case currentVersion = "current_version"
            case promoted
            case detail
        }
    }

    private struct Version: Decodable {
        let version: String
        let file: File?
    }

    private struct File: Decodable {
        let url: String
        let hash: String?
        let size: Int
    }

    /// AMO answers localized fields either as a plain string or as a
    /// locale-keyed object, depending on the request and the field.
    private struct LocalizedText: Decodable {
        let resolved: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                resolved = text
                return
            }
            let translations =
                (try? container.decode([String: String?].self)) ?? [:]
            let available = translations.compactMapValues { $0 }
            resolved =
                available[BrowserMozillaAddonsListingRequest.locale]
                ?? available.sorted { $0.key < $1.key }.first?.value
        }
    }

    /// AMO has published `promoted` as a single object and as an array of
    /// objects. Either shape resolves to the same question: is this add-on
    /// Recommended?
    private struct Promotion: Decodable {
        let isRecommended: Bool

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(Category.self) {
                isRecommended = single.isRecommended
                return
            }
            let categories =
                (try? container.decode([Category].self)) ?? []
            isRecommended = categories.contains { $0.isRecommended }
        }

        private struct Category: Decodable {
            let category: String?

            var isRecommended: Bool { category == "recommended" }
        }
    }
}
