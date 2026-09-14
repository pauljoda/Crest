import Foundation

enum ArcTabSessionAdapter {
    static func decode(
        _ data: Data,
        importedAt: Date
    ) throws -> [BrowserTabSessionDraft] {
        if data.starts(with: Data("SNSS".utf8)) {
            return try ChromiumTabSessionAdapter.decode(
                data,
                importedAt: importedAt
            )
        }
        guard let document = ArcSidebarDocument(data: data) else {
            throw BrowserTabMigrationError.invalidContents
        }

        var drafts: [BrowserTabSessionDraft] = []
        for container in document.containers {
            let itemsByID = Dictionary(
                uniqueKeysWithValues: container.items.compactMap { item in
                    item.id.map { ($0, item) }
                }
            )

            for (spaceIndex, space) in container.spaces.enumerated() {
                var folders: [BrowserTabSessionFolderDraft] = []
                var tabs: [BrowserTabSessionTabDraft] = []
                var visited: Set<String> = []

                if let favoriteRootID = container.favoriteContainerIDs[space.profileKey] {
                    try appendItem(
                        favoriteRootID,
                        placement: .pinned,
                        parentFolderSourceID: nil,
                        depth: 0,
                        itemsByID: itemsByID,
                        importedAt: importedAt,
                        visited: &visited,
                        folders: &folders,
                        tabs: &tabs
                    )
                }

                var placement = TabPlacement.current
                let sectionIDs =
                    space.containerIDs.isEmpty
                    ? space.newContainerIDs
                    : space.containerIDs
                for sectionID in sectionIDs {
                    switch sectionID {
                    case "unpinned":
                        placement = .current
                    case "pinned":
                        placement = .saved
                    default:
                        try appendItem(
                            sectionID,
                            placement: placement,
                            parentFolderSourceID: nil,
                            depth: 0,
                            itemsByID: itemsByID,
                            importedAt: importedAt,
                            visited: &visited,
                            folders: &folders,
                            tabs: &tabs
                        )
                    }
                }

                let symbol = symbol(space.customInfo)
                let colors = colors(space.customInfo)
                let accent = accent(for: colors.first)
                drafts.append(
                    BrowserTabSessionDraft(
                        sourceOrdinal: drafts.count + 1,
                        name: space.title ?? "Arc Space \(spaceIndex + 1)",
                        tabs: tabs,
                        selectedTabIndex: tabs.indices.last,
                        folders: folders,
                        symbol: symbol,
                        accent: accent,
                        branding: branding(colors: colors, symbol: symbol)
                    ))
            }
        }
        // Arc can retain empty or otherwise non-importable Space records. The
        // shared materializer removes those drafts before enforcing the Space
        // limit, so counting raw records here can reject an otherwise small
        // import.
        return drafts
    }

    private static func appendItem(
        _ id: String,
        placement: TabPlacement,
        parentFolderSourceID: String?,
        depth: Int,
        itemsByID: [String: ArcSidebarDocument.Item],
        importedAt: Date,
        visited: inout Set<String>,
        folders: inout [BrowserTabSessionFolderDraft],
        tabs: inout [BrowserTabSessionTabDraft]
    ) throws {
        guard depth < BrowserSpace.maximumFolderDepth,
            visited.insert(id).inserted,
            let item = itemsByID[id],
            let content = item.content
        else { return }
        if let tab = content.tab,
            let sourceURL = tab.url,
            let url = BrowserImportValueSanitizer.url(sourceURL)
        {
            guard tabs.count < BrowserTabMigration.maximumTabCountPerSpace else {
                throw BrowserTabMigrationError.resourceLimitExceeded
            }
            tabs.append(
                BrowserTabSessionTabDraft(
                    title: tab.title,
                    url: url,
                    placement: placement,
                    folderSourceID: parentFolderSourceID,
                    lastActivatedAt: date(
                        tab.lastActivatedAtValue,
                        fallback: importedAt
                    )
                ))
            return
        }

        let childIDs = item.childrenIDs
        if content.isFolder, placement == .saved {
            guard folders.count < BrowserSpace.maximumFolderCount else {
                throw BrowserTabMigrationError.resourceLimitExceeded
            }
            folders.append(
                BrowserTabSessionFolderDraft(
                    sourceID: id,
                    title: item.title ?? "Untitled Folder",
                    parentSourceID: parentFolderSourceID
                ))
            for childID in childIDs {
                try appendItem(
                    childID,
                    placement: placement,
                    parentFolderSourceID: id,
                    depth: depth + 1,
                    itemsByID: itemsByID,
                    importedAt: importedAt,
                    visited: &visited,
                    folders: &folders,
                    tabs: &tabs
                )
            }
            return
        }

        for childID in childIDs {
            try appendItem(
                childID,
                placement: placement,
                parentFolderSourceID: parentFolderSourceID,
                depth: depth,
                itemsByID: itemsByID,
                importedAt: importedAt,
                visited: &visited,
                folders: &folders,
                tabs: &tabs
            )
        }
    }

    private static func symbol(_ value: Any?) -> String {
        let customInfo = value as? [String: Any]
        let icon = customInfo?["iconType"] as? [String: Any]
        if let emoji = icon?["emoji_v2"] as? String, !emoji.isEmpty {
            return BrowserTab.symbol(forEmoji: emoji)
        }
        switch icon?["icon"] as? String {
        case "planet": return "globe.americas.fill"
        case "briefcase": return "briefcase.fill"
        case "book": return "book.fill"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "sidebar.left"
        }
    }

    private static func colors(_ value: Any?) -> [BrowserSpaceBrandColor] {
        let customInfo = value as? [String: Any]
        let theme = customInfo?["windowTheme"] as? [String: Any]
        let background = theme?["background"] as? [String: Any]
        let single = background?["single"] as? [String: Any]
        let singleValue = single?["_0"] as? [String: Any]
        let style = singleValue?["style"] as? [String: Any]
        let color = style?["color"] as? [String: Any]
        let colorValue = color?["_0"] as? [String: Any]

        var result: [BrowserSpaceBrandColor] = []
        if let gradient = colorValue?["blendedGradient"] as? [String: Any],
            let details = gradient["_0"] as? [String: Any],
            let baseColors = details["baseColors"] as? [Any]
        {
            result.append(contentsOf: baseColors.compactMap(brandColor))
        } else if let singleColor = colorValue?["blendedSingleColor"] as? [String: Any],
            let details = singleColor["_0"] as? [String: Any],
            let rawColor = details["color"]
        {
            if let parsed = brandColor(rawColor) { result.append(parsed) }
        }
        if result.isEmpty,
            let palette = theme?["primaryColorPalette"] as? [String: Any],
            let rawColor = palette["midTone"],
            let parsed = brandColor(rawColor)
        {
            result.append(parsed)
        }
        return Array(result.prefix(BrowserSpaceBranding.maximumColorCount))
    }

    private static func brandColor(_ value: Any) -> BrowserSpaceBrandColor? {
        guard let color = value as? [String: Any],
            let red = (color["red"] as? NSNumber)?.doubleValue,
            let green = (color["green"] as? NSNumber)?.doubleValue,
            let blue = (color["blue"] as? NSNumber)?.doubleValue
        else { return nil }
        return BrowserSpaceBrandColor(
            red: red,
            green: green,
            blue: blue,
            alpha: (color["alpha"] as? NSNumber)?.doubleValue ?? 1
        )
    }

    private static func branding(
        colors: [BrowserSpaceBrandColor],
        symbol: String
    ) -> BrowserSpaceBranding? {
        guard !colors.isEmpty else { return nil }
        return BrowserSpaceBranding(
            colors: colors,
            bannerPattern: colors.count > 1 ? .diagonal : .solid,
            bannerStrength: 1,
            keepsControlsReadable: true,
            themeMode: colors.count > 1 ? .gradient : .banner,
            gradientAngle: 45,
            showsTexture: false,
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
            distance(color, lhs.1) < distance(color, rhs.1)
        }?.0
    }

    private static func distance(
        _ lhs: BrowserSpaceBrandColor,
        _ rhs: BrowserSpaceBrandColor
    ) -> Double {
        pow(lhs.red - rhs.red, 2)
            + pow(lhs.green - rhs.green, 2)
            + pow(lhs.blue - rhs.blue, 2)
    }

    private static func date(_ value: Any?, fallback: Date) -> Date {
        guard let raw = (value as? NSNumber)?.doubleValue, raw.isFinite else {
            return fallback
        }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }
}
