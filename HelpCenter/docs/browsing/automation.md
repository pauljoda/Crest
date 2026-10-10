---
title: Control Crest from scripts and coding agents
description: Let command-line tools and coding agents on your Mac open, list, show and close tabs in the Spaces you choose, and read the protocol they use.
slug: /automation
keywords: [automation, scripts, coding agents, AI, Claude Code, Codex, command line, CLI, socket, JSON-RPC]
---

# Control Crest from scripts and coding agents

On Mac, a tool you run on your computer, such as a script or a coding agent in a terminal, can work with Crest's tabs: list them, open a website in a tab, bring a tab forward, and close it. It works in the Spaces you choose and with the websites you are already signed in to there.

Automation is off until you turn it on.

## Turn on automation

1. Open **Settings > Automation**.
2. Turn on **Allow tools to control Crest**.
3. Under **Spaces**, turn on each Space tools may use.

The first time a tool connects, Crest asks whether to allow it. Choose **Allow** only for tools you trust. Crest remembers your answer for that tool, and lists it under **Allowed tools**. Choose **Forget** to disconnect it; Crest asks again the next time it connects.

Turning automation off disconnects every tool.

## What tools can reach

- Only the Spaces you turned on. A tool sees the name of a locked Space, and nothing in it until you unlock it.
- Never a private window or a temporary window.
- Only websites over `http` and `https`. A tool can't open Crest's own pages or other kinds of links.
- A tool can close an open tab, after the page agrees to go, but never a pinned or saved tab.
- A tool works in the windows you have open and never opens a window of its own.

Any program that runs as you on your Mac can connect, and the approval is for a program at a particular location. Allow only tools you trust, and turn automation off when you don't need it.

## For tool authors

Crest listens on a Unix domain socket while automation is on:

```text
~/Library/Application Support/Crest/Automation.sock
```

**Settings > Automation** shows the exact path and copies it. Only your own user can connect. Each message is one JSON-RPC 2.0 object on its own line, in both directions. Give each request an `id`, a whole number or a string, which its answer repeats. Crest answers a connection's requests in the order it sends them.

### Hello

Send `hello` first. Crest checks the protocol version and asks the person to allow the tool when it is new, so the answer can take a while.

```json
{"jsonrpc":"2.0","id":1,"method":"hello","params":{"protocol":1,"client":{"name":"crest","version":"0.1.0"}}}
```

```json
{"id":1,"jsonrpc":"2.0","result":{"crest":{"version":"0.7.25"},"methods":["spaces.list","tabs.list","tabs.open","tabs.close","tabs.show"],"protocol":1}}
```

Crest identifies a tool by `client.name` and the program that connected. Ship your tool as its own executable; a script run by a general interpreter is identified as the interpreter.

### Methods

| Method | Parameters | Result |
| --- | --- | --- |
| `spaces.list` | none | `spaces`: each with `id`, `name` and `locked` |
| `tabs.list` | `space` (optional) | `tabs`: every tab of the reachable, unlocked Spaces, or of `space`, in sidebar order |
| `tabs.open` | `space`, `url`, `show` (optional, false) | `tab`: the new tab, after the tab the Space shows. With `show`, it comes forward in the front window over the Space, when one is open |
| `tabs.show` | `tab` | `tab`: brought forward in the front window over its Space |
| `tabs.close` | `tab` | `closed`: true when the tab closed, false when its page asked you before leaving and is still open. It closes if you agree |

A tab has `id`, `space`, `title`, `url` (absent for a tab that shows no website), `placement` (`pinned`, `saved` or `current`) and `shown`, which says whether a window shows it now. Identities are the ones Crest gives.

### Errors

A refused request answers a JSON-RPC error. `error.data.reason` says why and never changes:

| Reason | Meaning |
| --- | --- |
| `parse-error`, `invalid-request`, `invalid-params`, `method-not-found` | The request itself is wrong |
| `unsupported-protocol` | Crest speaks another protocol version |
| `hello-required` | Send `hello` first |
| `declined` | The person didn't allow the tool; Crest closes the connection |
| `not-approved` | The person has since forgotten the tool |
| `automation-off` | Automation is turned off |
| `space-unavailable`, `tab-unavailable` | The Space or tab is not one tools may reach |
| `space-locked` | The Space is locked; ask the person to unlock it |
| `unsupported-address` | The address is not `http` or `https` |
| `no-window` | No window shows the Space |
| `refused` | Crest could not do it; `error.message` says why |
