# CrestAgentHelper

`crest-browser`, the command-line helper agents run as an MCP server
(`crest-browser mcp`). It speaks the Model Context Protocol over its standard
streams, answers discovery and the tool list itself, and hands each tool call
to the Crest app it ships inside over the agent socket. Mac only.

## Goal

Let an agent see Crest's tools even while Crest is closed, and reach the
running app only for the calls that need it.

## Contents

| File | What it is |
| --- | --- |
| `main.swift` | Entry point: argument handling and the socket it connects to |
| `AgentHelperEndpoint.swift` | The MCP endpoint over standard streams, modern and legacy protocol revisions |
| `AgentHelperMethod.swift` | The MCP methods the endpoint hears and how it answers each |
| `AgentAppLink.swift` | The socket link to the app, reconnected after Crest restarts |
| `AgentLinkResponse+AgentAppLink.swift` | Reading the app's answers off the link |
| `AgentLineChannel.swift` | Newline-delimited messages over one file descriptor |

## Depends on

`CrestAgents/`, which holds the protocol and tool definitions and is compiled
into the same `CrestBrowserHelper` target (`project.yml`). The `Crest` target
embeds the tool in `Contents/Helpers`; for the Chromium host the packager
copies it there (`project.yml`).

## Rules

- Keep the target arm64-native (`CONTRIBUTING.md`, "Validation").
- Test copies of Crest that the helper connects to are quit, unregistered and deleted before handing off (skill, "Verification and reporting").

## Read next

`CrestAgents/CONTEXT.md`, then `HelpCenter/docs/browsing/coding-agents.md`
for what the person sees.
