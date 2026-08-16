import Foundation

final class BrowserWebExtensionPreparedPackage {
    let resourceURL: URL

    private let rootURL: URL
    private let fileManager: FileManager

    init(
        resourceURL: URL,
        rootURL: URL,
        fileManager: FileManager
    ) {
        self.resourceURL = resourceURL
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    deinit {
        try? fileManager.removeItem(at: rootURL)
    }
}

typealias BrowserChromeWebStorePreparedPackage =
    BrowserWebExtensionPreparedPackage
