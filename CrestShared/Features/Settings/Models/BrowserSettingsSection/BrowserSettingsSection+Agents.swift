import Foundation

/// The sections of the Agents settings page.
///
/// Coding agents and scripts.
extension BrowserSettingsSection {
    static let agentAccess = BrowserSettingsSection(
        name: "agentAccess", title: "Agents",
        searchTerms:
            "allow agents to use Crest AI MCP model context protocol coding agents automation Claude Codex Cursor"
    )
    static let agentConnection = BrowserSettingsSection(
        name: "agentConnection", title: "Connect an Agent",
        searchTerms: "connect an agent command line terminal")
    static let agentSpaces = BrowserSettingsSection(
        name: "agentSpaces", title: "Spaces",
        searchTerms: "agent Spaces allowed")
    static let agentScripts = BrowserSettingsSection(
        name: "agentScripts", title: "Scripts",
        searchTerms: "let agents run scripts in pages")
    static let agentSessions = BrowserSettingsSection(
        name: "agentSessions", title: "Connected",
        searchTerms: "connected agents sessions activity")
    static let allowedAgents = BrowserSettingsSection(
        name: "allowedAgents", title: "Allowed agents",
        searchTerms: "allowed agents remove")
}
