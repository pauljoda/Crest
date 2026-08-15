import Foundation

struct BrowserCredentialCSVExport: Equatable, Sendable {
    let filename: String
    let data: Data

    static func filename(spaceName: String) -> String {
        let safeName =
            spaceName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(80)
        let suffix = safeName.isEmpty ? String(localized: "Space") : String(safeName)
        return "Crest Passwords - \(suffix).csv"
    }
}
