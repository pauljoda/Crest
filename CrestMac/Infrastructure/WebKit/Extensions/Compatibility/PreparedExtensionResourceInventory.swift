import Darwin
import Foundation

/// The authored assets and generated scripts that must survive together before
/// a prepared package can be reused. File metadata checks avoid rereading large
/// bundles on every restoration; all preparation runs on the filesystem worker.
struct PreparedExtensionResourceInventory: Codable {
    private let fileByteCounts: [String: Int]

    init(resourceURL: URL, fileManager: FileManager) throws {
        var files: [String: Int] = [:]
        for path in try fileManager.subpathsOfDirectory(atPath: resourceURL.path) {
            let attributes = try fileManager.attributesOfItem(atPath: resourceURL.appending(path: path).path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            files[path] = (attributes[.size] as? NSNumber)?.intValue
        }
        fileByteCounts = files
    }

    func matches(resourceURL: URL) -> Bool {
        guard fileByteCounts["manifest.json"] != nil else { return false }
        let prefix = resourceURL.path + "/"
        return fileByteCounts.allSatisfy { path, expectedSize in
            // Request only type and size; FileManager's full attribute lookup
            // also reads metadata that is unnecessary for package reuse.
            var attributes = stat()
            guard lstat(prefix + path, &attributes) == 0 else { return false }
            return attributes.st_mode & S_IFMT == S_IFREG && attributes.st_size == expectedSize
        }
    }
}
