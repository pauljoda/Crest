import AppKit

@MainActor
enum BrowserInstalledImportSourceDetector {
    static func installedSources(
        workspace: NSWorkspace = .shared
    ) -> [BrowserInstalledImportSource] {
        BrowserImportApplication.allCases.compactMap { application in
            guard
                let url = workspace.urlForApplication(
                    withBundleIdentifier: application.bundleIdentifier
                )
            else { return nil }
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
            return BrowserInstalledImportSource(
                application: application,
                applicationURL: url,
                detectedPayload: BrowserDetectedImportPayload(
                    application: application,
                    profiles: BrowserImportDataLocator.importProfiles(
                        for: application
                    ),
                    passwordStores: BrowserImportDataLocator.passwordStores(
                        for: application
                    )
                ),
                icon: icon
            )
        }
    }
}
