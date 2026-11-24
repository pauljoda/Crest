import Foundation
import Observation

// MARK: - Types

/// A login the person chose on a step that asked only for the username, which
/// the site's password step after it fills.
struct BrowserCredentialChosenAccount: Equatable, Sendable {
    /// How long after the choice the password step may take it.
    static let lifetime: TimeInterval = 5 * 60

    let credentialID: UUID
    let origin: CredentialOrigin
    let chosenAt: Date
}

struct BrowserCredentialUsernameHint: Equatable, Sendable {
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let username: String
    let capturedAt: Date
}

/// One form message the core decided on, with where it came from, what a
/// fill would write into, and when the page saw it.
struct BrowserCredentialObservation<FillTarget> {
    let message: BrowserCredentialFormMessage
    let frameOrigin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let fillTarget: FillTarget?
    let decision: CredentialCaptureDecision
    let now: Date
}

/// Owns the short-lived credential state for one retained browser page.
///
/// The generic fill target is intentionally opaque here. WebKit pages use a
/// `WKFrameInfo`, while tests can use a harmless value. The immutable Space ID
/// prevents a prompt from following the app's currently selected Space.
@Observable
@MainActor
final class BrowserCredentialPageState<FillTarget> {
    let spaceID: UUID
    @ObservationIgnored private let core: CrestCore

    private(set) var fillRequest: BrowserCredentialFillRequest?
    private(set) var saveCandidate: BrowserCredentialSaveCandidate?

    /// A candidate the person answered Not Now to, kept while the page stays
    /// on its site, so the key in the address field can offer it again.
    private(set) var heldSaveCandidate: BrowserCredentialSaveCandidate?

    /// The login the page last filled, whose code the next step offers first.
    @ObservationIgnored private(set) var lastFilledCredentialID: UUID?

    /// The login chosen on the username step, for the password step after it,
    /// once and only shortly after.
    @ObservationIgnored private var chosenAccount: BrowserCredentialChosenAccount?

    /// Whether an extension handles passwords in the page's profile, so the
    /// page offers and saves no passwords or codes, though addresses and cards
    /// still fill.
    @ObservationIgnored var passwordsHandledElsewhere = false {
        didSet {
            guard passwordsHandledElsewhere else { return }
            dismissFillRequest()
            dismissSaveCandidate()
            heldSaveCandidate = nil
        }
    }

    /// An address or card a sent form proposed to keep, until the person
    /// answers.
    private(set) var autofillSaveCandidate: BrowserAutofillSaveCandidate?

    /// The latest key the page held back for the fill popup on show.
    private(set) var keyPress: BrowserCredentialKeyPress?

    @ObservationIgnored private var fillTargets: [UUID: FillTarget] = [:]

    /// The form the live request's field belongs to, kept here rather than on
    /// the request itself: a later geometry report has to prove it is about the
    /// same field before it may move the prompt, and the form's ID is the only
    /// name both sides of the bridge agree on.
    @ObservationIgnored private var fillFormID: String?
    @ObservationIgnored private var pendingUsernameHint: BrowserCredentialUsernameHint?
    @ObservationIgnored private var usernameExpirationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveCandidate: BrowserCredentialSaveCandidate?
    @ObservationIgnored private var candidateExpirationTask: Task<Void, Never>?

    init(spaceID: UUID, core: CrestCore) {
        self.spaceID = spaceID
        self.core = core
    }

    /// Applies one validated form message. The portable core decides what
    /// the message means from its redacted facts; the username and password
    /// values stay here. Without a core answer nothing is captured or offered.
    func receive(
        _ message: BrowserCredentialFormMessage,
        frameOrigin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        isMainFrame: Bool,
        fillTarget: FillTarget?
    ) {
        guard let event = message.event.captureEvent else {
            if let key = message.key {
                press(key, from: message, frameOrigin: frameOrigin)
            } else {
                followField(message, frameOrigin: frameOrigin, isMainFrame: isMainFrame)
            }
            return
        }
        let now = Date.now
        let facts = CredentialFormFacts(
            event: event, frameOrigin: frameOrigin, topLevelOrigin: topLevelOrigin, isMainFrame: isMainFrame,
            hasFormID: message.formID != nil, fields: message.fields, focusedField: message.focusedField,
            submission: message.submission, filledUsername: false,
            hasVisiblePasswordField: message.hasVisiblePasswordField, hasFillTarget: fillTarget != nil,
            fieldRectInTopViewport: message.fieldRectInTopViewport)
        guard
            let decision = captureDecision(
                facts, usernameHint: pendingUsernameHint,
                pendingCandidate: message.event.weighsPendingCandidate ? pendingSaveCandidate : nil, now: now)
        else {
            // Fail safe: close any fill prompt this page shows and capture nothing.
            if message.event.closesFillWhenRefused { dismissFillRequest() }
            return
        }
        if decision.clearsUsernameHint { clearUsernameHint() }
        captureAutofill(message, frameOrigin: frameOrigin, topLevelOrigin: topLevelOrigin)
        decision.action.take(
            BrowserCredentialObservation(
                message: message, frameOrigin: frameOrigin, topLevelOrigin: topLevelOrigin, fillTarget: fillTarget,
                decision: decision, now: now),
            on: self)
    }

    /// A form sent from a secure page with an address or card the person
    /// typed proposes to keep it, as the core reads the fields.
    private func captureAutofill(
        _ message: BrowserCredentialFormMessage, frameOrigin: CredentialOrigin, topLevelOrigin: CredentialOrigin
    ) {
        guard message.submission != nil, !message.values.isEmpty, frameOrigin.isSecure, topLevelOrigin.isSecure else {
            return
        }
        let values = message.values.map { AutofillValue(field: $0.key, value: $0.value) }
        guard let proposal = try? core.query(AutofillCapture(fields: message.fields, values: values)),
            proposal.address != nil || proposal.card != nil
        else { return }
        autofillSaveCandidate = BrowserAutofillSaveCandidate(
            id: UUID(),
            address: proposal.address.map {
                var address = $0
                address.id = UUID()
                return address
            },
            card: proposal.card.map {
                var card = $0
                card.id = UUID()
                return card
            })
    }

    func dismissAutofillSaveCandidate() {
        autofillSaveCandidate = nil
    }

    /// A held key answers only the popup on show for the same form and frame.
    private func press(
        _ key: BrowserCredentialPopupKey,
        from message: BrowserCredentialFormMessage,
        frameOrigin: CredentialOrigin
    ) {
        guard let request = fillRequest, request.origin == frameOrigin, message.formID == fillFormID else { return }
        keyPress = BrowserCredentialKeyPress(id: UUID(), key: key)
    }

    /// The form and frame the live request's fields belong to, for releasing
    /// or holding its keys.
    func fillTarget(for requestID: UUID) -> FillTarget? {
        guard fillRequest?.id == requestID else { return nil }
        return fillTargets[requestID]
    }

    /// A geometry report only moves the prompt already on show, and only for
    /// the same form's field, measured in the top page's viewport.
    private func followField(
        _ message: BrowserCredentialFormMessage,
        frameOrigin: CredentialOrigin,
        isMainFrame: Bool
    ) {
        guard isMainFrame || message.fieldRectInTopViewport,
            let request = fillRequest,
            request.fieldRect != nil,
            let formID = message.formID,
            formID == fillFormID,
            request.origin == frameOrigin,
            let fieldRect = message.fieldRect,
            fieldRect != request.fieldRect
        else {
            return
        }
        fillRequest = request.following(fieldRect)
    }

    func fillContext(
        for requestID: UUID,
        credential: BrowserCredential
    ) throws -> (request: BrowserCredentialFillRequest, target: FillTarget) {
        guard let request = fillRequest,
            request.id == requestID,
            fillAllowed(from: .saved, into: request.passwordKind),
            credential.descriptor.spaceID == spaceID,
            credential.descriptor.origin == request.origin,
            let target = fillTargets[requestID]
        else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        return (request, target)
    }

    func generatedPasswordFillContext(
        for requestID: UUID
    ) throws -> (request: BrowserCredentialFillRequest, target: FillTarget) {
        guard let request = fillRequest,
            request.id == requestID,
            fillAllowed(from: .generated, into: request.passwordKind),
            let target = fillTargets[requestID]
        else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        return (request, target)
    }

    func completeFill(username: String, requestID: UUID, credentialID: UUID? = nil) {
        guard let request = fillRequest, request.id == requestID else { return }
        if let credentialID { lastFilledCredentialID = credentialID }
        // A login chosen where only the username went in fills the password
        // step that follows; one whose password went in is done.
        chosenAccount = credentialID.flatMap { id in
            request.fields.password == nil && request.fields.username != nil
                ? BrowserCredentialChosenAccount(credentialID: id, origin: request.origin, chosenAt: .now) : nil
        }
        let facts = CredentialFormFacts(
            event: .filled, frameOrigin: request.origin, topLevelOrigin: request.topLevelOrigin,
            isMainFrame: request.fieldRect != nil, hasFormID: fillFormID != nil, fields: [], focusedField: nil,
            submission: nil, filledUsername: true, hasVisiblePasswordField: nil, hasFillTarget: true,
            fieldRectInTopViewport: request.fieldRect != nil)
        if let decision = captureDecision(facts, usernameHint: nil, pendingCandidate: nil, now: .now),
            decision.action == .rememberUsername
        {
            rememberUsername(
                username, origin: request.origin, topLevelOrigin: request.topLevelOrigin,
                lifetime: decision.usernameHintLifetime)
        }
        dismissFillRequest()
    }

    func completeGeneratedPasswordFill(requestID: UUID) {
        guard fillRequest?.id == requestID else { return }
        dismissFillRequest()
    }

    /// Whether a login chosen on a username step waits for `origin`'s
    /// password step.
    func awaitsPasswordStep(at origin: CredentialOrigin, now: Date) -> Bool {
        guard let chosenAccount, chosenAccount.origin == origin else { return false }
        return now.timeIntervalSince(chosenAccount.chosenAt) < BrowserCredentialChosenAccount.lifetime
    }

    func dismissFillRequest() {
        fillFormID = nil
        keyPress = nil
        guard let request = fillRequest else { return }
        fillTargets[request.id] = nil
        fillRequest = nil
    }

    func dismissSaveCandidate() {
        pendingSaveCandidate = nil
        candidateExpirationTask?.cancel()
        candidateExpirationTask = nil
        saveCandidate = nil
    }

    /// Puts the candidate on show away for now, keeping it for the address
    /// field's key.
    func holdSaveCandidate() {
        let candidate = saveCandidate
        dismissSaveCandidate()
        heldSaveCandidate = candidate
    }

    /// Shows the held candidate again, as one the person just asked to save.
    func reofferHeldSaveCandidate() {
        guard let held = heldSaveCandidate else { return }
        heldSaveCandidate = nil
        dismissFillRequest()
        dismissSaveCandidate()
        saveCandidate = held.reoffered(at: .now)
    }

    func didChangeTopLevelURL(to url: URL?) {
        let currentOrigin = url.flatMap(CredentialOrigin.init(url:))
        if let held = heldSaveCandidate, currentOrigin != held.topLevelOrigin {
            heldSaveCandidate = nil
        }
        guard let hint = pendingUsernameHint,
            let currentOrigin,
            currentOrigin != hint.topLevelOrigin
        else { return }
        clearUsernameHint()
    }

    func didStartNavigation() {
        dismissFillRequest()
    }

    func webContentProcessDidTerminate() {
        reset()
    }

    func reset() {
        dismissFillRequest()
        dismissSaveCandidate()
        autofillSaveCandidate = nil
        heldSaveCandidate = nil
        chosenAccount = nil
        clearUsernameHint()
    }

    private func rememberUsername(
        _ username: String,
        origin: CredentialOrigin,
        topLevelOrigin: CredentialOrigin,
        lifetime: TimeInterval
    ) {
        let hint = BrowserCredentialUsernameHint(
            origin: origin,
            topLevelOrigin: topLevelOrigin,
            username: username,
            capturedAt: .now
        )
        pendingUsernameHint = hint
        usernameExpirationTask?.cancel()
        usernameExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled,
                self?.pendingUsernameHint?.capturedAt == hint.capturedAt
            else { return }
            self?.pendingUsernameHint = nil
            self?.usernameExpirationTask = nil
        }
    }

    /// What one form observation does to the page's credential state. Nil
    /// when the core refuses the facts; the caller then captures and offers
    /// nothing. Only the facts cross: the username and password stay here.
    private func captureDecision(
        _ facts: CredentialFormFacts,
        usernameHint: BrowserCredentialUsernameHint?,
        pendingCandidate: BrowserCredentialSaveCandidate?,
        now: Date
    ) -> CredentialCaptureDecision? {
        let capture = CredentialCapture(
            facts: facts,
            hint: usernameHint.map {
                CredentialUsernameHint(
                    origin: $0.origin, topLevelOrigin: $0.topLevelOrigin,
                    capturedAt: $0.capturedAt.timeIntervalSince1970)
            },
            pending: pendingCandidate.map {
                CredentialPendingCandidate(origin: $0.origin, submittedAt: $0.submittedAt.timeIntervalSince1970)
            },
            now: now.timeIntervalSince1970)
        guard let decision = try? core.query(capture), decision.candidateLifetime > 0, decision.usernameHintLifetime > 0
        else { return nil }
        return decision
    }

    /// Whether a fill may take a saved credential or a generated password into
    /// a field of this kind. A core that refuses fills nothing.
    private func fillAllowed(from source: CredentialFillSource, into passwordKind: CredentialPasswordKind) -> Bool {
        (try? core.query(CredentialFill(source: source, passwordKind: passwordKind)))?.isAllowed ?? false
    }

    /// The username the core chose: the form's own, or the remembered one.
    /// A change of password that named no account has none yet; the saved
    /// login holding its current password names it when the save is planned.
    private func username(
        from source: CredentialUsernameSource,
        explicitUsername: String?
    ) -> String? {
        switch source {
        case .explicit: explicitUsername
        case .hint: pendingUsernameHint?.username
        case .currentPassword: ""
        case .none: nil
        }
    }

    private func clearUsernameHint() {
        usernameExpirationTask?.cancel()
        usernameExpirationTask = nil
        pendingUsernameHint = nil
    }
}

// MARK: - Actions - Capture

extension BrowserCredentialPageState: CredentialCapturePerformer {
    func ignore(_ observation: BrowserCredentialObservation<FillTarget>) {}

    func rememberUsername(_ observation: BrowserCredentialObservation<FillTarget>) {
        guard let username = observation.message.value(at: observation.decision.form.username) else { return }
        rememberUsername(
            username, origin: observation.frameOrigin, topLevelOrigin: observation.topLevelOrigin,
            lifetime: observation.decision.usernameHintLifetime)
    }

    func dismissFill(_ observation: BrowserCredentialObservation<FillTarget>) {
        dismissFillRequest()
    }

    func offerFill(_ observation: BrowserCredentialObservation<FillTarget>) {
        let message = observation.message
        let decision = observation.decision
        let form = decision.form
        // An extension that handles passwords keeps them and codes to itself.
        guard
            (decision.passwordKind != nil || decision.codeFields != nil) && !passwordsHandledElsewhere
                || decision.autofill != nil,
            let formID = message.formID,
            let fillTarget = observation.fillTarget
        else { return }
        // A code request names no password; its kind only stands in.
        let passwordKind = decision.passwordKind ?? .current
        // The password step after a username step where the person chose a
        // login takes that login, on the same site and shortly after; a
        // second focus in the same form keeps it.
        let takesPassword =
            decision.passwordKind == .current && decision.codeFields == nil && form.currentPassword != nil
        let waiting = takesPassword && awaitsPasswordStep(at: observation.frameOrigin, now: observation.now)
        let chosen =
            waiting
            ? chosenAccount?.credentialID
            : takesPassword && fillFormID == formID ? fillRequest?.chosenCredentialID : nil
        if waiting { chosenAccount = nil }
        // A hidden username field is the page's own record; a fill leaves it be.
        let usernameField = message.field(at: form.username)?.isVisible == true ? form.username : nil
        let request = BrowserCredentialFillRequest(
            id: UUID(),
            origin: observation.frameOrigin,
            topLevelOrigin: observation.topLevelOrigin,
            usernameHint: username(
                from: decision.usernameSource, explicitUsername: message.value(at: form.username)),
            passwordKind: passwordKind,
            isCrossOriginFrame: decision.isCrossOriginFrame,
            requestedAt: observation.now,
            fieldRect: decision.anchorsToField ? message.fieldRect : nil,
            fields: BrowserCredentialFillFields(
                username: usernameField, password: form.currentPassword, newPasswords: form.newPasswords),
            isQuietWithoutLogins: decision.quietWithoutLogins,
            // A new password follows the rules of the field it goes into,
            // even when the username field beside it asked for it.
            requirements: message.field(at: passwordKind == .new ? form.newPasswords.first : message.focusedField).map {
                PasswordRequirements(minLength: $0.minLength, maxLength: $0.maxLength, rules: $0.passwordRules)
            } ?? .none,
            codeFields: decision.codeFields,
            autofill: decision.autofill.flatMap { section in
                message.focusedField.map { BrowserAutofillOffer(section: section, fields: message.fields, focused: $0) }
            },
            chosenCredentialID: chosen
        )
        if let previousRequest = fillRequest {
            fillTargets[previousRequest.id] = nil
        }
        fillTargets[request.id] = fillTarget
        fillFormID = formID
        fillRequest = request
    }

    /// Keeps the password the form sent as a candidate, once every new
    /// password field agrees with it.
    func captureCandidate(_ observation: BrowserCredentialObservation<FillTarget>) {
        guard !passwordsHandledElsewhere else { return }
        let message = observation.message
        let decision = observation.decision
        let form = decision.form
        guard
            let username = username(
                from: decision.usernameSource, explicitUsername: message.value(at: form.username)),
            let password = message.value(at: form.keptPassword),
            let passwordKind = decision.passwordKind,
            form.newPasswords.allSatisfy({ message.value(at: $0) == password })
        else { return }
        dismissSaveCandidate()
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: observation.frameOrigin,
            topLevelOrigin: observation.topLevelOrigin,
            username: username,
            password: password,
            passwordKind: passwordKind,
            isCrossOriginFrame: decision.isCrossOriginFrame,
            submittedAt: observation.now,
            currentPassword: decision.usernameSource == .currentPassword ? message.value(at: form.currentPassword) : nil
        )
        dismissFillRequest()
        clearUsernameHint()
        heldSaveCandidate = nil
        pendingSaveCandidate = candidate
        let lifetime = decision.candidateLifetime
        candidateExpirationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled, let self else { return }
            if self.pendingSaveCandidate?.id == candidate.id {
                self.pendingSaveCandidate = nil
            }
            if self.saveCandidate?.id == candidate.id {
                self.saveCandidate = nil
            }
            self.candidateExpirationTask = nil
        }
    }

    func offerSave(_ observation: BrowserCredentialObservation<FillTarget>) {
        guard let candidate = pendingSaveCandidate else { return }
        pendingSaveCandidate = nil
        saveCandidate = candidate
    }

    func keepPending(_ observation: BrowserCredentialObservation<FillTarget>) {}

    func discardPending(_ observation: BrowserCredentialObservation<FillTarget>) {
        pendingSaveCandidate = nil
    }
}

enum BrowserCredentialFillError: Error, Equatable {
    case staleOrMismatchedRequest
    case formChanged
}
