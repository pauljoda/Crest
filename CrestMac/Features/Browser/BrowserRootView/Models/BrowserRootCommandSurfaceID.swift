enum BrowserRootCommandSurfaceID {
    static func address(spaceID: SpaceID?) -> String {
        "crest-address-command-\(spaceID?.id.uuidString ?? "none")"
    }
}
