import Foundation

extension BrowserSession {
    /// Selection is window state, so the session never stores it. Older
    /// formats, and their tab groups, are decoded by the core, which answers
    /// only this format.
    private enum CodingKeys: String, CodingKey {
        case spaces, defaultSpaceID, disposableSeedMarker, spaceDeletions, appPreferences
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        spaces = try values.decode([BrowserSpace].self, forKey: .spaces)
        defaultSpaceID = try values.decodeIfPresent(SpaceID.self, forKey: .defaultSpaceID)
        disposableSeedMarker = try values.decodeIfPresent(UUID.self, forKey: .disposableSeedMarker)
        spaceDeletions = try values.decodeIfPresent([BrowserSpaceDeletionIntent].self, forKey: .spaceDeletions)
        appPreferences = try values.decodeIfPresent(BrowserAppPreferences.self, forKey: .appPreferences)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(spaces, forKey: .spaces)
        try values.encodeIfPresent(defaultSpaceID, forKey: .defaultSpaceID)
        try values.encodeIfPresent(disposableSeedMarker, forKey: .disposableSeedMarker)
        try values.encodeIfPresent(spaceDeletions, forKey: .spaceDeletions)
        try values.encodeIfPresent(appPreferences, forKey: .appPreferences)
    }
}
