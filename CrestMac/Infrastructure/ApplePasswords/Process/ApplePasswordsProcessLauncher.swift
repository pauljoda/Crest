import Foundation

/// Starts Apple's helper as a child of Crest's main process, after checking
/// that it is the system's own, signed by Apple.
struct ApplePasswordsProcessLauncher: ApplePasswordsChannelLauncher {
    // MARK: - Variables

    /// The launch's flags. An isolated launch never starts the helper.
    let launchEnvironment: BrowserLaunchEnvironment
    let manifestURL: URL

    // MARK: - Initializers

    init(
        launchEnvironment: BrowserLaunchEnvironment = .current,
        manifestURL: URL = URL(fileURLWithPath: ApplePasswordsHelperLocation.manifestPath)
    ) {
        self.launchEnvironment = launchEnvironment
        self.manifestURL = manifestURL
    }

    // MARK: - Actions - Launching

    func launch() throws -> any ApplePasswordsChannel {
        guard !launchEnvironment.requiresIsolation else { throw ApplePasswordsUnavailability.isolatedLaunch }
        let executable = try ApplePasswordsHelperLocation.verifiedExecutable(manifestURL: manifestURL)
        return try ApplePasswordsHelperProcess(executable: executable)
    }
}
