import Foundation

/// The person's answers to agents asking to use Crest: one question on screen
/// at a time, an agent that asks again while it is asked about waits for the
/// same answer, and at most `maximumWaiting` agents wait to be asked. A
/// question closes unanswered once every connection waiting on it is gone,
/// and turning agents off closes them all.
@MainActor
final class BrowserAgentApprovals {
    // MARK: - Types

    /// One open question, and the connections waiting on its answer.
    private final class Asking {
        let identity: AgentIdentity
        let dismissal: BrowserPromptDismissal
        var waiters: Set<ObjectIdentifier>
        var answer: Task<Bool, Never>?

        init(identity: AgentIdentity, dismissal: BrowserPromptDismissal, waiter: ObjectIdentifier) {
            self.identity = identity
            self.dismissal = dismissal
            waiters = [waiter]
        }
    }

    // MARK: - Static Variables

    static let maximumWaiting = 4

    // MARK: - Variables

    private let dialogs = BrowserDialogPresenter()
    private var asking: [Asking] = []
    /// The question asked last, which the next one waits for.
    private var last: Task<Void, Never>?

    // MARK: - Actions - Approval

    /// Returns once the person allowed `agent` for the connection `waiter`,
    /// asking them when no question about it is open. Throws `declined` when
    /// they did not, and `busy` when too many agents already wait.
    func approve(_ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, for waiter: ObjectIdentifier)
        async throws(BrowserAgentFailure)
    {
        if let open = asking.first(where: { $0.identity == agent.identity }), let answer = open.answer {
            open.waiters.insert(waiter)
            guard await answer.value else { throw .declined }
            return
        }
        guard asking.count < Self.maximumWaiting else { throw .busy }
        let dismissal = BrowserPromptDismissal()
        let question = Asking(identity: agent.identity, dismissal: dismissal, waiter: waiter)
        let earlier = last
        let answer = Task { [dialogs] in
            await earlier?.value
            guard !dismissal.isDismissed else { return false }
            let allowed = await dialogs.approveAgent(agent, client: client, dismissal: dismissal)
            return allowed && !dismissal.isDismissed
        }
        question.answer = answer
        asking.append(question)
        last = Task { _ = await answer.value }
        let allowed = await answer.value
        asking.removeAll { $0 === question }
        guard allowed else { throw .declined }
    }

    /// Stops the connection `waiter` waiting, closing unanswered any question
    /// no other connection waits on.
    func withdraw(_ waiter: ObjectIdentifier) {
        for question in asking where question.waiters.remove(waiter) != nil && question.waiters.isEmpty {
            question.dismissal.dismiss()
        }
    }

    /// Closes every open question unanswered.
    func dismissAll() {
        for question in asking { question.dismissal.dismiss() }
    }
}
