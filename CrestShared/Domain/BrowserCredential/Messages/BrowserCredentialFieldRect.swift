import Foundation

/// Where the password field that asked for a credential sits inside its own
/// frame's viewport, in CSS pixels.
///
/// This is page-controlled data, so it is validated exactly as narrowly as the
/// rest of `BrowserCredentialFormMessage`: four finite numbers, a positive size,
/// and magnitudes small enough that no arithmetic downstream can overflow. A
/// rect that fails any of those is not a smaller rect — it is no rect at all,
/// and the prompt falls back to the placement it uses when a field never
/// reported one.
///
/// The values stay `Double` rather than becoming a `CGRect` here because this
/// layer only imports Foundation. Turning CSS pixels into a shell's points is
/// the drawing layer's job anyway: it is the only layer that knows the page's
/// zoom.
struct BrowserCredentialFieldRect: Equatable, Sendable {
    /// The largest coordinate or size a page may claim. A document can be very
    /// tall, but nothing honest is a million CSS pixels across.
    static let coordinateLimit: Double = 1_000_000

    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init?(body: Any?) {
        guard let dictionary = body as? [String: Any],
            let x = Self.coordinate(dictionary["x"]),
            let y = Self.coordinate(dictionary["y"]),
            let width = Self.coordinate(dictionary["width"]),
            let height = Self.coordinate(dictionary["height"]),
            width > 0,
            height > 0
        else {
            return nil
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private static func coordinate(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let candidate = number.doubleValue
        guard candidate.isFinite, abs(candidate) <= coordinateLimit else {
            return nil
        }
        return candidate
    }
}
