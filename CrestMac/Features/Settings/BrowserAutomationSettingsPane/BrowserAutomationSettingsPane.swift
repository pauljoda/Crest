import AppKit
import SwiftUI

/// Whether local tools, such as scripts and coding agents, may control Crest
/// on this Mac, which of the person's Spaces they reach, and the tools the
/// person approved. Tools connect to the socket this pane names, which exists
/// only while automation is on.
struct BrowserAutomationSettingsPane: View {
    // MARK: - Variables

    let core: CrestCore
    @State private var failure: String?

    private var preferences: AutomationPreferences { core.state.automationPreferences }
    private let socketPath = BrowserAutomationEndpoint.path(for: .current)

    /// The Spaces of the person's own session that are not being deleted,
    /// which are the only ones tools may be allowed to reach.
    private var spaces: [SpaceModel] {
        guard let workspace = core.state.workspaces.values.first(where: { $0.kind.keepsAppPreferences }) else {
            return []
        }
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        return workspace.spaces.models.filter { !deleting.contains($0.id) }
    }

    // MARK: - Actions - Presentation

    var body: some View {
        BrowserSettingsPane(.automation) {
            Section {
                Toggle("Allow tools to control Crest", isOn: isOn)
                    .accessibilityIdentifier("automation-enabled")
                if preferences.isOn, let socketPath {
                    BrowserAutomationSocketRow(path: socketPath)
                }
            } footer: {
                CrestFormFootnote(
                    "Scripts and coding agents on this Mac can open, read and close tabs in the Spaces you choose. Crest asks before each new tool connects."
                )
            }
            Section {
                ForEach(spaces) { space in
                    Toggle(isOn: allows(space)) {
                        BrowserSpaceIdentityLabel(space: space)
                    }
                }
            } header: {
                Text("Spaces")
            } footer: {
                CrestFormFootnote("Tools never reach a private window, and see only the name of a locked Space.")
            }
            .disabled(!preferences.isOn)
            Section {
                if preferences.tools.isEmpty {
                    Text("No tools yet").foregroundStyle(.secondary)
                }
                ForEach(Array(preferences.tools.enumerated()), id: \.offset) { _, tool in
                    BrowserAutomationToolRow(tool: tool) { send(ForgetAutomationTool(tool: tool)) }
                }
            } header: {
                Text("Allowed tools")
            } footer: {
                CrestFormFootnote("Forgetting a tool disconnects it. Crest asks again the next time it connects.")
            }
            if let failure { Text(failure).foregroundStyle(.red) }
        }
    }

    // MARK: - Actions - Preferences

    private var isOn: Binding<Bool> {
        Binding {
            preferences.isOn
        } set: {
            send(SetAutomation(isOn: $0))
        }
    }

    private func allows(_ space: SpaceModel) -> Binding<Bool> {
        Binding {
            preferences.spaceIDs.contains(space.id)
        } set: {
            send(AllowAutomationSpace(spaceID: space.id, allowed: $0))
        }
    }

    private func send(_ intent: some AutomationIntent) {
        do {
            try core.send(intent)
            failure = nil
        } catch { failure = error.explanation }
    }
}

/// Where tools connect, with a button that copies it.
private struct BrowserAutomationSocketRow: View {
    let path: String

    var body: some View {
        LabeledContent("Socket") {
            HStack {
                Text(path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy the socket’s path")
            }
        }
    }
}

/// A tool the person allowed: the name it gave and the program it runs.
private struct BrowserAutomationToolRow: View {
    let tool: AutomationTool
    let forget: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(tool.name)
                Text(tool.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Forget") { forget() }
        }
    }
}

#if DEBUG
    #Preview("Allowed tool") {
        Form {
            BrowserAutomationToolRow(tool: AutomationTool(name: "crest", path: "/opt/homebrew/bin/crest")) {}
            BrowserAutomationSocketRow(path: "/Users/person/Library/Application Support/Crest/Automation.sock")
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
#endif
