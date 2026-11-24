import Foundation
import LocalAuthentication
import Observation

typealias BrowserCredentialClipboardWriter =
    @MainActor (
        BrowserCredentialSecretLease
    ) -> Bool

typealias BrowserCredentialRevealer =
    @MainActor (
        UUID,
        BrowserSpaceRuntimeAssignment,
        String
    ) async throws -> BrowserCredential

/// Reads the notes and code a login keeps beside its password, once the
/// person has authenticated.
typealias BrowserCredentialExtrasReader =
    @MainActor (
        UUID,
        BrowserSpaceRuntimeAssignment
    ) async throws -> BrowserCredentialExtras?

/// Saves what the person changed about a login and returns it as saved.
typealias BrowserCredentialEditor =
    @MainActor (
        UUID,
        BrowserSpaceRuntimeAssignment,
        BrowserCredentialEdit
    ) async throws -> CredentialDescriptor

/// What the person is changing about a login while the editor is in Edit:
/// the text of each field, and the sites as typed, after the one the login
/// was saved for.
struct BrowserCredentialDraft: Equatable {
    var title: String
    var username: String
    var password: String
    var sites: [String]
    var notes: String
    /// The `otpauth` link of the login's code, or nil for none.
    var codeLink: String?
}

struct BrowserCredentialDetailOperationToken: Equatable, Sendable {
    let assignment: BrowserSpaceRuntimeAssignment
    let sequence: UInt64
}

@Observable
@MainActor
final class BrowserCredentialDetailModel {
    private(set) var revealLease: BrowserCredentialSecretLease?
    private(set) var isAuthenticating = false
    private(set) var copiedUntil: Date?
    private(set) var errorMessage: String?
    /// The login as last saved, which an edit replaces.
    private(set) var descriptor: CredentialDescriptor
    /// What the login keeps beside its password, once the person revealed it.
    private(set) var revealedExtras: BrowserCredentialExtras?
    /// Whether the login keeps notes, as the list read it without them.
    private(set) var hasNotes: Bool
    /// Whether the login makes one-time codes, as the list read it.
    private(set) var hasCode: Bool
    /// The edit in progress, or nil while the editor only shows the login.
    var draft: BrowserCredentialDraft?
    private(set) var isSaving = false

    let request: BrowserCredentialDetailRequest

    @ObservationIgnored private let isAssignmentCurrent:
        @MainActor (
            BrowserSpaceRuntimeAssignment
        ) -> Bool
    @ObservationIgnored private let revealCredential: BrowserCredentialRevealer
    @ObservationIgnored private let readExtras: BrowserCredentialExtrasReader
    @ObservationIgnored private let saveEdit: BrowserCredentialEditor
    /// Draws a new strong password for the login's site, or nil when none
    /// can be made.
    @ObservationIgnored let makeStrongPassword: () -> String?
    @ObservationIgnored private let writeClipboard: BrowserCredentialClipboardWriter
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private var operationSequence: UInt64 = 0
    @ObservationIgnored private var activeOperationToken: BrowserCredentialDetailOperationToken?
    @ObservationIgnored private var activeOperationTask: Task<Void, Never>?

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        request.spaceAssignment
    }

    var spaceName: String {
        request.spaceName
    }

    var visiblePassword: String? {
        revealLease?.password(at: now())
    }

    var revealExpiration: Date? {
        revealLease?.expiration
    }

    var copyExpiration: Date? {
        copiedUntil
    }

    var showsCopyConfirmation: Bool {
        copiedUntil != nil
    }

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        request: BrowserCredentialDetailRequest
    ) {
        let sensitiveAccess = BrowserCredentialSensitiveAccess(browser: browser)
        self.request = request
        descriptor = request.descriptor
        hasNotes = request.hasNotes
        hasCode = request.hasCode
        isAssignmentCurrent = { spaceAssignment in
            guard let space = browser.spaceModel(matching: spaceAssignment) else {
                return false
            }
            return !spaceAccess.isLocked(space)
        }
        revealCredential = { credentialID, spaceAssignment, reason in
            try await sensitiveAccess.revealCredential(
                id: credentialID,
                matching: spaceAssignment,
                reason: reason
            )
        }
        readExtras = { credentialID, spaceAssignment in
            guard browser.spaceModel(matching: spaceAssignment) != nil else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            return try await browser.credentialExtras(id: credentialID, in: spaceAssignment.spaceID)
        }
        saveEdit = { credentialID, spaceAssignment, edit in
            guard browser.spaceModel(matching: spaceAssignment) != nil else {
                throw BrowserCredentialSensitiveAccessError.missingCredential
            }
            return try await browser.editCredential(id: credentialID, in: spaceAssignment.spaceID, edit: edit)
        }
        makeStrongPassword = {
            (try? browser.strongPasswordRecipe()).flatMap { try? BrowserStrongPasswordGenerator.generate(from: $0) }
        }
        writeClipboard = BrowserCredentialClipboard.write
        now = { .now }
        sleep = { try await Task.sleep(for: $0) }
    }

    init(
        descriptor: CredentialDescriptor,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String = "Space",
        isAssignmentCurrent:
            @escaping @MainActor (
                BrowserSpaceRuntimeAssignment
            ) -> Bool,
        revealCredential: @escaping BrowserCredentialRevealer,
        readExtras: @escaping BrowserCredentialExtrasReader = { _, _ in nil },
        saveEdit: @escaping BrowserCredentialEditor = { _, _, _ in
            throw BrowserCredentialSensitiveAccessError.missingCredential
        },
        writeClipboard: @escaping BrowserCredentialClipboardWriter,
        now: @escaping @MainActor () -> Date = { .now },
        sleep: @escaping @MainActor (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        request = BrowserCredentialDetailRequest(
            descriptor: descriptor,
            spaceAssignment: assignment,
            spaceName: spaceName
        )
        self.descriptor = descriptor
        hasNotes = false
        hasCode = false
        self.isAssignmentCurrent = isAssignmentCurrent
        self.revealCredential = revealCredential
        self.readExtras = readExtras
        self.saveEdit = saveEdit
        makeStrongPassword = { nil }
        self.writeClipboard = writeClipboard
        self.now = now
        self.sleep = sleep
    }

    func toggleReveal() async {
        if visiblePassword != nil {
            revealLease = nil
            return
        }
        guard let token = beginAuthentication() else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performReveal(token: token)
        }
        activeOperationTask = task
        await task.value
        finishAuthentication(token: token)
    }

    func copy() async {
        guard let token = beginAuthentication() else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCopy(token: token)
        }
        activeOperationTask = task
        await task.value
        finishAuthentication(token: token)
    }

    func expireReveal(at expiration: Date) async {
        guard await waitUntil(expiration), !Task.isCancelled else { return }
        guard revealLease?.expiration == expiration else { return }
        revealLease = nil
    }

    func expireCopyConfirmation(at expiration: Date) async {
        guard await waitUntil(expiration), !Task.isCancelled else { return }
        guard copiedUntil == expiration else { return }
        copiedUntil = nil
    }

    func clearSensitiveState() {
        cancelActiveOperation()
        revealLease = nil
        copiedUntil = nil
        errorMessage = nil
        revealedExtras = nil
        draft = nil
    }

    // MARK: - Actions - Editing

    /// Authenticates once and opens the login for editing, its password and
    /// notes in the fields.
    func beginEditing() async {
        guard draft == nil, let token = beginAuthentication() else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let credential = try await revealCredential(
                    descriptor.id, spaceAssignment,
                    String(localized: "Authenticate to edit the Crest password for \(descriptor.origin.host)."))
                let extras = try await readExtras(descriptor.id, spaceAssignment)
                guard !Task.isCancelled, activeOperationToken == token, isCurrent(token),
                    credentialMatchesRequest(credential)
                else { return }
                revealedExtras = extras ?? .empty
                draft = BrowserCredentialDraft(
                    title: descriptor.displayName ?? "", username: descriptor.username, password: credential.password,
                    sites: descriptor.sites.map(\.description), notes: extras?.notes ?? "", codeLink: extras?.codeLink)
            } catch {
                guard !Task.isCancelled, activeOperationToken == token, isCurrent(token) else { return }
                handleAccessError(error)
            }
        }
        activeOperationTask = task
        await task.value
        finishAuthentication(token: token)
    }

    func cancelEditing() {
        draft = nil
        errorMessage = nil
    }

    /// Saves the edit, after checking every site the person typed is a web
    /// address. Returns whether it saved.
    @discardableResult
    func commitEditing() async -> Bool {
        guard let draft, !isSaving, isAssignmentCurrent(spaceAssignment) else { return false }
        var sites: [CredentialOrigin] = []
        for text in draft.sites.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !text.isEmpty {
            guard let site = CredentialOrigin(typed: text) else {
                errorMessage = String(localized: "“\(text)” isn’t a website address.")
                return false
            }
            sites.append(site)
        }
        guard !draft.password.isEmpty else {
            errorMessage = String(localized: "A login needs a password.")
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let notes = String(draft.notes.prefix(BrowserCredentialExtras.maximumNotesLength))
        let extras = revealedExtras.map { _ in BrowserCredentialExtras(notes: notes, codeLink: draft.codeLink) }
        do {
            descriptor = try await saveEdit(
                descriptor.id, spaceAssignment,
                BrowserCredentialEdit(
                    title: draft.title, username: draft.username, sites: sites, password: draft.password,
                    extras: extras == revealedExtras ? nil : extras))
            revealedExtras = extras
            if let extras {
                hasNotes = !extras.notes.isEmpty
                hasCode = extras.codeLink != nil
            }
            self.draft = nil
            return true
        } catch {
            errorMessage = String(localized: "Crest couldn’t save those changes.")
            return false
        }
    }

    /// Authenticates and shows the notes and code the login keeps.
    func revealExtras() async {
        guard revealedExtras == nil, let token = beginAuthentication() else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let credential = try await revealCredential(
                    descriptor.id, spaceAssignment,
                    String(localized: "Authenticate to view the notes and code for \(descriptor.origin.host)."))
                let extras = try await readExtras(descriptor.id, spaceAssignment)
                guard !Task.isCancelled, activeOperationToken == token, isCurrent(token),
                    credentialMatchesRequest(credential)
                else { return }
                revealedExtras = extras ?? .empty
            } catch {
                guard !Task.isCancelled, activeOperationToken == token, isCurrent(token) else { return }
                handleAccessError(error)
            }
        }
        activeOperationTask = task
        await task.value
        finishAuthentication(token: token)
    }

    private func performReveal(token: BrowserCredentialDetailOperationToken) async {
        do {
            let credential = try await revealCredential(
                descriptor.id,
                spaceAssignment,
                String(
                    localized: "Authenticate to reveal the Crest password for \(descriptor.origin.host)."
                )
            )
            guard !Task.isCancelled,
                activeOperationToken == token,
                isCurrent(token),
                credentialMatchesRequest(credential)
            else { return }
            revealLease = .reveal(
                password: credential.password,
                issuedAt: now()
            )
        } catch {
            guard !Task.isCancelled, activeOperationToken == token,
                isCurrent(token)
            else { return }
            handleAccessError(error)
        }
    }

    private func performCopy(token: BrowserCredentialDetailOperationToken) async {
        do {
            let credential = try await revealCredential(
                descriptor.id,
                spaceAssignment,
                String(
                    localized: "Authenticate to copy the Crest password for \(descriptor.origin.host)."
                )
            )
            guard !Task.isCancelled,
                activeOperationToken == token,
                isCurrent(token),
                credentialMatchesRequest(credential)
            else { return }
            let lease = BrowserCredentialSecretLease.clipboard(
                password: credential.password,
                issuedAt: now()
            )
            guard writeClipboard(lease) else {
                errorMessage = String(
                    localized: "Crest couldn’t copy that password."
                )
                return
            }
            copiedUntil = lease.expiration
        } catch {
            guard !Task.isCancelled, activeOperationToken == token,
                isCurrent(token)
            else { return }
            handleAccessError(error)
        }
    }

    private func beginAuthentication() -> BrowserCredentialDetailOperationToken? {
        guard !isAuthenticating,
            descriptor.spaceID == spaceAssignment.spaceID,
            isAssignmentCurrent(spaceAssignment)
        else {
            if !isAuthenticating {
                errorMessage = Self.accessFailureMessage
            }
            return nil
        }
        operationSequence &+= 1
        let token = BrowserCredentialDetailOperationToken(
            assignment: spaceAssignment,
            sequence: operationSequence
        )
        activeOperationToken = token
        isAuthenticating = true
        errorMessage = nil
        return token
    }

    private func finishAuthentication(
        token: BrowserCredentialDetailOperationToken
    ) {
        guard activeOperationToken == token else { return }
        activeOperationTask = nil
        activeOperationToken = nil
        isAuthenticating = false
    }

    private func cancelActiveOperation() {
        operationSequence &+= 1
        activeOperationTask?.cancel()
        activeOperationTask = nil
        activeOperationToken = nil
        isAuthenticating = false
    }

    private func isCurrent(
        _ token: BrowserCredentialDetailOperationToken
    ) -> Bool {
        token.assignment == spaceAssignment
            && activeOperationToken == token
            && isAssignmentCurrent(spaceAssignment)
    }

    private func credentialMatchesRequest(
        _ credential: BrowserCredential
    ) -> Bool {
        credential.descriptor.id == descriptor.id
            && credential.descriptor.spaceID == descriptor.spaceID
    }

    private func handleAccessError(_ error: Error) {
        guard !Self.isAuthenticationCancellation(error) else { return }
        errorMessage = Self.accessFailureMessage
    }

    private func waitUntil(_ date: Date) async -> Bool {
        let delay = max(0, date.timeIntervalSince(now()))
        do {
            try await sleep(.seconds(delay))
            return true
        } catch {
            return false
        }
    }

    private static var accessFailureMessage: String {
        String(
            localized: "Crest couldn’t authenticate and read that password from this Space."
        )
    }

    private static func isAuthenticationCancellation(_ error: Error) -> Bool {
        guard let error = error as? LAError else { return false }
        return switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            true
        default:
            false
        }
    }
}
