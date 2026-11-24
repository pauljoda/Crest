import Foundation
import Observation

/// A page's credential capture and fill, on either engine. Messages arrive
/// from the credential content bridge; fills are evaluated back into the
/// document that asked.
@Observable
@MainActor
final class BrowserCredentialSession {
    /// Where a fill lands: the form, the page script's reading of its fields
    /// that the core chose them from, and the frame.
    typealias FillTarget = (formID: String, readingID: Int, frame: BrowserContentFrame)
    typealias Evaluate = @MainActor (String, [String: Any], BrowserContentFrame) async throws -> Any?

    let state: BrowserCredentialPageState<FillTarget>
    private(set) var isEnabled: Bool
    @ObservationIgnored private let supportsAccess: Bool
    @ObservationIgnored private let httpAuthentication: BrowserHTTPAuthenticationSession

    init(
        spaceID: UUID,
        core: CrestCore,
        supportsAccess: Bool,
        isEnabled: Bool,
        httpAuthentication: BrowserHTTPAuthenticationSession
    ) {
        state = BrowserCredentialPageState(spaceID: spaceID, core: core)
        self.supportsAccess = supportsAccess
        self.isEnabled = supportsAccess && isEnabled
        self.httpAuthentication = httpAuthentication
    }

    func setEnabled(_ isEnabled: Bool) {
        let resolvedValue = supportsAccess && isEnabled
        guard self.isEnabled != resolvedValue else { return }
        self.isEnabled = resolvedValue
        httpAuthentication.setCredentialStorageEnabled(resolvedValue)
        if !resolvedValue {
            state.reset()
        }
    }

    func receive(_ body: Any, from frame: BrowserContentFrame, topLevelURL: URL?) {
        guard isEnabled,
            let message = BrowserCredentialFormMessage(body: body),
            let frameOrigin = CredentialOrigin(
                securityProtocol: frame.securityProtocol,
                host: frame.host,
                port: frame.port
            ),
            let topLevelURL,
            let topLevelOrigin = CredentialOrigin(url: topLevelURL)
        else { return }

        state.receive(
            message,
            frameOrigin: frameOrigin,
            topLevelOrigin: topLevelOrigin,
            isMainFrame: frame.isMainFrame,
            fillTarget: message.formID.flatMap { formID in message.readingID.map { (formID, $0, frame) } }
        )
    }

    /// Fills a saved login into the fields the core chose: its username, and
    /// its password where the form asks for one, so a username step takes
    /// the username alone.
    func fill(_ credential: BrowserCredential, for requestID: UUID, evaluate: Evaluate) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.fillContext(for: requestID, credential: credential)
        let fields = context.request.fields
        let entries = [
            fields.username.map { ["index": $0, "value": credential.descriptor.username] as [String: Any] },
            fields.password.map { ["index": $0, "value": credential.password] as [String: Any] },
        ].compactMap { $0 }
        try await fill(entries, generated: false, into: context.target, evaluate: evaluate)
        state.completeFill(username: credential.descriptor.username, requestID: requestID)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID, evaluate: Evaluate) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.generatedPasswordFillContext(for: requestID)
        let entries = context.request.fields.newPasswords.map { ["index": $0, "value": password] as [String: Any] }
        try await fill(entries, generated: true, into: context.target, evaluate: evaluate)
        state.completeGeneratedPasswordFill(requestID: requestID)
    }

    /// What the form's username field holds now, empty when the person
    /// cleared it, for a password Crest makes before the form is sent; nil
    /// when the form has no username field or it can't be read.
    func currentUsername(for requestID: UUID, evaluate: Evaluate) async -> String? {
        guard isEnabled, let context = try? state.generatedPasswordFillContext(for: requestID),
            let index = context.request.fields.username
        else { return nil }
        return try? await evaluate(
            "return globalThis.__crestCredentialBridge?.valueOf(formID, readingID, index) ?? null;",
            ["formID": context.target.formID, "readingID": context.target.readingID, "index": index],
            context.target.frame) as? String
    }

    private func fill(
        _ entries: [[String: Any]], generated: Bool, into target: FillTarget, evaluate: Evaluate
    ) async throws {
        guard !entries.isEmpty else { throw BrowserCredentialFillError.formChanged }
        let result = try await evaluate(
            "return globalThis.__crestCredentialBridge?.fill(formID, readingID, entries, generated) === true;",
            ["formID": target.formID, "readingID": target.readingID, "entries": entries, "generated": generated],
            target.frame
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
    }
}
