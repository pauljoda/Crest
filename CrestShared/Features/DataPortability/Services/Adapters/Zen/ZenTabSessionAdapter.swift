import Foundation

enum ZenTabSessionAdapter {
    static func decode(
        _ source: Data,
        importedAt: Date
    ) throws -> [BrowserTabSessionDraft] {
        let data = try MozillaLZ4.decompressedData(source)
        let root: [String: Any]
        do {
            guard
                let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
            else {
                throw BrowserTabMigrationError.invalidContents
            }
            root = object
        } catch let error as BrowserTabMigrationError {
            throw error
        } catch {
            throw BrowserTabMigrationError.invalidContents
        }
        guard let rawSpaces = root["spaces"] as? [Any],
            let rawTabs = root["tabs"] as? [Any],
            !rawSpaces.isEmpty,
            rawSpaces.count <= BrowserPortableArchive.maximumSpaceCount,
            rawTabs.count <= BrowserTabMigration.maximumTabCountPerSpace
                * rawSpaces.count
        else {
            throw BrowserTabMigrationError.invalidContents
        }
        let rawFolders = root["folders"] as? [Any] ?? []
        guard rawFolders.count <= BrowserSpace.maximumFolderCount * rawSpaces.count else {
            throw BrowserTabMigrationError.resourceLimitExceeded
        }

        var drafts: [BrowserTabSessionDraft] = []
        for (spaceIndex, rawSpace) in rawSpaces.enumerated() {
            guard let space = rawSpace as? [String: Any],
                let workspaceID = space["uuid"] as? String
            else { continue }
            let folders = rawFolders.compactMap { raw -> BrowserTabSessionFolderDraft? in
                guard let folder = raw as? [String: Any],
                    (folder["workspaceId"] as? String
                        ?? folder["workspaceID"] as? String) == workspaceID,
                    let id = folder["id"] as? String
                else { return nil }
                return BrowserTabSessionFolderDraft(
                    sourceID: id,
                    title: folder["name"] as? String ?? "Untitled Folder",
                    parentSourceID: folder["parentId"] as? String
                        ?? folder["parentID"] as? String
                )
            }
            var decodedTabs: [(tab: BrowserTabSessionTabDraft, isActive: Bool)] = []
            for rawTab in rawTabs {
                guard let tab = rawTab as? [String: Any] else { continue }
                let tabWorkspace = tab["zenWorkspace"] as? String
                let isEssential = (tab["zenEssential"] as? NSNumber)?.boolValue ?? false
                guard tabWorkspace == workspaceID || (tabWorkspace == nil && isEssential),
                    let decoded = decodeTab(tab, importedAt: importedAt)
                else { continue }
                decodedTabs.append(
                    (
                        decoded,
                        (tab["_zenIsActiveTab"] as? NSNumber)?.boolValue ?? false
                    ))
            }
            guard decodedTabs.count <= BrowserTabMigration.maximumTabCountPerSpace else {
                throw BrowserTabMigrationError.resourceLimitExceeded
            }
            let colors = themeColors(space["theme"])
            let symbol = "circle.hexagongrid.fill"
            drafts.append(
                BrowserTabSessionDraft(
                    sourceOrdinal: spaceIndex + 1,
                    name: space["name"] as? String ?? "Zen Space \(spaceIndex + 1)",
                    tabs: decodedTabs.map(\.tab),
                    selectedTabIndex: decodedTabs.firstIndex(where: \.isActive)
                        ?? decodedTabs.indices.last,
                    folders: folders,
                    symbol: symbol,
                    accent: accent(for: colors.first) ?? .indigo,
                    branding: branding(colors: colors, theme: space["theme"])
                ))
        }
        return drafts
    }

    private static func decodeTab(
        _ tab: [String: Any],
        importedAt: Date
    ) -> BrowserTabSessionTabDraft? {
        guard let entries = tab["entries"] as? [Any], !entries.isEmpty else { return nil }
        let selectedIndex = min(
            max(0, ((tab["index"] as? NSNumber)?.intValue ?? 1) - 1),
            entries.count - 1
        )
        guard let entry = entries[selectedIndex] as? [String: Any],
            let sourceURL = entry["url"] as? String,
            let url = BrowserTabMigrationSanitizer.url(sourceURL)
        else { return nil }
        let isEssential = (tab["zenEssential"] as? NSNumber)?.boolValue ?? false
        let isPinned = (tab["pinned"] as? NSNumber)?.boolValue ?? false
        let placement: TabPlacement = isEssential ? .pinned : (isPinned ? .saved : .current)
        let rawLastAccessed = (tab["lastAccessed"] as? NSNumber)?.doubleValue
        return BrowserTabSessionTabDraft(
            title: entry["title"] as? String ?? "",
            url: url,
            placement: placement,
            folderSourceID: placement == .saved ? tab["groupId"] as? String : nil,
            lastActivatedAt: rawLastAccessed.map {
                Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1_000 : $0)
            } ?? importedAt
        )
    }

    private static func themeColors(_ value: Any?) -> [BrowserSpaceBrandColor] {
        guard let theme = value as? [String: Any],
            let values = theme["gradientColors"] as? [Any]
        else { return [] }
        return Array(
            values.compactMap { raw -> BrowserSpaceBrandColor? in
                if let hex = raw as? String { return color(hex: hex) }
                guard let dictionary = raw as? [String: Any],
                    let red = (dictionary["red"] as? NSNumber)?.doubleValue,
                    let green = (dictionary["green"] as? NSNumber)?.doubleValue,
                    let blue = (dictionary["blue"] as? NSNumber)?.doubleValue
                else {
                    return nil
                }
                return BrowserSpaceBrandColor(red: red, green: green, blue: blue)
            }.prefix(BrowserSpaceBranding.maximumColorCount))
    }

    private static func color(hex source: String) -> BrowserSpaceBrandColor? {
        let value = source.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let raw = Int(value, radix: 16) else { return nil }
        return BrowserSpaceBrandColor(
            red: Double((raw >> 16) & 0xFF) / 255,
            green: Double((raw >> 8) & 0xFF) / 255,
            blue: Double(raw & 0xFF) / 255
        )
    }

    private static func branding(
        colors: [BrowserSpaceBrandColor],
        theme value: Any?
    ) -> BrowserSpaceBranding? {
        guard !colors.isEmpty else { return nil }
        let theme = value as? [String: Any]
        return BrowserSpaceBranding(
            colors: colors,
            bannerPattern: colors.count > 1 ? .bands : .solid,
            bannerStrength: (theme?["opacity"] as? NSNumber)?.doubleValue ?? 0.65,
            keepsControlsReadable: true,
            themeMode: .gradient,
            gradientAngle: 45,
            showsTexture: ((theme?["texture"] as? NSNumber)?.intValue ?? 0) != 0,
            iconStyle: .simpleSymbol,
            crest: BrowserSpaceCrest()
        )
    }

    private static func accent(for color: BrowserSpaceBrandColor?) -> SpaceAccent? {
        guard let color else { return nil }
        let references: [(SpaceAccent, BrowserSpaceBrandColor)] = [
            (.indigo, .indigo), (.orange, .ember), (.teal, .teal), (.rose, .rose),
        ]
        return references.min { lhs, rhs in
            let lhsDistance =
                pow(color.red - lhs.1.red, 2)
                + pow(color.green - lhs.1.green, 2)
                + pow(color.blue - lhs.1.blue, 2)
            let rhsDistance =
                pow(color.red - rhs.1.red, 2)
                + pow(color.green - rhs.1.green, 2)
                + pow(color.blue - rhs.1.blue, 2)
            return lhsDistance < rhsDistance
        }?.0
    }
}
