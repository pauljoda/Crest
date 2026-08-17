/// The platform seam for enumerating and replacing store-sourced packages.
///
/// Downloading, CRX3 verification, staging, and the load/rollback dance all
/// live in the platform shell next to WebKit, exactly as native messaging
/// does. The scheduler above this port decides *whether* and *when*; the
/// adapter behind it decides nothing about policy.
@MainActor
protocol BrowserExtensionUpdateApplying: AnyObject {
    /// Every Chrome Web Store installation across every Space.
    ///
    /// Unpacked and Safari app-extension installations are absent by
    /// construction: neither has a store identity Crest could verify a
    /// replacement package against.
    func chromeWebStoreUpdateTargets() -> [BrowserExtensionUpdateTarget]

    /// Downloads, verifies, and installs the current package for one target,
    /// answering the version that ended up installed.
    ///
    /// The replacement runs through the same verification and rollback path as
    /// a first-time install, so a package that fails its signature or identity
    /// checks throws and leaves the existing installation in place.
    func applyUpdate(
        to target: BrowserExtensionUpdateTarget
    ) async throws -> String?
}
