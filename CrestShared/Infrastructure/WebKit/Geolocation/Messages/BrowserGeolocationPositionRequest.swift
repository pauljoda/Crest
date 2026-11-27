import Foundation

/// The frame asks for the person's position once, or to watch it.
struct BrowserGeolocationPositionRequest: BrowserGeolocationMessage {
    // MARK: - Types

    private struct WireOptions: Decodable {
        let enableHighAccuracy: Bool?
        let maximumAge: Double?
    }

    private struct WirePayload: Decodable {
        let identifier: String
        let options: WireOptions?
    }

    // MARK: - Static Variables

    /// Each action this message answers, with whether it watches the position.
    private static let watchesPositionByAction = ["getCurrentPosition": false, "watchPosition": true]

    // MARK: - Variables

    let identifier: String
    let watchesPosition: Bool
    let options: BrowserGeolocationRequestOptions

    // MARK: - Initializers

    init?(action: String, body: [String: Any]) {
        guard let watchesPosition = Self.watchesPositionByAction[action],
            JSONSerialization.isValidJSONObject(body),
            let data = try? JSONSerialization.data(withJSONObject: body),
            let payload = try? JSONDecoder().decode(WirePayload.self, from: data),
            Self.isValid(payload.identifier)
        else { return nil }
        identifier = payload.identifier
        self.watchesPosition = watchesPosition
        let maximumAgeMilliseconds = payload.options?.maximumAge ?? 0
        options = BrowserGeolocationRequestOptions(
            enablesHighAccuracy: payload.options?.enableHighAccuracy ?? false,
            maximumAge: maximumAgeMilliseconds / 1_000
        )
    }

    // MARK: - Actions - Geolocation

    func handle(on coordinator: BrowserGeolocationCoordinator, in frame: BrowserGeolocationFrame) {
        coordinator.beginRequest(
            identifier: identifier,
            watchesPosition: watchesPosition,
            options: options,
            origin: frame.origin,
            documentIdentifier: frame.documentIdentifier,
            frame: frame.frame,
            frameDocumentIdentifier: frame.frameDocumentIdentifier
        )
    }
}
