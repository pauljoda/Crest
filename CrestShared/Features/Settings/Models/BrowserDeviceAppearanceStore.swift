import Foundation
import Observation

struct BrowserTabAppearance: Codable, Equatable, Sendable {
    enum Borders: String, Codable, CaseIterable { case selected, pinned, all }
    var borders: Borders = .selected
    var outlinesSelectedTabs = false
    var usesWebsitePinColor = true
    var pinFill: Double = 0
    var pinGlow: Double = 0
    var hoverFill: Double = 0
    var color: BrowserSpaceBrandColor?

    static func intensity(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

struct BrowserAddressAppearance: Codable, Equatable, Sendable {
    var fill: Double = 0
    var border: Double = 0
    var usesAccentWhenEditing = false
    var color: BrowserSpaceBrandColor?
}

extension BrowserTabAppearance {
    private enum CodingKeys: String, CodingKey {
        case borders, outlinesSelectedTabs, usesWebsitePinColor
        case pinFill, pinGlow, hoverFill, color
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        borders = (try? values.decode(Borders.self, forKey: .borders)) ?? .selected
        outlinesSelectedTabs = (try? values.decode(Bool.self, forKey: .outlinesSelectedTabs)) ?? false
        usesWebsitePinColor = (try? values.decode(Bool.self, forKey: .usesWebsitePinColor)) ?? true
        pinFill = Self.intensity((try? values.decode(Double.self, forKey: .pinFill)) ?? 0)
        pinGlow = Self.intensity((try? values.decode(Double.self, forKey: .pinGlow)) ?? 0)
        hoverFill = Self.intensity((try? values.decode(Double.self, forKey: .hoverFill)) ?? 0)
        color = try? values.decode(BrowserSpaceBrandColor.self, forKey: .color)
    }
}

extension BrowserAddressAppearance {
    private enum CodingKeys: String, CodingKey { case fill, border, usesAccentWhenEditing, color }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fill = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .fill)) ?? 0)
        border = BrowserTabAppearance.intensity((try? values.decode(Double.self, forKey: .border)) ?? 0)
        usesAccentWhenEditing = (try? values.decode(Bool.self, forKey: .usesAccentWhenEditing)) ?? false
        color = try? values.decode(BrowserSpaceBrandColor.self, forKey: .color)
    }
}

/// Local presentation preferences never enter a Space record or CloudKit payload.
/// Decode once; Observation invalidates only views reading the changed value.
@MainActor @Observable
final class BrowserDeviceAppearanceStore {
    static let shared = BrowserDeviceAppearanceStore(defaults: BrowserFolderAppearancePreference.defaults)
    static let tabsKey = "crest.appearance.tabs"
    static let addressKey = "crest.appearance.address"
    static let cornerRadiusKey = "crest.appearance.cornerRadius"
    static let maximumCornerRadius: Double = 40
    static let cornerRadiusRange: ClosedRange<Double> = 0...maximumCornerRadius
    var cornerRadius: Double {
        didSet { defaults.set(sidebarCornerRadius, forKey: Self.cornerRadiusKey) }
    }
    var sidebarCornerRadius: Double {
        cornerRadius.isFinite
            ? min(max(cornerRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius
    }
    /// Containers keep straight header edges, even when their child tabs are capsules.
    func containerCornerRadius(padding: Double = 0) -> Double {
        sidebarCornerRadius == 0 ? 0 : min(sidebarCornerRadius, 10) + padding
    }
    @ObservationIgnored private let defaults: UserDefaults
    var tabs: BrowserTabAppearance { didSet { save(tabs, key: Self.tabsKey) } }
    var address: BrowserAddressAppearance { didSet { save(address, key: Self.addressKey) } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if defaults.object(forKey: Self.cornerRadiusKey) != nil {
            cornerRadius = defaults.double(forKey: Self.cornerRadiusKey)
        } else {
            let legacy =
                defaults.data(forKey: Self.tabsKey).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }?["cornerRadius"] as? Double
            let migratedRadius =
                legacy == 24 ? Self.maximumCornerRadius : (legacy ?? BrowserLookAndFeelDefaults.cornerRadius)
            cornerRadius = migratedRadius
            defaults.set(
                migratedRadius.isFinite
                    ? min(max(migratedRadius, 0), Self.maximumCornerRadius) : BrowserLookAndFeelDefaults.cornerRadius,
                forKey: Self.cornerRadiusKey)
        }
        tabs =
            defaults.data(forKey: Self.tabsKey).flatMap {
                try? JSONDecoder().decode(BrowserTabAppearance.self, from: $0)
            } ?? .init()
        address =
            defaults.data(forKey: Self.addressKey).flatMap {
                try? JSONDecoder().decode(BrowserAddressAppearance.self, from: $0)
            } ?? .init()
    }

    private func save(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
