import Foundation

struct BrowserSafariWebExtensionAppLocator {
    private static let safariWebExtensionPoint =
        "com.apple.Safari.web-extension"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func locate(
        in applicationURL: URL
    ) throws -> [BrowserSafariWebExtensionAppDescriptor] {
        guard applicationURL.pathExtension.lowercased() == "app",
            let applicationInfo = propertyList(
                at:
                    applicationURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Info.plist")
            ),
            string("CFBundlePackageType", in: applicationInfo) == "APPL",
            let applicationBundleIdentifier = string(
                "CFBundleIdentifier",
                in: applicationInfo
            )
        else {
            throw BrowserSafariWebExtensionAppLocatorError.invalidApplication
        }

        let plugInsURL =
            applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("PlugIns", isDirectory: true)
        guard
            let extensionURLs = try? fileManager.contentsOfDirectory(
                at: plugInsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            return []
        }

        let applicationDisplayName =
            string("CFBundleDisplayName", in: applicationInfo)
            ?? string("CFBundleName", in: applicationInfo)
            ?? applicationURL.deletingPathExtension().lastPathComponent

        return extensionURLs.compactMap { extensionURL in
            guard extensionURL.pathExtension.lowercased() == "appex",
                let info = propertyList(
                    at:
                        extensionURL
                        .appendingPathComponent("Contents", isDirectory: true)
                        .appendingPathComponent("Info.plist")
                ),
                let extensionInfo = info["NSExtension"]
                    as? [String: Any],
                string(
                    "NSExtensionPointIdentifier",
                    in: extensionInfo
                ) == Self.safariWebExtensionPoint,
                let extensionBundleIdentifier = string(
                    "CFBundleIdentifier",
                    in: info
                )
            else {
                return nil
            }

            let displayName =
                string("CFBundleDisplayName", in: info)
                ?? string("CFBundleName", in: info)
                ?? extensionURL.deletingPathExtension().lastPathComponent
            return BrowserSafariWebExtensionAppDescriptor(
                applicationURL: applicationURL,
                applicationDisplayName: applicationDisplayName,
                applicationBundleIdentifier: applicationBundleIdentifier,
                extensionBundleURL: extensionURL,
                extensionBundleIdentifier: extensionBundleIdentifier,
                displayName: displayName,
                version: string("CFBundleShortVersionString", in: info),
                relativeBundlePath:
                    "Contents/PlugIns/\(extensionURL.lastPathComponent)"
            )
        }
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
    }

    private func propertyList(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
            let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        else {
            return nil
        }
        return propertyList as? [String: Any]
    }

    private func string(
        _ key: String,
        in propertyList: [String: Any]
    ) -> String? {
        guard let value = propertyList[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
