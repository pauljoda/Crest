import Observation
import WebKit

@Observable
@MainActor
final class BrowserWebKitCredentialSession {
    typealias FillTarget = (formID: String, frame: WKFrameInfo)

    let state: BrowserCredentialPageState<FillTarget>
    private(set) var isEnabled: Bool
    @ObservationIgnored private let supportsAccess: Bool
    @ObservationIgnored private let httpAuthentication: BrowserHTTPAuthenticationSession

    init(
        spaceID: SpaceID,
        supportsAccess: Bool,
        isEnabled: Bool,
        httpAuthentication: BrowserHTTPAuthenticationSession
    ) {
        state = BrowserCredentialPageState(spaceID: spaceID)
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

    func receive(_ scriptMessage: WKScriptMessage, in webView: WKWebView) {
        guard isEnabled,
            scriptMessage.webView === webView,
            scriptMessage.name == BrowserCredentialContentBridge.messageHandlerName,
            let message = BrowserCredentialFormMessage(body: scriptMessage.body),
            let frameOrigin = origin(for: scriptMessage.frameInfo.securityOrigin),
            let topLevelURL = webView.url,
            let topLevelOrigin = CredentialOrigin(url: topLevelURL)
        else { return }

        state.receive(
            message,
            frameOrigin: frameOrigin,
            topLevelOrigin: topLevelOrigin,
            isMainFrame: scriptMessage.frameInfo.isMainFrame,
            fillTarget: message.formID.map { ($0, scriptMessage.frameInfo) }
        )
    }

    func fill(_ credential: BrowserCredential, for requestID: UUID, in webView: WKWebView) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.fillContext(for: requestID, credential: credential)
        let result = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fill(formID, username, password) === true;",
            arguments: [
                "formID": context.target.formID,
                "username": credential.descriptor.username,
                "password": credential.password,
            ],
            in: context.target.frame,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        state.completeFill(username: credential.descriptor.username, requestID: requestID)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID, in webView: WKWebView) async throws {
        guard isEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try state.generatedPasswordFillContext(for: requestID)
        let result = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fillGenerated(formID, password) === true;",
            arguments: [
                "formID": context.target.formID,
                "password": password,
            ],
            in: context.target.frame,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        state.completeGeneratedPasswordFill(requestID: requestID)
    }

    private func origin(for securityOrigin: WKSecurityOrigin) -> CredentialOrigin? {
        CredentialOrigin(
            securityProtocol: securityOrigin.protocol,
            host: securityOrigin.host,
            port: securityOrigin.port
        )
    }
}
