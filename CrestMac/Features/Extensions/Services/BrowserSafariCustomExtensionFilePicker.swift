import AppKit

@MainActor
enum BrowserSafariCustomExtensionFilePicker {
    static func chooseFolder(
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Allow Crest to Read Safari Custom Extensions"
        panel.message =
            "Crest has located Safari’s custom extensions folder. Click Allow Access to scan it—there is nothing to find or choose."
        panel.prompt = "Allow Access"
        panel.directoryURL =
            BrowserSafariCustomExtensionScanner.defaultSearchRoot
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
