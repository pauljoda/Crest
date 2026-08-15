import AppKit

@MainActor
enum BrowserImportFilePicker {
    static func chooseDataFolder(
        for application: BrowserImportApplication,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        let dataDirectory = BrowserImportDataLocator.defaultDataDirectory(
            for: application
        )
        panel.title = "Allow Crest to Read \(application.name)"
        panel.message =
            "Crest has located \(application.name)'s data folder. Click Allow Access to build your review—there is nothing to find or choose."
        panel.prompt = "Allow Access"
        panel.directoryURL = dataDirectory
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.begin { response in
            completion(response == .OK ? panel.url : nil)
        }
    }
}
