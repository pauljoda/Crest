# CrestAgents

The agent link protocol shared by the Mac app and its `crest-browser` helper:
the tool definitions agents discover, the JSON values that cross, the
line-delimited messages over the agent socket, and where that socket lives.
Foundation only; it is compiled into both sides rather than linked.

## Goal

One definition of what agents can ask Crest, readable by the helper while
Crest is closed and served by the app when it runs.

## Contents

| File | What it is |
| --- | --- |
| `AgentToolDefinition.swift` | A tool as an agent discovers it: name, description, arguments, behavior |
| `AgentToolDefinition+Browser.swift` | The browser's tool catalog |
| `AgentLink.swift` | What the helper and the app say over the socket, one JSON object per line |
| `AgentJSON.swift` | JSON values for arguments, results and schemas |
| `AgentSocketLocation.swift` | The per-bundle-identifier Unix socket in the person's Crest data |
| `MCPProtocolVersion.swift` | Model Context Protocol revisions the helper speaks |

## Depends on

Foundation, CryptoKit and Darwin. Compiled into `Crest`, `CrestNativeCore`,
`CrestBrowserHelper` and the `ChromiumHostFramework` template's targets
(`project.yml`); served by `CrestMac/App/Agents/` and
`CrestMac/Infrastructure/Agents/`, spoken by `CrestAgentHelper/`.

## Rules

- A new tool is a definition here and an instance in `CrestMac/App/Agents/BrowserAgentTool.swift` (that file's doc comment); the helper lists definitions without the app (`CrestAgents/AgentToolDefinition.swift` doc comment).
- Never mutate shared state from Swift for an agent; send a core intent (skill, "Architecture").
- Never open a window the person did not ask for (skill, "Windows and UI").
- Keep a test only for a contract such as Space ownership or authorization (skill, "Tests"); the agent suites are `CrestTests/BrowserAgentCatalogTests.swift` and `CrestTests/BrowserAgentMutationTests.swift`.

## Read next

`CrestAgentHelper/CONTEXT.md`, `CrestMac/App/Agents/`, and the user-facing
behavior in `HelpCenter/docs/browsing/coding-agents.md`.
