import Foundation
import Security

/// Finds Apple's password manager helper the way Apple's own Chrome extension
/// does, through the native messaging manifest, and refuses anything that is
/// not a system component signed by Apple.
struct ApplePasswordsHelperLocation {
    // MARK: - Static Variables

    static let manifestPath = "/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json"
    private static let manifestName = "com.apple.passwordmanager"
    private static let manifestTransport = "stdio"
    /// Where Apple's helper lives once symbolic links are resolved: the system cryptex.
    private static let trustedDirectoryPrefixes = ["/System/Cryptexes/", "/System/Volumes/Preboot/Cryptexes/"]
    /// The helper's own designated requirement: Apple-signed, and that identifier.
    private static let signingRequirement =
        #"identifier "com.apple.PasswordManagerBrowserExtensionHelper" and anchor apple"#

    // MARK: - Types

    private struct Manifest: Decodable {
        let name: String
        let path: String
        let type: String
    }

    // MARK: - Actions - Locating

    /// The helper's executable, once it is known to be Apple's.
    /// - Parameter manifestURL: Where the manifest is read from.
    static func verifiedExecutable(
        manifestURL: URL = URL(fileURLWithPath: manifestPath)
    ) throws(ApplePasswordsUnavailability) -> URL {
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            manifest.name == manifestName, manifest.type == manifestTransport
        else { throw .helperMissing }

        let executable = URL(fileURLWithPath: manifest.path).resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw .helperMissing }
        guard trustedDirectoryPrefixes.contains(where: executable.path.hasPrefix), isSignedByApple(executable) else {
            throw .helperUntrusted
        }
        return executable
    }

    private static func isSignedByApple(_ executable: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(signingRequirement as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
