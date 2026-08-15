import Foundation

enum BrowserExtensionPackageStoreError: LocalizedError, Equatable {
    case packageMissing
    case packageTooLarge
    case symbolicLink
    case unreadableSource
    case unsafePackageName
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .packageMissing:
            "The installed extension package is missing."
        case .packageTooLarge:
            "The extension package exceeds Crest’s safe import limits."
        case .symbolicLink:
            "Extension packages cannot contain symbolic links."
        case .unreadableSource:
            "The extension package could not be inspected."
        case .unsafePackageName:
            "The extension package name is unsafe."
        case .unsupportedSource:
            "Choose an unpacked extension folder or ZIP archive."
        }
    }
}
