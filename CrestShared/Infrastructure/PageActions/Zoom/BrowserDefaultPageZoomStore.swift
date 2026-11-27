import CoreGraphics
import Foundation
import Observation

@MainActor
protocol BrowserDefaultPageZoomObserving: AnyObject {
    func defaultPageZoomDidChange(to zoom: CGFloat)
}

/// The zoom every page starts at on this device, which the core's device
/// store keeps, and the pages that follow it.
///
/// Pages subscribe weakly so changing Settings can update every resident page
/// without making their lifetimes part of the preference's lifetime. A page
/// whose site keeps a zoom of its own shows that instead.
@Observable
@MainActor
final class BrowserDefaultPageZoomStore {
    /// The baseline a page starts at when nothing else is saved.
    nonisolated static let defaultLevel = CGFloat(PagePreferences.standardZoom)
    /// The baselines a saved preference may hold, which the core keeps it
    /// within.
    nonisolated static let defaultRange = CGFloat(PagePreferences.minimumZoom)...CGFloat(PagePreferences.maximumZoom)

    /// The store every page and Settings share: over the launch's core once
    /// the launch configures it, and before that over a memory-only core of
    /// its own, made on first use, as previews and tests use.
    static var shared: BrowserDefaultPageZoomStore {
        if let configured { return configured }
        let store = BrowserDefaultPageZoomStore(core: CrestCore())
        configured = store
        return store
    }

    /// The store `shared` answers, once there is one.
    private static var configured: BrowserDefaultPageZoomStore?

    @ObservationIgnored private let core: CrestCore
    @ObservationIgnored private let observers = NSHashTable<AnyObject>.weakObjects()

    var defaultZoom: CGFloat {
        get { CGFloat(core.state.pagePreferences.defaultZoom) }
        set { setDefaultZoom(newValue) }
    }

    init(core: CrestCore) {
        self.core = core
    }

    /// Has every page and Settings share the store over `core`, the launch's.
    static func configure(core: CrestCore) {
        configured = BrowserDefaultPageZoomStore(core: core)
    }

    /// Preserve the continuous multiplier, bounding only out-of-range values.
    /// Non-finite values fall back to the familiar 100% default.
    nonisolated static func normalized(_ proposed: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return defaultLevel }
        return min(max(proposed, defaultRange.lowerBound), defaultRange.upperBound)
    }

    func register(_ observer: any BrowserDefaultPageZoomObserving) {
        observers.add(observer)
        observer.defaultPageZoomDidChange(to: defaultZoom)
    }

    private func setDefaultZoom(_ proposed: CGFloat) {
        let previous = defaultZoom
        _ = try? core.send(SetDefaultPageZoom(zoom: Double(proposed)))
        let zoom = defaultZoom
        guard zoom != previous else { return }
        for observer in observers.allObjects {
            (observer as? any BrowserDefaultPageZoomObserving)?.defaultPageZoomDidChange(to: zoom)
        }
    }
}
