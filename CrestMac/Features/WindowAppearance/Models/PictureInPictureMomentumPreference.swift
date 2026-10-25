import Foundation

/// How readily a release throws the floating Picture in Picture window into a
/// corner. Each choice carries the speed, in points per second, a release must
/// exceed to be a throw, so more momentum is a lower speed. The speed is what is
/// stored, and the Chromium host reads it when a drag or swipe ends.
struct PictureInPictureMomentumPreference: Hashable, Identifiable {
    // MARK: - Static Variables

    static let key = "crest.appearance.picture-in-picture-momentum-threshold"

    static let low = PictureInPictureMomentumPreference(speed: 1000, title: "Low")
    static let medium = PictureInPictureMomentumPreference(speed: 500, title: "Medium")
    static let high = PictureInPictureMomentumPreference(speed: 250, title: "High")

    static let all = [low, medium, high]
    static let defaultValue = medium

    // MARK: - Variables

    let speed: Double
    let title: LocalizedStringResource

    var id: Double { speed }

    // MARK: - Initializers

    private init(speed: Double, title: LocalizedStringResource) {
        self.speed = speed
        self.title = title
    }

    // MARK: - Actions - Comparison

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.speed == rhs.speed }

    func hash(into hasher: inout Hasher) { hasher.combine(speed) }

    /// The choice for a stored speed. A speed that is none of the choices falls
    /// back to the default, so a stale or hand-edited value never leaves the
    /// setting blank.
    init(storedSpeed: Double) {
        self = Self.all.first { $0.speed == storedSpeed } ?? Self.defaultValue
    }
}
