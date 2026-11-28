import Foundation

/// Why Crest did not do what an agent asked, in words the agent's model reads
/// and can act on.
struct BrowserAgentFailure: Error, Sendable {
    // MARK: - Static Variables

    static let notAttached = Self("The helper has not introduced the agent yet.")
    static let unidentified = Self("Crest couldn’t tell which program this agent is.")
    static let declined = Self("The person didn’t allow this agent to use Crest.")
    static let historyKept = Self("The person kept this history.")
    static let windowDeclined = Self("The person didn’t let this agent open a window.")
    static let busy = Self("Crest is already asking the person about agents. Try again shortly.")
    static let noWindow = Self(
        "Crest could not open a browser window.")
    static let unsupportedAddress = Self("Agents may open only http and https addresses.")
    static let noPage = Self("The tab’s page could not be loaded.")
    static let timedOut = Self("The page took too long to answer.")
    static let scriptsOff = Self(
        "The person hasn’t allowed agents to run scripts in pages. They can allow it in Crest’s Settings › Agents.")
    static let pinnedOrSaved = Self("Agents may close only open tabs, never pinned or saved ones.")
    static let notEditable = Self("That element isn’t a text field, text area, editable element or menu.")
    static let notWebPage = Self(
        "The tab shows a browser or extension page, or a file, which agents can’t use. Open a web page instead.")
    static let tooLarge = Self(
        "The answer was too large to send. Ask for less, such as one element or the viewport, not the whole page.")
    static let signInOff = Self(
        "The person hasn’t allowed agents to sign in with saved passwords. They can allow it in Crest’s Settings › Agents."
    )
    static let signInWithScripts = Self(
        "Crest doesn’t sign agents in while they may run scripts in pages, which could read a filled password. The person can turn off scripts in pages in Crest’s Settings › Agents."
    )
    static let passwordsOff = Self("Crest Passwords is off in this tab’s Space. Ask the person to sign in.")
    static let passwordsElsewhere = Self(
        "An extension handles passwords in this tab’s Space, so Crest doesn’t fill them. Ask the person to sign in.")
    static let insecurePage = Self("Crest fills saved passwords only on pages served over HTTPS.")
    static let notSignInField = Self(
        "That element isn’t a field of a sign-in form Crest can fill. Use the uid of the form’s username or password field."
    )
    static let otherSiteField = Self(
        "The sign-in form isn’t the tab’s own page’s, such as one in a frame from another site. Crest fills only the page’s own sign-in forms."
    )
    static let noSavedLogin = Self(
        "This Space’s Crest Passwords has no saved login for this site. Ask the person to sign in.")
    static let signInDeclined = Self("The person didn’t let Crest fill a saved password.")
    static let signInChanged = Self(
        "The sign-in form changed before Crest could fill it. Take a new snapshot and try again.")

    // MARK: - Variables

    let message: String

    // MARK: - Initializers

    init(_ message: String) {
        self.message = message
    }

    // MARK: - Actions - Failures

    static func rejected(_ rejection: Rejection) -> Self {
        Self(rejection.explanation)
    }

    static func unknownTool(_ name: String) -> Self {
        Self("Crest has no tool named \(name).")
    }

    static func invalidArguments(_ detail: String) -> Self {
        Self("The arguments are not valid: \(detail)")
    }

    static func unknownElement(_ uid: String) -> Self {
        Self("The page has no element \(uid) now. Take a new snapshot and use its uids.")
    }

    static func spaceLocked(_ name: String) -> Self {
        Self("The \(name) Space is locked. Ask the person to unlock it in Crest.")
    }

    static func script(_ message: String) -> Self {
        Self("The script threw: \(message)")
    }

    /// The page is showing `asked`, which holds up its scripts until someone
    /// answers it.
    static func dialog(_ asked: ScriptDialogAsked) -> Self {
        let message = String(asked.question.message.prefix(500))
        return asked.question.kind == .beforeUnload
            ? Self("The page is asking the person whether to leave it. Wait for them to answer.")
            : Self("The page is showing a dialog: “\(message)”. Answer it with handle_dialog.")
    }

    static func refused(_ detail: String) -> Self {
        Self(detail)
    }
}
