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
    /// The request whose popup holds its field's keys, and where that field
    /// is, kept until the popup gives them back: a closing popup's request
    /// has already lost its fill target.
    @ObservationIgnored private var heldKeys: (requestID: UUID, target: FillTarget)?
    /// The frame whose field the person focused last, which the phone's
    /// previous and next buttons move through.
    @ObservationIgnored private var focusedFrame: BrowserContentFrame?

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

    func receive(_ body: Any, from frame: BrowserContentFrame, topLevelURL: URL?, evaluate: Evaluate? = nil) {
        guard isEnabled,
            let decoded = BrowserCredentialFormMessage(body: body),
            let frameOrigin = CredentialOrigin(
                securityProtocol: frame.securityProtocol,
                host: frame.host,
                port: frame.port
            ),
            let topLevelURL,
            let topLevelOrigin = CredentialOrigin(url: topLevelURL)
        else { return }
        // A frame the engine draws in its own view can't measure where it
        // sits in the page; the engine does, so its field can be pointed at.
        let message = frame.viewportOffset.map { decoded.placed(atFrameOffset: $0) } ?? decoded
        if message.event == .focus { focusedFrame = frame }

        state.receive(
            message,
            frameOrigin: frameOrigin,
            topLevelOrigin: topLevelOrigin,
            isMainFrame: frame.isMainFrame,
            fillTarget: message.formID.flatMap { formID in message.readingID.map { (formID, $0, frame) } }
        )
        // A password step that a login chosen on the username step waits for
        // takes it as soon as it shows, even where the page focuses nothing.
        if message.event == .documentState, message.hasVisiblePasswordField == true, state.fillRequest == nil,
            state.awaitsPasswordStep(at: frameOrigin, now: .now), let evaluate
        {
            Task {
                _ = try? await evaluate(
                    "return globalThis.__crestCredentialBridge?.offerPasswordStep() === true;", [:], frame)
            }
        }
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
        state.completeFill(
            username: credential.descriptor.username, requestID: requestID, credentialID: credential.descriptor.id)
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

    /// Fills the values the core planned for a code, an address or a card
    /// into the fields it named, by index.
    func fillValues(_ values: [BrowserAutofillValue], for requestID: UUID, evaluate: Evaluate) async throws {
        guard isEnabled, let target = state.fillTarget(for: requestID) else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let entries = values.map { ["index": $0.field, "value": $0.value] as [String: Any] }
        try await fill(entries, generated: false, into: target, evaluate: evaluate)
        state.dismissFillRequest()
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

    /// Sends the request's field's arrow, Return and Escape keys to Crest's
    /// popup while it is on show, or gives them back to the page. The keys go
    /// back to the field they were taken from, and only for the request that
    /// took them, so a stale release can't free a later popup's keys.
    func holdKeys(_ hold: Bool, for requestID: UUID, evaluate: Evaluate) async {
        let target: FillTarget
        if hold {
            guard isEnabled, let current = state.fillTarget(for: requestID) else { return }
            target = current
            heldKeys = (requestID, current)
        } else {
            guard let held = heldKeys, held.requestID == requestID else { return }
            target = held.target
            heldKeys = nil
        }
        _ = try? await evaluate(
            "return globalThis.__crestCredentialBridge?.holdKeys(formID, hold) === true;",
            ["formID": target.formID, "hold": hold], target.frame)
    }

    /// Moves focus to the form control before, -1, or after, 1, the focused
    /// one, in the frame that holds it. Nil when no field has reported focus
    /// or its frame is gone.
    func focusAdjacentField(_ step: Int, evaluate: Evaluate) async -> Bool? {
        guard let focusedFrame else { return nil }
        return try? await evaluate(
            "return globalThis.__crestCredentialBridge?.focusAdjacent(step) === true;", ["step": step], focusedFrame)
            as? Bool
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
