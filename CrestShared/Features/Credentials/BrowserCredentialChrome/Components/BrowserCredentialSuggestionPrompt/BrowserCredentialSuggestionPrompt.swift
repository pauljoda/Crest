import SwiftUI

/// The passwords this Space already holds for the site asking for one.
///
/// Everything the prompt needs from the page arrives through
/// `BrowserCredentialFillPort`, everything about how big it is comes from
/// `BrowserCredentialPromptMetrics`, and the surface under it is the one thing
/// a shell dresses differently. So both shells share this prompt rather than a
/// resemblance.
struct BrowserCredentialSuggestionPrompt: View {
    let request: BrowserCredentialFillRequest
    let port: BrowserCredentialFillPort
    let browser: BrowserStore
    let metrics: BrowserCredentialPromptMetrics

    @State private var model = BrowserCredentialSuggestionModel()
    @State private var fillErrorMessage: String?
    /// The request the model last loaded for, so a second load for the same
    /// one is a refresh of the rows on show.
    @State private var loadedRequestID: UUID?

    /// What a load is for: a new request, or the same one after a code arrived.
    private struct LoadKey: Hashable {
        let requestID: UUID
        let codeArrivals: Int
    }

    var body: some View {
        // A code field with nothing to offer shows nothing at all.
        ZStack {
            if !request.isOneTimeCodeField || !model.codes.isEmpty {
                surface
            }
        }
        .task(id: LoadKey(requestID: request.id, codeArrivals: codeArrivals)) { await load() }
        .onDisappear {
            model.cancel()
            if request.isOneTimeCodeField { browser.forgetOneTimeCodes(tab: port.tabID) }
        }
    }

    /// Only an open code list looks again when the helper announces a code.
    private var codeArrivals: Int {
        request.isOneTimeCodeField ? browser.oneTimeCodeArrivals : 0
    }

    private var surface: some View {
        BrowserCredentialPromptSurface(
            accessibilityLabel: Text("Crest password suggestions"),
            accessibilityIdentifier: "crest-password-suggestions",
            width: metrics.fillPromptWidth,
            metrics: metrics
        ) {
            BrowserCredentialSuggestionPromptContent(
                request: request,
                space: space,
                siteIconData: port.siteIconData,
                model: model,
                fillErrorMessage: fillErrorMessage,
                metrics: metrics,
                dismiss: port.dismiss,
                fill: fill,
                fillCode: fillCode,
                beginPairing: beginPairing,
                openPasswordsApp: openPasswordsApp,
                submitPairingCode: submitPairingCode
            )
        }
    }

    private func load() async {
        let refreshes = request.isOneTimeCodeField && loadedRequestID == request.id
        loadedRequestID = request.id
        fillErrorMessage = nil
        await model.load(request, in: port.spaceID, tab: port.tabID, keepsRows: refreshes, using: browser)
        if request.isOneTimeCodeField && model.codes.isEmpty && !Task.isCancelled { port.dismiss() }
    }

    private var space: BrowserSpaceIdentity? {
        browser.spaceModel(port.spaceID)?.identity
    }

    private func beginPairing() {
        Task { await model.beginPairing(in: port.spaceID, using: browser) }
    }

    private func openPasswordsApp() {
        Task { @MainActor in
            await browser.openApplePasswordsApp(for: request.origin, in: port.spaceID)
            port.dismiss()
        }
    }

    private func submitPairingCode(_ code: String) {
        Task { await model.submitPairingCode(code, for: request, in: port.spaceID, tab: port.tabID, using: browser) }
    }

    private func fill(_ suggestion: BrowserCredentialSuggestion) {
        Task { @MainActor in
            do {
                guard
                    let credential = try await browser.credential(
                        for: suggestion,
                        in: port.spaceID,
                        tab: port.tabID
                    )
                else {
                    fillErrorMessage = "That password is no longer available."
                    return
                }
                try await port.fill(credential, request.id)
            } catch {
                fillErrorMessage = "The form changed before Crest could fill it."
            }
        }
    }

    private func fillCode(_ code: BrowserOneTimeCodeSuggestion) {
        Task { @MainActor in
            do {
                let value = try await browser.oneTimeCode(
                    for: code, request: request, in: port.spaceID, tab: port.tabID)
                try await port.fillOneTimeCode(value, request.id)
            } catch BrowserCredentialFillError.formChanged {
                fillErrorMessage = "The form changed before Crest could fill it."
            } catch {
                fillErrorMessage = "That code is no longer available."
            }
        }
    }
}
