import Foundation

extension BrowserExtensionPermissionRestoreError: LocalizedError {
    var errorDescription: String? {
        let patterns = droppedHostPatterns.sorted().joined(separator: ", ")
        return """
            Crest could not restore website access for \(patterns). \
            Grant website access again in Extensions settings.
            """
    }
}
