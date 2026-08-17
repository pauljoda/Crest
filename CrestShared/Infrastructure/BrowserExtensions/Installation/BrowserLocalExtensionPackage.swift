import Foundation

enum BrowserLocalExtensionPackageFormat:
    String,
    Codable,
    Equatable,
    Sendable
{
    case chromeCRX3
    case firefoxXPI

    var filenameExtension: String {
        switch self {
        case .chromeCRX3:
            "crx"
        case .firefoxXPI:
            "xpi"
        }
    }

    var displayName: String {
        switch self {
        case .chromeCRX3:
            String(localized: "Chrome CRX package")
        case .firefoxXPI:
            String(localized: "Firefox XPI package")
        }
    }

    var sourceDisplayName: String {
        switch self {
        case .chromeCRX3:
            String(localized: "Local Chrome Package")
        case .firefoxXPI:
            String(localized: "Local Firefox Package")
        }
    }
}

/// A package selected from the Mac rather than acquired from a trusted store
/// page. Crest retains its format and digest without claiming store provenance.
struct BrowserLocalExtensionSource: Codable, Equatable, Sendable {
    let extensionID: String
    let format: BrowserLocalExtensionPackageFormat
    let sha256Hex: String
}

/// Validated archive bytes ready to be copied into one Space.
struct BrowserLocalExtensionPackage: Equatable, Sendable {
    let extensionID: String
    let format: BrowserLocalExtensionPackageFormat
    let archiveData: Data
    let sha256Hex: String
}
