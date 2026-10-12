import Foundation

/// The person's answers to agents asking to use Crest: one question on screen
/// at a time, an agent that asks again while it is asked about waits for the
/// same answer, and at most `maximumWaiting` agents wait to be asked. Turning
/// agents off closes every question unanswered.
@MainActor
final class BrowserAgentApprovals {
    // MARK: - Types

    private struct Asking {
        let identity: AgentIdentity
        let answer: Task<Bool, Never>
    }

    // MARK: - Static Variables

    static let maximumWaiting = 4

    // MARK: - Variables

    private let dialogs = BrowserDialogPresenter()
    private var asking: [Asking] = []
    private var dismissals: [BrowserPromptDismissal] = []
    /// The question asked last, which the next one waits for.
    private var last: Task<Void, Never>?

    // MARK: - Actions - Approval

    /// Returns once the person allowed `agent`, asking them when no question
    /// about it is open. Throws `declined` when they did not, and `busy` when
    /// too many agents already wait.
    func approve(_ agent: BrowserAgentPeer.Program, client: AgentClientInfo?) async throws(BrowserAgentFailure) {
        if let open = asking.first(where: { $0.identity == agent.identity }) {
            guard await open.answer.value else { throw .declined }
            return
        }
        guard asking.count < Self.maximumWaiting else { throw .busy }
        let dismissal = BrowserPromptDismissal()
        dismissals.append(dismissal)
        let earlier = last
        let answer = Task { [dialogs] in
            await earlier?.value
            guard !dismissal.isDismissed else { return false }
            let allowed = await dialogs.approveAgent(agent, client: client, dismissal: dismissal)
            return allowed && !dismissal.isDismissed
        }
        asking.append(Asking(identity: agent.identity, answer: answer))
        last = Task { _ = await answer.value }
        let allowed = await answer.value
        asking.removeAll { $0.identity == agent.identity }
        dismissals.removeAll { $0 === dismissal }
        guard allowed else { throw .declined }
    }

    /// Closes every open question unanswered.
    func dismissAll() {
        for dismissal in dismissals { dismissal.dismiss() }
        dismissals = []
    }
}
