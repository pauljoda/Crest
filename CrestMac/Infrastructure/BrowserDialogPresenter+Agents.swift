import AppKit
import Foundation

extension BrowserDialogPresenter {
    // MARK: - Actions - Agents

    /// Whether `agent`, which macOS vouches for by its code signature, may use
    /// Crest. The question names the program macOS verified, never what the
    /// agent says of itself, except for a general interpreter, whose approval
    /// covers the agent by the name it gives. Crest comes forward, since the
    /// person is likely in the agent's terminal when it asks, and declining is
    /// the default. A `dismissal` closes the question unanswered.
    func approveAgent(
        _ agent: BrowserAgentPeer.Program, client: AgentClientInfo?, dismissal: BrowserPromptDismissal? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = String(localized: "Allow “\(agent.name)” to use Crest?")
            // A signed program is known by its signer; an unsigned one only by
            // where it is.
            var lines =
                agent.signer.map { [String(localized: "Signed by \($0).")] }
                ?? [String(localized: "This program isn’t signed by a developer."), agent.path]
            if agent.isInterpreter, let named = client.map({ Self.shown($0.name) }), !named.isEmpty {
                lines.append(
                    String(
                        localized:
                            "\(agent.name) runs other programs. Allowing it lets any program it runs that calls itself “\(named)” use Crest."
                    ))
            }
            lines.append(
                String(
                    localized:
                        "It can read history and search providers, manage tabs in the Spaces you choose in Settings › Agents, and open windows, including Private Windows. Private tabs remain inaccessible. Every tab it uses shows its badge."
                ))
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Don’t Allow"))
            alert.addButton(withTitle: String(localized: "Allow"))
            if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) }
            present(alert, comesForward: true, dismissal: dismissal) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    /// `name` as a question may show it: without control or formatting
    /// characters, such as the ones that reverse text, and at most 64
    /// characters.
    private static func shown(_ name: String) -> String {
        let kept = name.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: false
            default: true
            }
        }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .prefix(64).description
    }

}
