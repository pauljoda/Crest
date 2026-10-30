import Foundation
import Observation

/// A page's credential capture and fill, on either engine. Messages arrive
/// from the credential content bridge; fills are evaluated back into the
/// document that asked.
@Observable
@MainActor
final class BrowserCredentialSession {
    typealias FillTarget = (formID: String, frame: BrowserContentFrame)
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
        offersOneTimeCodes: Bool = false,
        httpAuthentication: BrowserHTTPAuthenticationSession
    ) {
        state = BrowserCredentialPageState(spaceID: spaceID, core: core, offersOneTimeCodes: offersOneTimeCodes)
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
            fillTarget: message.formID.map { ($0, frame) }
        )
    }

    func fill(_ credential: BrowserCredential, for requestID: UUID, evaluate: Evaluate) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.fillContext(for: requestID, credential: credential)
        let result = try await evaluate(
            "return globalThis.__crestCredentialBridge?.fill(formID, username, password) === true;",
            [
                "formID": context.target.formID,
                "username": credential.descriptor.username,
                "password": credential.password,
            ],
            context.target.frame
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        state.completeFill(username: credential.descriptor.username, requestID: requestID)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID, evaluate: Evaluate) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.generatedPasswordFillContext(for: requestID)
        let result = try await evaluate(
            "return globalThis.__crestCredentialBridge?.fillGenerated(formID, password) === true;",
            [
                "formID": context.target.formID,
                "password": password,
            ],
            context.target.frame
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        state.completeGeneratedPasswordFill(requestID: requestID)
    }

    /// Puts the code the person picked into the focused code field of the frame
    /// that raised the prompt. The frame's own origin is checked again where
    /// the code lands, and nothing is submitted.
    func fillOneTimeCode(_ code: String, for requestID: UUID, evaluate: Evaluate) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.oneTimeCodeFillContext(for: requestID)
        let result = try await evaluate(
            "return globalThis.__crestCredentialBridge?.fillOneTimeCode(formID, origin, code) === true;",
            [
                "formID": context.target.formID,
                "origin": context.request.origin.description,
                "code": code,
            ],
            context.target.frame
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        state.completeOneTimeCodeFill(requestID: requestID)
    }
}
