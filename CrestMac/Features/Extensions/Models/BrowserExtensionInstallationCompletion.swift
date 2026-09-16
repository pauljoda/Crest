import Foundation

/// A primary installation has committed; retrying it would replace a working installation.
struct BrowserExtensionPartialInstallationError: LocalizedError {
    let summary: BrowserExtensionSummary
    let additionalSpaceCount: Int
    let copyFailure: String
    var errorDescription: String? { copyFailure }
}

@MainActor
struct BrowserExtensionInstallationCompletion {
    let summary: BrowserExtensionSummary
    let additionalSpaceCount: Int
    var copyWarnings: [String] = []

    static func perform(
        additionalSpaceCount: Int,
        installation: () async throws -> BrowserExtensionSummary
    ) async throws -> Self {
        do {
            return Self(summary: try await installation(), additionalSpaceCount: additionalSpaceCount)
        } catch let partial as BrowserExtensionPartialInstallationError {
            return Self(
                summary: partial.summary, additionalSpaceCount: partial.additionalSpaceCount,
                copyWarnings: [partial.copyFailure])
        }
    }
}
