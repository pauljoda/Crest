enum BrowserRootCommandSurfaceID {
    static func address(spaceID: SpaceID?) -> String {
        "crest-address-command-\(spaceID?.uuidString ?? "none")"
    }

    /// The sidebar address field's own morph identity. It never matched
    /// `address(spaceID:)`: the field used to spell a Space's ID wrapper, so
    /// the palette has never taken the field's frame, and this keeps it so.
    static func sidebarAddress(spaceID: SpaceID) -> String {
        "crest-sidebar-address-\(spaceID.uuidString)"
    }
}
