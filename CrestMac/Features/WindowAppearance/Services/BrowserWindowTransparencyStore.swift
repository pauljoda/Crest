import Observation

@Observable
@MainActor
final class BrowserWindowTransparencyStore {
    private let persistence: any BrowserWindowTransparencyPersisting
    private var storedStrength: Double

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            persistence.saveIsEnabled(isEnabled)
        }
    }

    var strength: Double {
        get {
            storedStrength
        }
        set {
            let normalized =
                BrowserWindowTransparencyPolicy.normalizedStrength(newValue)
            guard normalized != storedStrength else { return }
            storedStrength = normalized
            persistence.saveStrength(normalized)
        }
    }

    init(persistence: any BrowserWindowTransparencyPersisting) {
        self.persistence = persistence
        let preference = persistence.load()
        isEnabled = preference.isEnabled
        storedStrength = BrowserWindowTransparencyPolicy.normalizedStrength(
            preference.strength
        )
    }
}
