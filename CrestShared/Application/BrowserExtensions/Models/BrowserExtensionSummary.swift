struct BrowserExtensionSummary: Equatable, Identifiable {
    let id: String
    let displayName: String
    let version: String?
    let requestedPermissions: [String]
    let requestedHosts: [String]
    let unsupportedAPIs: [String]
    /// Runtime problems reported against this extension. Mutable so a load can
    /// add a failure the WebKit context itself does not carry, such as a stored
    /// website-access pattern WebKit's parser no longer accepts.
    var errors: [String]
    /// Recoverable parser and runtime messages retained for troubleshooting.
    /// These do not imply that the extension stopped running.
    var diagnostics: [String]
    let isEnabled: Bool
    let isLoaded: Bool
    let permissionSnapshot: BrowserExtensionPermissionSnapshot
    var compatibilitySource: BrowserExtensionCompatibilitySource =
        .unpackedPackage
    var compatibilityAssessment: BrowserExtensionCompatibilityAssessment =
        .compatible
    var sourceDisplayName: String? = nil
    var iconPayload: BrowserExtensionIconPayload? = nil
    var hasOptionsPage = false
    var hasCommands = false
    var isPinned = false

    var needsAttention: Bool {
        !errors.isEmpty || !compatibilityAssessment.canRun
    }

    init(
        id: String,
        displayName: String,
        version: String?,
        requestedPermissions: [String],
        requestedHosts: [String],
        unsupportedAPIs: [String],
        errors: [String],
        diagnostics: [String] = [],
        isEnabled: Bool,
        isLoaded: Bool,
        permissionSnapshot: BrowserExtensionPermissionSnapshot,
        compatibilitySource: BrowserExtensionCompatibilitySource =
            .unpackedPackage,
        compatibilityAssessment: BrowserExtensionCompatibilityAssessment =
            .compatible,
        sourceDisplayName: String? = nil,
        iconPayload: BrowserExtensionIconPayload? = nil,
        hasOptionsPage: Bool = false,
        hasCommands: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.requestedPermissions = requestedPermissions
        self.requestedHosts = requestedHosts
        self.unsupportedAPIs = unsupportedAPIs
        self.errors = errors
        self.diagnostics = diagnostics
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.permissionSnapshot = permissionSnapshot
        self.compatibilitySource = compatibilitySource
        self.compatibilityAssessment = compatibilityAssessment
        self.sourceDisplayName = sourceDisplayName
        self.iconPayload = iconPayload
        self.hasOptionsPage = hasOptionsPage
        self.hasCommands = hasCommands
        self.isPinned = isPinned
    }
}
