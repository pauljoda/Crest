import Foundation
import XCTest

@testable import Crest

/// Keeps the published compatibility tables identical to the executable matrix.
///
/// The routing table is Swift. Every document that repeats it carries one
/// generated block, and this test regenerates that block and compares it byte
/// for byte. Set `CREST_WRITE_EXTENSION_MATRIX_DOCS=1` to rewrite the blocks in
/// place instead of failing.
final class BrowserExtensionAPICompatibilityMatrixDocumentationTests: XCTestCase {
    private struct GeneratedDocument {
        let relativePath: String
        let beginMarker: String
        let endMarker: String
    }

    /// Markdown files use HTML comments; the Docusaurus page is parsed as MDX,
    /// where an HTML comment is a syntax error, so it uses a JSX comment.
    private static let documents: [GeneratedDocument] = [
        GeneratedDocument(
            relativePath: "Documentation/ExtensionAPICompatibilityMatrix.md",
            beginMarker:
                "<!-- \(BrowserExtensionAPICompatibilityMatrix.generatedDocumentationBeginMarker) -->",
            endMarker:
                "<!-- \(BrowserExtensionAPICompatibilityMatrix.generatedDocumentationEndMarker) -->"
        ),
        GeneratedDocument(
            relativePath: "HelpCenter/docs/extensions/api-compatibility-matrix.md",
            beginMarker:
                "{/* \(BrowserExtensionAPICompatibilityMatrix.generatedDocumentationBeginMarker) */}",
            endMarker:
                "{/* \(BrowserExtensionAPICompatibilityMatrix.generatedDocumentationEndMarker) */}"
        ),
    ]

    private static let writeEnvironmentVariable = "CREST_WRITE_EXTENSION_MATRIX_DOCS"

    /// `#filePath` is `<repository>/CrestTests/<this file>`.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testGeneratedBlocksMatchTheExecutableMatrix() throws {
        let expected =
            "\n" + BrowserExtensionAPICompatibilityMatrix.generatedDocumentationMarkdown() + "\n"
        let rewritesDocuments =
            ProcessInfo.processInfo.environment[Self.writeEnvironmentVariable] == "1"

        for document in Self.documents {
            let url = Self.repositoryRoot.appendingPathComponent(document.relativePath)
            let contents = try String(contentsOf: url, encoding: .utf8)

            guard
                let begin = contents.range(of: document.beginMarker),
                let end = contents.range(
                    of: document.endMarker,
                    options: [],
                    range: begin.upperBound..<contents.endIndex
                )
            else {
                XCTFail(
                    """
                    \(document.relativePath) is missing its generated block. Add:

                    \(document.beginMarker)
                    \(expected)\(document.endMarker)
                    """
                )
                continue
            }

            let generated = String(contents[begin.upperBound..<end.lowerBound])
            guard generated != expected else { continue }

            if rewritesDocuments {
                let rewritten = contents.replacingCharacters(
                    in: begin.upperBound..<end.lowerBound,
                    with: expected
                )
                try rewritten.write(to: url, atomically: true, encoding: .utf8)
                continue
            }

            XCTFail(
                """
                \(document.relativePath) no longer matches \
                BrowserExtensionAPICompatibilityMatrix.

                Rerun with \(Self.writeEnvironmentVariable)=1 to rewrite it, or paste the \
                following between `\(document.beginMarker)` and `\(document.endMarker)`:
                \(expected)
                """
            )
        }
    }

    /// The pinned revisions are also repeated in hand-written prose and links.
    /// A revision hash that is not the pinned one is drift, wherever it appears.
    func testDocumentationRepeatsOnlyPinnedRevisions() throws {
        let pinned: Set<String> = [
            BrowserExtensionAPICompatibilityMatrix.chromiumRevision,
            BrowserExtensionAPICompatibilityMatrix.firefoxRevision,
            BrowserExtensionAPICompatibilityMatrix.webKitRevision,
        ]
        let expression = try NSRegularExpression(pattern: "[0-9a-f]{40}")

        for document in Self.documents {
            let url = Self.repositoryRoot.appendingPathComponent(document.relativePath)
            let contents = try String(contentsOf: url, encoding: .utf8)
            let matches = expression.matches(
                in: contents,
                range: NSRange(contents.startIndex..<contents.endIndex, in: contents)
            )

            for match in matches {
                guard let range = Range(match.range, in: contents) else { continue }
                let revision = String(contents[range])
                XCTAssertTrue(
                    pinned.contains(revision),
                    """
                    \(document.relativePath) references revision \(revision), which is not \
                    pinned by BrowserExtensionAPICompatibilityMatrix. Update the document or \
                    the matrix so one revision review covers both.
                    """
                )
            }
        }
    }
}
