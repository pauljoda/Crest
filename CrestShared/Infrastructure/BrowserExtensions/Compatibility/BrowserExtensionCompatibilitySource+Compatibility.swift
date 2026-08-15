extension BrowserExtensionCompatibilitySource {
    init(installationSource: BrowserExtensionInstallationSource?) {
        switch installationSource {
        case nil, .unpackedPackage:
            self = .unpackedPackage
        case .chromeWebStore:
            self = .chromeWebStore
        case .mozillaAddons:
            self = .mozillaAddons
        case .safariWebExtension:
            self = .safariAppExtensionBundle
        }
    }
}
