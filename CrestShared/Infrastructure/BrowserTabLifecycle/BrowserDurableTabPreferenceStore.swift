import Foundation
import Observation

@Observable
@MainActor
final class BrowserDurableTabPreferenceStore {
    static let key = "crest.tabs.durable.closePolicy"

    static let shared: BrowserDurableTabPreferenceStore = {
        let environment = BrowserLaunchEnvironment.current
        guard BrowserLaunchIsolationPolicy.requiresIsolation(environment) else {
            return BrowserDurableTabPreferenceStore(defaults: .standard)
        }
        let defaults = environment.persistentIsolationID.flatMap {
            UserDefaults(suiteName: BrowserLaunchIsolationPolicy.isolatedDefaultsSuiteName(isolationID: $0))
        }
        return BrowserDurableTabPreferenceStore(defaults: defaults)
    }()

    var closePolicy: BrowserDurableTabClosePolicy {
        didSet {
            guard closePolicy != oldValue else { return }
            defaults?.set(closePolicy.rawValue, forKey: Self.key)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        closePolicy =
            defaults?.string(forKey: Self.key)
            .flatMap(BrowserDurableTabClosePolicy.init(rawValue:)) ?? .resumeLastLocation
    }
}
