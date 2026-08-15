struct BrowserExtensionIconRenderState<Icon> {
    private var renderedIcon: BrowserExtensionRenderedIcon<Icon>?

    func icon(for identity: BrowserExtensionIconRequestIdentity) -> Icon? {
        guard renderedIcon?.identity == identity else { return nil }
        return renderedIcon?.icon
    }

    mutating func store(
        _ icon: Icon?,
        for identity: BrowserExtensionIconRequestIdentity
    ) {
        renderedIcon = icon.map {
            BrowserExtensionRenderedIcon(identity: identity, icon: $0)
        }
    }

    mutating func clear() {
        renderedIcon = nil
    }
}
