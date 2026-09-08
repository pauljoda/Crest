import Foundation

@MainActor
final class BrowserCredentialSensitiveAccess {
    private let browser: BrowserStore
    private let authenticator: any BrowserDeviceAuthenticating

    init(
        browser: BrowserStore,
        authenticator: any BrowserDeviceAuthenticating =
            SystemBrowserDeviceAuthenticator()
    ) {
        self.browser = browser
        self.authenticator = authenticator
    }

    func revealCredential(
        id: CredentialID,
        in spaceID: SpaceID,
        reason: String = String(localized: "Authenticate to view this Crest password.")
    ) async throws -> BrowserCredential {
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }
        guard let credential = try await browser.credential(id: id, in: spaceID),
            credential.descriptor.id == id,
            credential.descriptor.spaceID == spaceID
        else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        return credential
    }

    func revealCredential(
        id: CredentialID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        reason: String = String(localized: "Authenticate to view this Crest password.")
    ) async throws -> BrowserCredential {
        guard browser.space(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }
        guard browser.space(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        guard
            let credential = try await browser.credential(
                id: id,
                in: assignment.spaceID
            ), browser.space(matching: assignment) != nil,
            credential.descriptor.id == id,
            credential.descriptor.spaceID == assignment.spaceID
        else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        return credential
    }

    func exportCredentials(in spaceID: SpaceID) async throws -> BrowserCredentialCSVExport {
        guard let space = browser.session.space(id: spaceID) else {
            throw CredentialVaultError.missingSpace
        }
        let reason = String(
            localized: "Authenticate to export passwords from \(space.name)."
        )
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }

        let descriptors = try await browser.savedCredentialDescriptors(in: spaceID)
            .sorted(by: Self.exportOrder)
        var credentials: [BrowserCredential] = []
        credentials.reserveCapacity(descriptors.count)
        for descriptor in descriptors {
            guard
                let credential = try await browser.credential(
                    id: descriptor.id,
                    in: spaceID
                ), credential.descriptor.id == descriptor.id,
                credential.descriptor.spaceID == spaceID
            else {
                throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
            }
            credentials.append(credential)
        }

        return BrowserCredentialCSVExport(
            filename: BrowserCredentialCSVExport.filename(spaceName: space.name),
            data: Self.csvData(credentials: credentials)
        )
    }

    func credentialInventory(
        matching assignment: BrowserSpaceRuntimeAssignment,
        reason: String
    ) async throws -> [BrowserCredential] {
        guard browser.space(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        guard try await authenticator.authenticate(reason: reason) else {
            throw BrowserCredentialSensitiveAccessError.authenticationDenied
        }
        guard browser.space(matching: assignment) != nil else {
            throw BrowserCredentialSensitiveAccessError.missingCredential
        }
        let credentials = try await browser.credentialInventory(
            in: assignment.spaceID
        )
        guard
            browser.space(matching: assignment) != nil,
            credentials.allSatisfy({
                $0.descriptor.spaceID == assignment.spaceID
            })
        else {
            throw BrowserCredentialSensitiveAccessError.malformedCredentialInventory
        }
        return credentials
    }

    private static func exportOrder(
        _ lhs: CredentialDescriptor,
        _ rhs: CredentialDescriptor
    ) -> Bool {
        if lhs.origin.description != rhs.origin.description {
            return lhs.origin.description < rhs.origin.description
        }
        let usernameOrder = lhs.username.localizedStandardCompare(rhs.username)
        if usernameOrder != .orderedSame {
            return usernameOrder == .orderedAscending
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    private static func csvData(credentials: [BrowserCredential]) -> Data {
        var rows = [["name", "url", "username", "password", "note"]]
        rows.reserveCapacity(credentials.count + 1)
        for credential in credentials {
            let descriptor = credential.descriptor
            rows.append([
                descriptor.displayName ?? descriptor.origin.host,
                descriptor.origin.description,
                descriptor.username,
                credential.password,
                descriptor.scope.settingsLabel ?? "",
            ])
        }
        let csv =
            rows
            .map { $0.map(csvField).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
        return Data(csv.utf8)
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
