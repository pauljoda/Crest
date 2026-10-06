import Foundation

@MainActor
protocol BrowserOnboardingImportCommitting {
    func prepare(
        review: SetupImportReview,
        payload: BrowserDetectedImportPayload?
    ) async throws -> BrowserOnboardingPreparedImport

    func finalize(
        review: SetupImportReview,
        preparedImport: BrowserOnboardingPreparedImport,
        browser: BrowserStore
    ) async throws -> BrowserPasswordImportResult
}

/// One extension an import brought, with every Space it installs in. An
/// extension several imported Spaces share is one install, not one for each.
struct BrowserImportedExtensionInstall: Equatable, Sendable {
    let extensionID: String
    let name: String
    /// The Spaces to install it in, in the order the import lists them.
    let spaceIDs: [UUID]
}

/// Installs the extensions an import brought, in the Spaces each belongs in,
/// once the import has made those Spaces. Only the Chromium engine runs
/// extensions, so its composition sets `handler`; any other product leaves it
/// empty and installs none. The handler confirms each install with the person.
@MainActor
enum BrowserImportedExtensionInstaller {
    static var handler: (@MainActor (_ installs: [BrowserImportedExtensionInstall]) -> Void)?

    /// Hands the extensions `review` brings to the handler, each extension
    /// once with all the Spaces it goes into. Two reviewed Spaces that join
    /// the same Space count as one.
    static func install(brought review: SetupImportReview) {
        guard let handler else { return }
        let installs = installs(brought: review)
        if !installs.isEmpty { handler(installs) }
    }

    /// The installs `review` brings, in the order each extension first appears.
    static func installs(brought review: SetupImportReview) -> [BrowserImportedExtensionInstall] {
        var order: [String] = []
        var names: [String: String] = [:]
        var spaces: [String: [UUID]] = [:]
        for space in review.spaces {
            let destination = space.destinationID ?? space.source.id
            for item in space.broughtExtensions {
                if names[item.extensionID] == nil {
                    order.append(item.extensionID)
                    names[item.extensionID] = item.name
                }
                if spaces[item.extensionID, default: []].contains(destination) == false {
                    spaces[item.extensionID, default: []].append(destination)
                }
            }
        }
        return order.map {
            BrowserImportedExtensionInstall(extensionID: $0, name: names[$0] ?? $0, spaceIDs: spaces[$0] ?? [])
        }
    }
}
