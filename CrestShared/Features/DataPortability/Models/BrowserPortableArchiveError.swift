import Foundation

enum BrowserPortableArchiveError: LocalizedError, Equatable, Sendable {
    case archiveTooLarge
    case invalidContents
    case unrecognizedFormat
    case unsupportedSchemaVersion(Int)
    case missingFileContents

    var errorDescriptionResource: LocalizedStringResource {
        switch self {
        case .archiveTooLarge:
            "This file is larger than Crest’s 50 MB import limit."
        case .invalidContents:
            "This file does not contain valid Crest browser data."
        case .unrecognizedFormat:
            "This is not a Crest browser-data file."
        case .unsupportedSchemaVersion(let version):
            "This Crest browser-data version (\(version)) is not supported."
        case .missingFileContents:
            "Crest could not read this file."
        }
    }

    var errorDescription: String? {
        String(localized: errorDescriptionResource)
    }
}
