import Foundation

enum BrowserPageExportPolicy {
    static func pdfFilename(title: String?, url: URL?) -> String {
        filename(title: title, url: url, pathExtension: "pdf")
    }

    static func webArchiveFilename(title: String?, url: URL?) -> String {
        filename(title: title, url: url, pathExtension: "webarchive")
    }

    static func imageFilename(title: String?, url: URL?) -> String {
        filename(title: title, url: url, pathExtension: "png")
    }

    private static func filename(
        title: String?,
        url: URL?,
        pathExtension: String
    ) -> String {
        let source =
            normalized(title)
            ?? normalized(url?.host())
            ?? "Web Page"
        var candidate = source.replacingOccurrences(
            of: #"[\x00-\x1F\x7F/\\:*?"<>|]+"#,
            with: "-",
            options: .regularExpression
        )
        candidate =
            candidate
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while candidate.hasSuffix(".") {
            candidate.removeLast()
        }
        let suffix = ".\(pathExtension.lowercased())"
        if candidate.lowercased().hasSuffix(suffix) {
            candidate.removeLast(suffix.count)
        }
        candidate = String(candidate.prefix(120))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(candidate.isEmpty ? "Web Page" : candidate).\(pathExtension)"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
