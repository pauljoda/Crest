import Foundation

struct BrowserSafariCustomExtensionScanResult: Sendable {
    let packages: [BrowserLocalExtensionPackage]
    let rejectedExtensionCount: Int
}

enum BrowserSafariCustomExtensionScannerError: LocalizedError, Equatable {
    case inaccessibleDirectory
    case invalidDirectory

    var errorDescription: String? {
        switch self {
        case .inaccessibleDirectory:
            String(
                localized:
                    "Crest needs permission to read Safari’s custom extensions folder."
            )
        case .invalidDirectory:
            String(
                localized:
                    "Choose Safari’s MagicExtensions folder or one custom extension inside it."
            )
        }
    }
}

/// Captures Safari-created WebExtensions as inert file snapshots. Safari's
/// private database, profile assignment, permissions, and runtime state are
/// deliberately never read or reused.
struct BrowserSafariCustomExtensionScanner {
    static var defaultSearchRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.apple.Safari", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Safari", isDirectory: true)
            .appendingPathComponent("MagicExtensions", isDirectory: true)
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(
        searchRoot: URL = Self.defaultSearchRoot
    ) throws -> BrowserSafariCustomExtensionScanResult {
        guard fileManager.fileExists(atPath: searchRoot.path) else {
            return BrowserSafariCustomExtensionScanResult(
                packages: [],
                rejectedExtensionCount: 0
            )
        }
        let rootValues: URLResourceValues
        do {
            rootValues = try searchRoot.resourceValues(
                forKeys: [.isDirectoryKey]
            )
        } catch {
            throw BrowserSafariCustomExtensionScannerError
                .inaccessibleDirectory
        }
        guard rootValues.isDirectory == true else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }

        let containsManifest = fileManager.fileExists(
            atPath:
                searchRoot
                .appendingPathComponent("manifest.json")
                .path
        )
        guard
            containsManifest
                || searchRoot.lastPathComponent == "MagicExtensions"
        else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }

        let extensionURLs: [URL]
        if containsManifest {
            extensionURLs = [searchRoot]
        } else {
            do {
                extensionURLs = try fileManager.contentsOfDirectory(
                    at: searchRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                ).filter { url in
                    guard
                        (try? url.resourceValues(
                            forKeys: [.isDirectoryKey]
                        ).isDirectory) == true
                    else {
                        return false
                    }
                    return fileManager.fileExists(
                        atPath:
                            url
                            .appendingPathComponent("manifest.json")
                            .path
                    )
                }
            } catch {
                throw BrowserSafariCustomExtensionScannerError
                    .inaccessibleDirectory
            }
        }

        var packages: [BrowserLocalExtensionPackage] = []
        var rejectedExtensionCount = 0
        for extensionURL in extensionURLs {
            do {
                packages.append(try snapshot(extensionURL))
            } catch {
                rejectedExtensionCount += 1
            }
        }
        packages.sort { $0.extensionID < $1.extensionID }
        return BrowserSafariCustomExtensionScanResult(
            packages: packages,
            rejectedExtensionCount: rejectedExtensionCount
        )
    }

    private func snapshot(
        _ extensionURL: URL
    ) throws -> BrowserLocalExtensionPackage {
        let directoryName = extensionURL.lastPathComponent
        var enumerationFailed = false
        guard isSafeDirectoryName(directoryName),
            let enumerator = fileManager.enumerator(
                at: extensionURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ],
                options: [],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                }
            )
        else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }

        var files: [BrowserLocalExtensionDirectoryFile] = []
        var totalByteCount = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isSymbolicLink != true else {
                throw BrowserSafariCustomExtensionScannerError
                    .invalidDirectory
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true,
                files.count
                    < BrowserLocalExtensionPackage
                    .maximumDirectoryEntryCount
            else {
                throw BrowserSafariCustomExtensionScannerError
                    .invalidDirectory
            }
            totalByteCount += values.fileSize ?? 0
            guard
                totalByteCount
                    <= BrowserLocalExtensionPackage.maximumDirectoryByteCount
            else {
                throw BrowserSafariCustomExtensionScannerError
                    .invalidDirectory
            }
            files.append(
                BrowserLocalExtensionDirectoryFile(
                    relativePath: try relativePath(
                        for: fileURL,
                        under: extensionURL
                    ),
                    data: try Data(
                        contentsOf: fileURL,
                        options: [.mappedIfSafe]
                    )
                )
            )
        }
        guard !enumerationFailed else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }
        guard files.contains(where: { $0.relativePath == "manifest.json" })
        else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }
        return BrowserLocalExtensionPackage(
            extensionID:
                "com.apple.Safari.MagicExtensions.\(directoryName)",
            format: .safariCustom,
            directoryFiles: files
        )
    }

    private func relativePath(
        for fileURL: URL,
        under rootURL: URL
    ) throws -> String {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.starts(with: rootComponents) else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }
        let relativeComponents = fileComponents.dropFirst(
            rootComponents.count
        )
        guard !relativeComponents.isEmpty,
            relativeComponents.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && $0 != "/"
            })
        else {
            throw BrowserSafariCustomExtensionScannerError.invalidDirectory
        }
        return relativeComponents.joined(separator: "/")
    }

    private func isSafeDirectoryName(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 128
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }
}
