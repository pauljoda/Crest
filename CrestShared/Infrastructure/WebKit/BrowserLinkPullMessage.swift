import Foundation

/// Decodes the shared fields of the desktop drag and mobile touch bridges once
/// at the script-message boundary into typed properties.
struct BrowserLinkPullMessage: Sendable {
    // MARK: - Types

    private struct WirePayload: Decodable {
        let version: Int?
        let document: String?
        let phase: String?
        let token: String?
        let label: String?
        let href: String?
        let time: Double?
        let x: Double?
        let y: Double?
        let originX: Double?
        let originY: Double?
        let deltaX: Double?
        let deltaY: Double?
    }

    // MARK: - Static Variables

    private static let protocolVersion = 1
    private static let maximumIdentifierLength = 100
    private static let maximumURLLength = 8192

    // MARK: - Variables

    let document: String
    let phase: BrowserLinkPullPhase
    let token: String?
    let label: String?
    let time: TimeInterval?
    let location: CGPoint?
    let origin: CGPoint?
    let dragOffset: CGPoint?
    let url: URL?

    // MARK: - Initializers

    init?(_ body: Any, requiresVersion: Bool = false) {
        guard JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let payload = try? JSONDecoder().decode(WirePayload.self, from: data),
            !requiresVersion || payload.version == Self.protocolVersion,
            let document = Self.identifier(payload.document),
            let rawPhase = payload.phase, let phase = BrowserLinkPullPhase.named(rawPhase)
        else { return nil }
        self.document = document
        self.phase = phase
        token = Self.identifier(payload.token)
        label = payload.label
        time = Self.finite(payload.time)
        location = Self.point(x: payload.x, y: payload.y)
        origin = Self.point(x: payload.originX, y: payload.originY)
        dragOffset = Self.point(x: payload.deltaX ?? 0, y: payload.deltaY ?? 0)
        if let href = payload.href, href.count <= Self.maximumURLLength {
            url = URL(string: href)
        } else {
            url = nil
        }
    }

    // MARK: - Actions - Validation

    private static func identifier(_ value: String?) -> String? {
        guard let value, value.count <= maximumIdentifierLength else { return nil }
        return value
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func point(x: Double?, y: Double?) -> CGPoint? {
        guard let x = finite(x), let y = finite(y) else { return nil }
        return CGPoint(x: x, y: y)
    }
}
