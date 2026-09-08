import CoreGraphics
import Foundation
import Observation

enum BrowserPageZoomPolicy {
    static let levels: [CGFloat] = [
        0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3,
    ]
    static let defaultLevel: CGFloat = 1

    static func increased(from current: CGFloat) -> CGFloat {
        levels.first(where: { $0 > current + tolerance }) ?? levels[levels.count - 1]
    }

    static func decreased(from current: CGFloat) -> CGFloat {
        levels.last(where: { $0 < current - tolerance }) ?? levels[0]
    }

    static func percentageLabel(for zoom: CGFloat) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }

    /// Turns persisted or externally supplied values into one of the same levels
    /// the page commands use. Finite values clamp to the nearest supported level;
    /// corrupt non-finite values fall back to the familiar 100% default.
    static func normalizedDefault(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return defaultLevel }
        return levels.min {
            abs($0 - proposed) < abs($1 - proposed)
        } ?? defaultLevel
    }

    static func levelsMatch(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private static let tolerance: CGFloat = 0.001
}

@MainActor
protocol BrowserDefaultPageZoomObserving: AnyObject {
    func defaultPageZoomDidChange(to zoom: CGFloat)
}

protocol BrowserDefaultPageZoomPersisting {
    func load() -> CGFloat?
    func save(_ zoom: CGFloat)
}

final class UserDefaultsBrowserDefaultPageZoomPersistence:
    BrowserDefaultPageZoomPersisting
{
    static let key = "crest.page-zoom.default"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CGFloat? {
        guard defaults.object(forKey: Self.key) != nil else { return nil }
        return CGFloat(defaults.double(forKey: Self.key))
    }

    func save(_ zoom: CGFloat) {
        defaults.set(Double(zoom), forKey: Self.key)
    }
}

final class InMemoryBrowserDefaultPageZoomPersistence:
    BrowserDefaultPageZoomPersisting
{
    private var zoom: CGFloat?

    init(zoom: CGFloat? = nil) {
        self.zoom = zoom
    }

    func load() -> CGFloat? {
        zoom
    }

    func save(_ zoom: CGFloat) {
        self.zoom = zoom
    }
}

/// The one persisted global zoom baseline shared by every browser runtime.
///
/// Pages subscribe weakly so changing Settings can update every resident page
/// without making their lifetimes part of the preference's lifetime. A page with
/// a temporary command override decides for itself whether to adopt the change.
@Observable
@MainActor
final class BrowserDefaultPageZoomStore {
    static let shared: BrowserDefaultPageZoomStore = {
        let persistence: any BrowserDefaultPageZoomPersisting =
            BrowserLaunchIsolationPolicy.requiresIsolation(.current)
            ? InMemoryBrowserDefaultPageZoomPersistence()
            : UserDefaultsBrowserDefaultPageZoomPersistence()
        return BrowserDefaultPageZoomStore(persistence: persistence)
    }()

    private var storedDefaultZoom: CGFloat

    @ObservationIgnored private let persistence: any BrowserDefaultPageZoomPersisting
    @ObservationIgnored private let observers = NSHashTable<AnyObject>.weakObjects()

    var defaultZoom: CGFloat {
        get { storedDefaultZoom }
        set { setDefaultZoom(newValue) }
    }

    /// The discrete slider position backed by ``BrowserPageZoomPolicy/levels``.
    var defaultZoomLevelIndex: Double {
        get {
            Double(
                BrowserPageZoomPolicy.levels.firstIndex(where: {
                    BrowserPageZoomPolicy.levelsMatch($0, storedDefaultZoom)
                }) ?? BrowserPageZoomPolicy.levels.firstIndex(
                    of: BrowserPageZoomPolicy.defaultLevel
                ) ?? 0
            )
        }
        set {
            let rounded = Int(newValue.rounded())
            let index = min(
                max(rounded, BrowserPageZoomPolicy.levels.startIndex),
                BrowserPageZoomPolicy.levels.index(before: BrowserPageZoomPolicy.levels.endIndex)
            )
            setDefaultZoom(BrowserPageZoomPolicy.levels[index])
        }
    }

    init(persistence: any BrowserDefaultPageZoomPersisting) {
        self.persistence = persistence
        let persisted = persistence.load()
        let normalized = BrowserPageZoomPolicy.normalizedDefault(
            persisted ?? BrowserPageZoomPolicy.defaultLevel
        )
        storedDefaultZoom = normalized
        if let persisted,
            !BrowserPageZoomPolicy.levelsMatch(persisted, normalized)
        {
            persistence.save(normalized)
        }
    }

    func register(_ observer: any BrowserDefaultPageZoomObserving) {
        observers.add(observer)
        observer.defaultPageZoomDidChange(to: storedDefaultZoom)
    }

    private func setDefaultZoom(_ proposed: CGFloat) {
        let normalized = BrowserPageZoomPolicy.normalizedDefault(proposed)
        guard !BrowserPageZoomPolicy.levelsMatch(normalized, storedDefaultZoom) else {
            return
        }
        storedDefaultZoom = normalized
        persistence.save(normalized)
        for observer in observers.allObjects {
            (observer as? any BrowserDefaultPageZoomObserving)?
                .defaultPageZoomDidChange(to: normalized)
        }
    }
}
