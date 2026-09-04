import Foundation

struct BrowserExtensionSidebarDefaults: Equatable, Sendable {
    let flavor: BrowserExtensionSidebarFlavor
    var path: String?
    var title: String?
    var icon: BrowserExtensionSidebarIcon?
    var opensAtInstall: Bool = false
}

enum BrowserExtensionSidebarManifestPolicy {
    static func declaresSidebar(manifest: [String: Any]) -> Bool {
        defaults(manifest: manifest, referenceEnvironment: .chromium) != nil
    }

    static func defaults(
        manifest: [String: Any],
        referenceEnvironment: BrowserExtensionReferenceEnvironment
    ) -> BrowserExtensionSidebarDefaults? {
        if referenceEnvironment == .firefox, let firefox = firefoxDefaults(manifest) {
            return firefox
        }
        if (manifest["manifest_version"] as? Int) == 3,
            let panel = manifest["side_panel"] as? [String: Any],
            let path = panel["default_path"] as? String
        {
            return .init(flavor: .sidePanel, path: path)
        }
        return firefoxDefaults(manifest)
    }

    private static func firefoxDefaults(_ manifest: [String: Any]) -> BrowserExtensionSidebarDefaults? {
        guard let panel = manifest["sidebar_action"] as? [String: Any],
            let path = panel["default_panel"] as? String
        else { return nil }
        let title = panel["default_title"] as? String
        return .init(
            flavor: .sidebarAction,
            path: path,
            title: title.flatMap { $0.contains("__MSG_") ? nil : $0 },
            icon: icon(panel["default_icon"]),
            opensAtInstall: panel["open_at_install"] as? Bool ?? true
        )
    }

    static func icon(_ value: Any?) -> BrowserExtensionSidebarIcon? {
        if let path = value as? String, !path.isEmpty { return .packagePath(path) }
        guard let sizes = value as? [String: String] else { return nil }
        let paths = sizes.compactMap { key, path -> (Int, String)? in
            guard let size = Int(key), size > 0, !path.isEmpty else { return nil }
            return (size, path)
        }.sorted { $0.0 < $1.0 }
        guard let path = (paths.first { $0.0 >= 32 } ?? paths.last)?.1 else { return nil }
        return .packagePath(path)
    }
}
