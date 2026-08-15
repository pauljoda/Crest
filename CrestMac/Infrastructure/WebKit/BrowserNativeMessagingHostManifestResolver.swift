import Foundation
import WebKit

struct BrowserNativeMessagingHostManifestResolver {
    let searchDirectories: [URL]
    let builtInHosts: [BrowserNativeMessagingBuiltInHost]

    init(
        searchDirectories: [URL],
        builtInHosts: [BrowserNativeMessagingBuiltInHost] = []
    ) {
        self.searchDirectories = searchDirectories
        self.builtInHosts = builtInHosts
    }

    static func production() -> Self {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Self(
            searchDirectories: [
                home.appending(
                    path: "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                home.appending(
                    path: "Library/Application Support/Chromium/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                URL(
                    filePath: "/Library/Google/Chrome/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
                URL(
                    filePath: "/Library/Application Support/Chromium/NativeMessagingHosts",
                    directoryHint: .isDirectory
                ),
            ],
            builtInHosts: Self.applePasswordManagerHosts()
        )
    }

    func resolve(
        hostName: String,
        extensionID: BrowserChromeExtensionID
    ) throws -> BrowserNativeMessagingHostManifest {
        guard Self.isValidHostName(hostName) else {
            throw BrowserNativeMessagingHostError.invalidHostName
        }
        if let host = builtInHosts.first(where: {
            $0.name == hostName && $0.extensionID == extensionID
        }) {
            let executableURL = host.executableURL.standardizedFileURL
            guard
                FileManager.default.isExecutableFile(
                    atPath: executableURL.path
                )
            else {
                throw BrowserNativeMessagingHostError.invalidManifest
            }
            return BrowserNativeMessagingHostManifest(
                name: hostName,
                executableURL: executableURL
            )
        }
        let manifestURL = searchDirectories.lazy
            .map { $0.appending(path: "\(hostName).json") }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
        guard let manifestURL else {
            throw BrowserNativeMessagingHostError.hostNotFound(hostName)
        }
        let data = try Data(contentsOf: manifestURL)
        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            object["name"] as? String == hostName,
            object["type"] as? String == "stdio",
            let path = object["path"] as? String,
            path.hasPrefix("/"),
            let origins = object["allowed_origins"] as? [String]
        else {
            throw BrowserNativeMessagingHostError.invalidManifest
        }
        let expectedOrigin =
            "chrome-extension://\(extensionID.rawValue)/"
        guard origins.contains(expectedOrigin) else {
            throw BrowserNativeMessagingHostError.originNotAllowed
        }
        let executableURL = URL(filePath: path).standardizedFileURL
        guard
            FileManager.default.isExecutableFile(
                atPath: executableURL.path
            )
        else {
            throw BrowserNativeMessagingHostError.invalidManifest
        }
        return BrowserNativeMessagingHostManifest(
            name: hostName,
            executableURL: executableURL
        )
    }

    private static func isValidHostName(_ value: String) -> Bool {
        guard !value.isEmpty,
            value.first != ".",
            value.last != ".",
            !value.contains("..")
        else { return false }
        return value.utf8.allSatisfy {
            (0x61...0x7a).contains($0)
                || (0x30...0x39).contains($0)
                || $0 == 0x5f || $0 == 0x2e
        }
    }

    private static func applePasswordManagerHosts()
        -> [BrowserNativeMessagingBuiltInHost]
    {
        // Apple's helper admits browsers carrying this managed entitlement.
        // Keep the route dormant until the current signature has it so an
        // unapproved build fails closed instead of attempting a denied launch.
        guard BrowserICloudPasswordsCapability.currentBuild == .available else {
            return []
        }
        guard
            let extensionID = BrowserChromeExtensionID(
                "pejdijmoenmkgeppbflobdenhhabjlaj"
            )
        else { return [] }
        let executableURL = URL(
            filePath:
                "/System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app/Contents/MacOS/PasswordManagerBrowserExtensionHelper"
        )
        guard
            FileManager.default.isExecutableFile(
                atPath: executableURL.path
            )
        else { return [] }
        return [
            BrowserNativeMessagingBuiltInHost(
                name: "com.apple.passwordmanager",
                extensionID: extensionID,
                executableURL: executableURL
            )
        ]
    }
}
