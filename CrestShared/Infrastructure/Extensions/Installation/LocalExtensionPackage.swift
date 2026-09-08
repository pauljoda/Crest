import CryptoKit
import Foundation

enum BrowserLocalExtensionPackageFormat:
    String,
    Codable,
    Equatable,
    Sendable
{
    case chromeCRX3
    case firefoxXPI
    case safariCustom

    var filenameExtension: String {
        switch self {
        case .chromeCRX3:
            "crx"
        case .firefoxXPI:
            "xpi"
        case .safariCustom:
            "safari-custom"
        }
    }

    var displayName: String {
        switch self {
        case .chromeCRX3:
            String(localized: "Chrome CRX package")
        case .firefoxXPI:
            String(localized: "Firefox XPI package")
        case .safariCustom:
            String(localized: "Safari custom extension")
        }
    }

    var sourceDisplayName: String {
        switch self {
        case .chromeCRX3:
            String(localized: "Local Chrome Package")
        case .firefoxXPI:
            String(localized: "Local Firefox Package")
        case .safariCustom:
            String(localized: "Safari Custom Extension")
        }
    }
}

struct BrowserLocalExtensionDirectoryFile: Equatable, Sendable {
    let relativePath: String
    let data: Data
}

enum BrowserLocalExtensionPackagePayload: Equatable, Sendable {
    case archive(Data)
    case directory([BrowserLocalExtensionDirectoryFile])
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
    static let maximumDirectoryEntryCount = 5_000
    static let maximumDirectoryByteCount = 256 * 1_024 * 1_024

    let extensionID: String
    let format: BrowserLocalExtensionPackageFormat
    let payload: BrowserLocalExtensionPackagePayload
    let sha256Hex: String

    init(
        extensionID: String,
        format: BrowserLocalExtensionPackageFormat,
        archiveData: Data,
        sha256Hex: String
    ) {
        self.extensionID = extensionID
        self.format = format
        payload = .archive(archiveData)
        self.sha256Hex = sha256Hex
    }

    init(
        extensionID: String,
        format: BrowserLocalExtensionPackageFormat,
        directoryFiles: [BrowserLocalExtensionDirectoryFile]
    ) {
        self.extensionID = extensionID
        self.format = format
        let sortedFiles = directoryFiles.sorted {
            $0.relativePath < $1.relativePath
        }
        payload = .directory(sortedFiles)
        sha256Hex = Self.directoryDigest(for: sortedFiles)
    }

    var archiveData: Data {
        guard case .archive(let data) = payload else { return Data() }
        return data
    }

    var directoryFiles: [BrowserLocalExtensionDirectoryFile] {
        guard case .directory(let files) = payload else { return [] }
        return files
    }

    var validatedSafariCustomDirectoryFiles: [BrowserLocalExtensionDirectoryFile]? {
        guard format == .safariCustom,
            case .directory(let files) = payload,
            !files.isEmpty,
            files.count <= Self.maximumDirectoryEntryCount,
            files.reduce(into: 0, { $0 += $1.data.count })
                <= Self.maximumDirectoryByteCount,
            Self.directoryDigest(for: files) == sha256Hex.lowercased(),
            Set(files.map(\.relativePath)).count == files.count,
            files.allSatisfy({ Self.isSafeRelativePath($0.relativePath) }),
            files.contains(where: { $0.relativePath == "manifest.json" })
        else {
            return nil
        }
        return files
    }

    static func directoryDigest(
        for files: [BrowserLocalExtensionDirectoryFile]
    ) -> String {
        var hasher = SHA256()
        for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
            hasher.update(data: Data(file.relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: file.data)
            hasher.update(data: Data([0]))
        }
        return Data(hasher.finalize()).hexString
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
            !value.hasPrefix("/"),
            !value.contains("\\")
        else {
            return false
        }
        let components = value.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return !components.isEmpty
            && components.allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }
}
