import Foundation

/// The questions the core asks about the page, shown as alerts over the
/// window, with the person's answers sent back to the core.
extension MobileBrowserPage: BrowserPromptPresenting {
    // MARK: - Actions - Prompts

    func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal) {
        let question = asked.question
        let request = URLRequest(url: URL(string: question.sourceURL) ?? webView.url ?? URL(fileURLWithPath: "/"))
        let corePage = corePage
        let promptID = asked.promptID
        let reply: @MainActor @Sendable (Bool, String?) -> Void = { accepted, text in
            corePage.answer(AnswerScriptDialog(promptID: promptID, accepted: accepted, text: text))
        }
        question.kind.present(question, request: request, dismissal: dismissal, on: self, reply: reply)
    }

    func presentHTTPAuthenticationPrompt(
        _ prompt: BrowserHTTPAuthenticationPrompt,
        dismissal: BrowserPromptDismissal
    ) async -> BrowserHTTPAuthenticationPromptResponse? {
        await MobileBrowserDialogPresenter.presentHTTPAuthentication(
            prompt: prompt, spaceName: spaceName, dismissal: dismissal)
    }
}

/// Each kind of script dialog, shown as an alert over the window. A page
/// asking before it unloads is a confirmation like any other.
extension MobileBrowserPage: BrowserScriptDialogPresenting {
    func presentAlert(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        MobileBrowserDialogPresenter.presentAlert(message: question.message, request: request, dismissal: dismissal) {
            reply(true, nil)
        }
    }

    func presentConfirm(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        MobileBrowserDialogPresenter.presentConfirmation(
            message: question.message, request: request, dismissal: dismissal
        ) {
            reply($0, nil)
        }
    }

    func presentPrompt(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        MobileBrowserDialogPresenter.presentPrompt(
            message: question.message, defaultText: question.defaultText, request: request, dismissal: dismissal
        ) { answer in
            reply(answer != nil, answer)
        }
    }

    func presentBeforeUnload(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        presentConfirm(question, request: request, dismissal: dismissal, reply: reply)
    }
}
