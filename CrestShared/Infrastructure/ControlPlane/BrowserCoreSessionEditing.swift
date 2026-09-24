import Foundation

/// The native models remain the UI projection. Structural tab edits execute in
/// .NET against the family's core session and publish atomically before page
/// pools observe the resulting session. Images, history and existing archive
/// records stay out of synchronous calls.
enum BrowserCoreSessionEditing {
    struct Result: Decodable {
        struct Copy: Decodable {
            var source: UUID
            var copy: UUID
        }
        /// The core decides which tab wears which image; the bytes never cross
        /// the boundary, so it names the tab whose stored image must change.
        struct FaviconAssignment: Decodable {
            var tabId: UUID
            var adopts: Bool
        }
        var space: BrowserSpace
        var tabId: UUID?
        var copies: [Copy]
        var changed: Bool
        var adoptLivePage: Bool?
        var favicon: FaviconAssignment?
    }

    static func decode(_ output: Data, preservingAssetsFrom space: BrowserSpace) throws -> Result {
        var result = try JSONDecoder().decode(Result.self, from: output)
        guard result.space.id == space.id, result.space.profile == space.profile else {
            throw EditError.wrongIdentity
        }
        let originals = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        let copies = Dictionary(
            uniqueKeysWithValues: result.copies.map { (TabID(rawValue: $0.copy), TabID(rawValue: $0.source)) })
        for index in result.space.tabs.indices {
            let id = result.space.tabs[index].id
            if let original = originals[copies[id] ?? id] {
                result.space.tabs[index].faviconData = original.faviconData
            }
        }
        return result
    }

    /// Replaces only the fields a tab edit owns. Preferences, branding, history
    /// and all native presentation metadata stay intact.
    static func apply(_ result: Result, to session: inout BrowserSession, at index: Int) {
        session.spaces[index].tabs = result.space.tabs
        session.spaces[index].folders = result.space.folders
        session.spaces[index].splitGroups = result.space.splitGroups
        session.spaces[index].archivedTabs.append(contentsOf: result.space.archivedTabs)
    }

    /// The core named the tab whose stored image must change. Applying those
    /// bytes here is projection work: no image ever entered a semantic command.
    static func applyFavicon(
        _ assignment: Result.FaviconAssignment?, bytes: Data?,
        to session: inout BrowserSession, at spaceIndex: Int
    ) -> TabID? {
        guard let assignment,
            let tabIndex = session.spaces[spaceIndex].tabs.firstIndex(where: { $0.id.rawValue == assignment.tabId })
        else { return nil }
        session.spaces[spaceIndex].tabs[tabIndex].faviconData = assignment.adopts ? bytes : nil
        return session.spaces[spaceIndex].tabs[tabIndex].id
    }

    private enum EditError: Error { case wrongIdentity }
}
