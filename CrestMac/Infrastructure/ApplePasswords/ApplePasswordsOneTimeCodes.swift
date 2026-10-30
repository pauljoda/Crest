import Foundation

/// The one-time code rows Apple Passwords issued to prompts, and the fill that
/// follows a pick.
///
/// Nothing is stored. Each row remembers, for this launch only, the tab, Space,
/// frame origin and top-level origin it was issued for, and the code itself when
/// the helper delivered one. A code is returned only for a row this object
/// issued, only to the tab, Space and origins it was issued to, only within
/// two minutes of the listing, and only once: a pick consumes its row before
/// anything is asked of the helper. Rows are also forgotten whenever their
/// prompt goes away and whenever the helper stops being paired.
@MainActor
final class ApplePasswordsOneTimeCodes {
    // MARK: - Types

    private struct Issued {
        let tab: UUID?
        let spaceID: UUID
        let origin: CredentialOrigin
        let topLevelOrigin: CredentialOrigin
        let source: ApplePasswordsOneTimeCodeSource
        let username: String?
        let domain: String?
        /// Held only for a delivered code; a generated one is read after the pick.
        let code: String?
        let issuedAt: Date
    }

    // MARK: - Static Variables

    /// How long a listing stays good for a pick.
    static let lifetime: TimeInterval = 120

    // MARK: - Variables

    private let source: any ApplePasswordsCredentialSource
    private let now: @MainActor () -> Date
    private var issued: [UUID: Issued] = [:]

    // MARK: - Initializers

    init(source: any ApplePasswordsCredentialSource, now: @escaping @MainActor () -> Date = { .now }) {
        self.source = source
        self.now = now
    }

    // MARK: - Actions - Listing

    /// - Throws: What the source throws; the tab's earlier rows are gone either way.
    func rows(
        for origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID, username: String?,
        tab: UUID?, support: ApplePasswordsSupport
    ) async throws -> [BrowserOneTimeCodeSuggestion] {
        forget(tab: tab)
        let codes = try await source.oneTimeCodes(
            for: origin, topLevel: topLevelOrigin, username: username, tab: tab, support: support)
        // Another listing for the tab may have landed while this one waited.
        forget(tab: tab)
        let issuedAt = now()
        return codes.compactMap { code in
            // A frame that is not the top-level page gets only its own site's codes.
            guard code.belongs(toFrame: origin, topLevel: topLevelOrigin) else { return nil }
            // A delivered code without a value has nothing to fill.
            guard code.source.asksForCurrentCode || code.code?.isEmpty == false else { return nil }
            let id = UUID()
            issued[id] = Issued(
                tab: tab, spaceID: spaceID, origin: origin, topLevelOrigin: topLevelOrigin, source: code.source,
                username: code.username, domain: code.domain,
                code: code.source.asksForCurrentCode ? nil : code.code, issuedAt: issuedAt)
            return BrowserOneTimeCodeSuggestion(id: id, username: code.username)
        }
    }

    // MARK: - Actions - Filling

    /// - Throws: `notPermitted` for a row this object did not issue to the tab
    ///   for the Space and the origins asking, or one that has expired or was
    ///   picked already, without asking the helper anything.
    func code(
        for id: UUID, origin: CredentialOrigin, topLevelOrigin: CredentialOrigin, in spaceID: UUID, tab: UUID?,
        support: ApplePasswordsSupport
    ) async throws -> String {
        let current = now()
        issued = issued.filter { current.timeIntervalSince($0.value.issuedAt) <= Self.lifetime }
        guard let row = issued[id], row.tab == tab, row.spaceID == spaceID, row.origin == origin,
            row.topLevelOrigin == topLevelOrigin
        else {
            throw ApplePasswordsError.notPermitted
        }
        // The pick consumes the row first, so a second click asks for nothing.
        issued[id] = nil
        if row.source.asksForCurrentCode {
            return try await source.currentOneTimeCode(
                for: row.origin, topLevel: row.topLevelOrigin, username: row.username, domain: row.domain, tab: tab,
                support: support)
        }
        guard let delivered = row.code, !delivered.isEmpty else { throw ApplePasswordsError.loginNotFound }
        return delivered
    }

    // MARK: - Mutators

    func forget(tab: UUID?) {
        issued = issued.filter { $0.value.tab != tab }
    }

    func forgetAll() {
        issued = [:]
    }
}
