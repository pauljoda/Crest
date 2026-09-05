import Foundation

extension BrowserSession {
    private enum CodingKeys: String, CodingKey {
        case spaces, selectedSpaceID, defaultSpaceID, disposableSeedMarker, currentTabFolders
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try values.decode([BrowserSpace].self, forKey: .spaces)
        selectedSpaceID = try values.decode(SpaceID.self, forKey: .selectedSpaceID)
        defaultSpaceID = try values.decodeIfPresent(SpaceID.self, forKey: .defaultSpaceID)
        disposableSeedMarker = try values.decodeIfPresent(UUID.self, forKey: .disposableSeedMarker)
        // Read the earlier extension-owned format once. Only folders and tab
        // membership are written back; no parallel group collection survives.
        let legacy = try values.decodeIfPresent([BrowserExtensionTabGroup].self, forKey: .currentTabFolders) ?? []
        for group in legacy {
            guard let index = spaces.firstIndex(where: { $0.id == group.spaceID }),
                !spaces[index].folders.contains(where: { $0.id == group.folderID })
            else { continue }
            let ids = Set(group.tabs)
            let members = spaces[index].tabs.indices.filter {
                ids.contains(spaces[index].tabs[$0].id) && spaces[index].tabs[$0].placement == .current
                    && spaces[index].tabs[$0].folderID == nil
            }
            guard !members.isEmpty else { continue }
            spaces[index].folders.append(
                BrowserFolder(
                    id: group.folderID, title: group.title ?? "Folder", location: .current,
                    color: group.color.brandColor, isCollapsed: group.isCollapsed))
            for member in members { spaces[index].tabs[member].folderID = group.folderID }
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(spaces, forKey: .spaces)
        try values.encode(selectedSpaceID, forKey: .selectedSpaceID)
        try values.encodeIfPresent(defaultSpaceID, forKey: .defaultSpaceID)
        try values.encodeIfPresent(disposableSeedMarker, forKey: .disposableSeedMarker)
    }
}
