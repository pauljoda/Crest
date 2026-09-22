#if CREST_CORE_BACKED
import CrestCoreABI
import Foundation
import os

/// The native models remain the UI projection. Structural tab edits execute in
/// .NET and publish atomically before page pools observe the resulting session.
/// Images, history and existing archive records stay out of synchronous calls.
enum BrowserCoreSessionEditing {
    struct Result: Decodable {
        struct Copy: Decodable { var source: UUID; var copy: UUID }
        /// The core decides which tab wears which image; the bytes never cross
        /// the boundary, so it names the tab whose stored image must change.
        struct FaviconAssignment: Decodable { var tabId: UUID; var adopts: Bool }
        var space: BrowserSpace
        var tabId: UUID?
        var selectSpace: Bool
        var copies: [Copy]
        var changed: Bool
        var adoptLivePage: Bool?
        var favicon: FaviconAssignment?
    }
    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "CoreSession")
    private static let maximumBytes = 4 * 1024 * 1024

    static func edit(_ operation: String, space: BrowserSpace, arguments: [String: Any], at date: Date) -> Result? {
        do {
            var compact = space
            compact.history = []
            compact.archivedTabs = []
            compact.tabs = space.tabs.map { var tab = $0; tab.faviconData = nil; return tab }
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(compact))
            let input = try JSONSerialization.data(withJSONObject: [
                "version": 1, "operation": operation, "space": value,
                "arguments": arguments, "now": date.timeIntervalSinceReferenceDate,
            ])
            guard input.count <= maximumBytes else { throw EditError.tooLarge }
            var length = 0
            let measured = input.withUnsafeBytes {
                crest_core_edit_session($0.bindMemory(to: UInt8.self).baseAddress, input.count, nil, 0, &length)
            }
            guard measured == CREST_BUFFER_TOO_SMALL, length > 0, length <= maximumBytes else {
                throw EditError.rejected(measured)
            }
            let capacity = length
            var output = Data(count: capacity)
            let status = output.withUnsafeMutableBytes { destination in
                input.withUnsafeBytes { source in
                    crest_core_edit_session(source.bindMemory(to: UInt8.self).baseAddress, input.count,
                        destination.bindMemory(to: UInt8.self).baseAddress, capacity, &length)
                }
            }
            guard status == CREST_OK else { throw EditError.rejected(status) }
            let result = try decode(output, preservingAssetsFrom: space)
            logger.debug("Applied \(operation, privacy: .public) to \(space.id.rawValue.uuidString, privacy: .public)")
            return result
        } catch {
            logger.error("Rejected \(operation, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    static func decode(_ output: Data, preservingAssetsFrom space: BrowserSpace) throws -> Result {
        var result = try JSONDecoder().decode(Result.self, from: output)
        guard result.space.id == space.id, result.space.profile == space.profile else {
            throw EditError.wrongIdentity
        }
        let originals = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        let copies = Dictionary(uniqueKeysWithValues: result.copies.map { (TabID(rawValue: $0.copy), TabID(rawValue: $0.source)) })
        for index in result.space.tabs.indices {
            let id = result.space.tabs[index].id
            if let original = originals[copies[id] ?? id] {
                result.space.tabs[index].faviconData = original.faviconData
            }
        }
        return result
    }

    /// Encodes a native presentation value as a command argument. Used for
    /// palette colors and icon accents, which are assets rather than records.
    static func value(_ source: (some Encodable)?) -> Any? {
        guard let source else { return nil }
        return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(source), options: [.fragmentsAllowed])
    }

    static func tabValue(_ source: BrowserTab) -> Any? {
        var tab = source; tab.faviconData = nil
        return try? JSONSerialization.jsonObject(with: JSONEncoder().encode(tab))
    }
    private enum EditError: Error { case tooLarge, rejected(Int32), wrongIdentity }
}

extension BrowserSession {
    @discardableResult
    mutating func applyCoreEdit(
        _ operation: String, in spaceID: SpaceID, arguments: [String: Any], at date: Date
    ) -> BrowserCoreSessionEditing.Result? {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }),
            let result = BrowserCoreSessionEditing.edit(operation, space: spaces[index], arguments: arguments, at: date)
        else { return nil }
        applyCoreResult(result, at: index)
        return result
    }

    /// The core named the tab whose stored image must change. Applying those
    /// bytes here is projection work: no image ever entered a semantic command.
    @discardableResult
    mutating func applyCoreFavicon(
        _ assignment: BrowserCoreSessionEditing.Result.FaviconAssignment?, bytes: Data?, at spaceIndex: Int
    ) -> TabID? {
        guard let assignment,
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id.rawValue == assignment.tabId })
        else { return nil }
        spaces[spaceIndex].tabs[tabIndex].faviconData = assignment.adopts ? bytes : nil
        return spaces[spaceIndex].tabs[tabIndex].id
    }

    mutating func applyCoreResult(_ result: BrowserCoreSessionEditing.Result, at index: Int) {
        // Only the fields owned by this editor are replaced. Preferences,
        // branding, history and all native presentation metadata stay intact.
        spaces[index].tabs = result.space.tabs
        spaces[index].folders = result.space.folders
        spaces[index].splitGroups = result.space.splitGroups
        spaces[index].selectedTabID = result.space.selectedTabID
        spaces[index].archivedTabs.append(contentsOf: result.space.archivedTabs)
        if result.selectSpace { selectedSpaceID = spaces[index].id }
    }
}
#endif
