/// Asks the extension's origin store which version it currently publishes.
///
/// This is a version probe only. It never downloads or stages a package, so a
/// scheduled pass over a dozen installations costs a dozen small requests
/// rather than a dozen multi-megabyte downloads.
///
/// The installed version is deliberately not an argument. Crest records an
/// extension's *display* version, which a manifest is free to write as
/// something like `4.9.129 beta`, and handing that to a store as the
/// authoritative installed version invites a wrong answer. Crest asks what is
/// published and decides for itself whether that is an upgrade.
protocol BrowserExtensionUpdateChecking: Sendable {
    /// The version the store publishes, or `nil` when the store has nothing
    /// newer to report.
    func publishedVersion(
        forExtension extensionID: String
    ) async throws -> String?
}
