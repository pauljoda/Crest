import Foundation

enum BrowserPlatformDownloadDirectory {
    static func url(fileManager: FileManager = .default) -> URL? {
        URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
    }
}
