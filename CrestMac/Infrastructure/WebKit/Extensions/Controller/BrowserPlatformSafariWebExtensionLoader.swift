enum BrowserPlatformSafariWebExtensionLoader {
    static func load(
        _ source: BrowserSafariWebExtensionSource
    ) async throws -> BrowserSafariWebExtensionRuntimeResource {
        let resource = try await BrowserSafariWebExtensionResource(
            source: source
        )
        return BrowserSafariWebExtensionRuntimeResource(
            webExtension: resource.webExtension,
            access: resource.access
        )
    }
}
