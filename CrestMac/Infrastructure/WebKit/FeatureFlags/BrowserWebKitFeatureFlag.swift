import Foundation

struct BrowserWebKitFeatureFlag: Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    let details: String
    let status: BrowserWebKitFeatureStatus
    let category: BrowserWebKitFeatureCategory
    let defaultValue: Bool

    var id: String { key }

    var searchText: String {
        [name, key, details, status.title, category.title]
            .joined(separator: " ")
    }
}

struct BrowserWebKitFeatureStatus: Identifiable, Hashable, Sendable {
    let rawValue: Int

    var id: Int { rawValue }

    var title: String {
        switch rawValue {
        case 0: "Embedder"
        case 1: "Unstable"
        case 2: "Internal"
        case 3: "Developer"
        case 4: "Testable"
        case 5: "Preview"
        case 6: "Stable"
        case 7: "Mature"
        default: "Other"
        }
    }
}

struct BrowserWebKitFeatureCategory: Identifiable, Hashable, Sendable {
    let rawValue: Int

    var id: Int { rawValue }

    var title: String {
        switch rawValue {
        case 1: "Animation"
        case 2: "CSS"
        case 3: "DOM"
        case 4: "Extensions"
        case 5: "HTML"
        case 6: "JavaScript"
        case 7: "Media"
        case 8: "Networking"
        case 9: "Privacy"
        case 10: "Security"
        default: "Other"
        }
    }
}

enum BrowserWebKitFeatureFlagOverride: String, Hashable, Sendable {
    case enabled
    case disabled

    var value: Bool {
        self == .enabled
    }
}
