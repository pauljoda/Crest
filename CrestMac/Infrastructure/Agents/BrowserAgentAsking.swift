import Foundation

// MARK: - Types

/// An agent asking to remove every visit to `address` from the history of the
/// Space named `spaceName`, as the person is asked about it: by the name they
/// allowed the agent under.
struct BrowserAgentHistoryDeletion: Equatable, Sendable {
    let agentName: String
    let address: String
    let spaceName: String
}

/// What asks the person about agents: Crest's dialogs, or a test that answers
/// for them. A `dismissal` closes a question unanswered, which declines.
@MainActor
protocol BrowserAgentAsking: AnyObject {
    func approveAgent(_ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, dismissal: BrowserPromptDismissal?)
        async -> Bool
    func approveHistoryDeletion(_ deletion: BrowserAgentHistoryDeletion, dismissal: BrowserPromptDismissal?) async
        -> Bool
}

extension BrowserDialogPresenter: BrowserAgentAsking {}
