import AppKit

/// What an installed browser keeps, as the core found it in its data folder.
struct BrowserDetectedImportPayload: Equatable, Sendable {
    let application: ImportSource
    let profiles: [ImportProfile]
    var passwordStores: [ImportPasswordStore] = []

    /// `data`, which the core found for `application`.
    init(application: ImportSource, data: ImportData) {
        self.application = application
        profiles = data.profiles
        passwordStores = data.passwordStores
    }

    init(application: ImportSource, profiles: [ImportProfile], passwordStores: [ImportPasswordStore] = []) {
        self.application = application
        self.profiles = profiles
        self.passwordStores = passwordStores
    }
}

/// A browser setup can import from: one Crest knows, or another browser built
/// on Chromium that setup found by looking, which reads as `ImportSource.otherChromium`
/// under its own name and icon.
struct BrowserInstalledImportSource: Identifiable {
    let application: ImportSource
    let applicationURL: URL
    let detectedPayload: BrowserDetectedImportPayload
    let icon: NSImage
    /// The name the browser goes by.
    let title: String

    init(
        application: ImportSource, applicationURL: URL, detectedPayload: BrowserDetectedImportPayload, icon: NSImage,
        title: String? = nil
    ) {
        self.application = application
        self.applicationURL = applicationURL
        self.detectedPayload = detectedPayload
        self.icon = icon
        self.title = title ?? application.title
    }

    var id: URL { applicationURL }

    var hasDetectedData: Bool {
        detectedPayload.profiles.contains {
            $0.bookmarksPath != nil || $0.sessionPath != nil
        }
    }

    /// Whether this process may already read every file the core found,
    /// without asking the person for access to the data folder.
    var hasReadableDetectedData: Bool {
        let paths =
            detectedPayload.profiles.flatMap { profile in
                [profile.bookmarksPath, profile.sessionPath].compactMap { $0 }
            } + detectedPayload.passwordStores.map(\.path)
        return !paths.isEmpty
            && paths.allSatisfy {
                FileManager.default.isReadableFile(atPath: $0)
            }
    }
}
