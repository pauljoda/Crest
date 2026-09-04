enum BrowserExtensionSidebarInvocation { case action, sidebarCommand, menu }

enum BrowserExtensionSidebarActionPolicy {
    static func intercepts(
        _ invocation: BrowserExtensionSidebarInvocation, flavor: BrowserExtensionSidebarFlavor,
        opensOnAction: Bool, hasPanel: Bool
    ) -> Bool {
        guard hasPanel else { return false }
        switch invocation {
        case .action: return flavor == .sidePanel && opensOnAction
        case .sidebarCommand: return flavor == .sidebarAction
        case .menu: return true
        }
    }
}
