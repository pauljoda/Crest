import Foundation

enum BrowserPlatformDownloadDirectory {
    static func url(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first
    }
}
