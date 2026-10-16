---
title: Let coding agents use Crest
description: Let coding agents on your Mac read and act on tabs in the Spaces you choose, through the Model Context Protocol server Crest includes.
slug: /coding-agents
keywords: [agents, AI, MCP, Model Context Protocol, coding agents, Claude Code, Codex, automation]
---

# Let coding agents use Crest

On Mac, coding agents you run, such as Claude Code or Codex, can use Crest as their browser: list and open tabs, read pages, click and type, take screenshots, and read a page's console and network requests. They work in the Spaces you choose, with the sites you're already signed in to there.

Agents are off until you turn them on.

## Turn on agents

1. Open **Settings > Agents**.
2. Turn on **Allow agents to use Crest**.
3. Under **Spaces**, turn on each Space agents may use.
4. Under **Connect an Agent**, choose **Copy Setup** for your agent, and paste it in your agent's terminal or settings.

Crest must be open while a tool works. Only explicit window or show-tab commands may open a window at your request.

## Allow an agent

The first time an agent uses Crest, Crest asks whether to allow it. The question names the program macOS verified by its code signature, not the name the agent gives itself. Crest remembers your answer and lists the agent under **Allowed agents**. Choose **Forget** to disconnect it; Crest asks again the next time it connects.

When the program is a general interpreter, such as node or python, allowing it covers any program it runs under the same agent name.

## See what agents do

- Each tab an agent uses shows the agent's badge and an outline in its colour, and the page shows a bar naming the agent.
- Choose **Stop** in that bar, or **Stop Agent in This Tab** from the badge, to keep the agent out of that tab, through any of its connections, until Crest quits or you forget the agent.
- **Settings > Agents** lists the agents connected now. Choose **Disconnect** to end one's connection.
- Turning agents off disconnects every agent.

## What agents can reach

- Only the Spaces you turned on. A locked Space shows agents its name and nothing in it.
- Private tabs remain inaccessible, including when a tool opens a Private Window for you. Never Crest's own pages, such as Settings, a browser or extension page, or a file.
- Only `http` and `https` pages, and blank ones.
- Not your saved passwords. A password field's value is left out of what agents read, cookies and sign-in headers are hidden in the requests they read, and request and response bodies are never shown.
- Scripts in a page's own world only when you turn on **Let agents run scripts in pages**. A script runs with the page's own access, so it can read anything the page holds, including a password filled in on it.

Any program that runs as you on your Mac can run an agent you allowed. Crest's question tells agents apart so you can see and control them; it is not a defense against harmful software already on your Mac. Allow only agents you trust, and turn agents off when you don't need them.

## For agent authors

Crest includes a Model Context Protocol server as a helper inside the app, which an agent runs over its standard input and output:

```text
/Applications/Crest.app/Contents/Helpers/crest-browser mcp
```

It speaks protocol version 2026-07-28 and the earlier versions that open with `initialize`. Call `identify` first with your name and brand colour as `#RRGGBB`, so the person sees which tabs you use. Then use `list_spaces` and `list_tabs`, and read pages with `take_snapshot`, whose element `uid`s `click`, `hover`, `fill` and `scroll` take. The other tools are `open_tab`, `navigate`, `show_tab`, `close_tab`, `screenshot`, `type_text`, `press_key`, `wait_for`, `list_console_messages`, `list_network_requests`, `get_network_request` and `evaluate_script`.

When a page runs on WebKit, input reaches it as script events, which some pages ignore, and its network requests show their address, type and timing without their method, status or headers.

## Browser launchers and search tools

Local tools such as Raycast use the same bundled MCP helper, approval and Space permissions. No extension bridge or direct socket access is needed.

- `list_spaces` includes the active state and native artwork of unlocked Spaces. Locked Spaces expose only their identity, name and locked status.
- `list_tabs` includes pinned/saved placement and folder breadcrumbs. `show_tab` activates the original tab and opens a normal window over its Space only if needed. `close_tab` archives an ordinary open tab or puts a saved/pinned page away while preserving its sidebar entry and close-policy behavior. It respects native page confirmation; `closed` reports completion, `tabPreserved` reports whether the entry remains, and `note` explains an incomplete close. `navigate` can reload a tab by identity.
- `search_history` reads live core history across allowed, unlocked Spaces. Optional `query` words must all match the title or address. Optional `domain` matches a hostname and its subdomains; Google Maps also matches Google's `/maps` pages. Filtering happens before the globally newest results are limited. `limit` defaults to 25 and accepts 1 through 1000. Visits include an ISO timestamp and `lastVisitTime` in Unix milliseconds.
- `list_search_providers` returns enabled Crest providers, shortcuts and resolved URL templates, including provider options, and the selected Space's default. Optional `space` must name an allowed, unlocked Space; otherwise the active allowed Space or first unlocked Space is used.
- `delete_history` takes required `space` and `url`. At your explicit request it removes every visit to that HTTP(S) address from the specified allowed, unlocked Space, ignoring URL fragments. The receipt identifies the Space and reports `removed`; repeating the request reports zero. It cannot clear all history, reach another unapproved Space, or delete private history.
- `open_window` takes optional `space` and `url`; `open_blank_window` takes optional `space`; `open_quick_window` takes required `url` and optional `space`. URLs must be HTTP or HTTPS and are validated before any window opens.
- `open_private_window` takes optional `url` and returns only a `windowID` creation receipt. No tool can list or act on that window or its tabs afterward. Private visits never appear in history results.

Opening a window requires the person's request. A refused operation remains an error; launchers should never replace saved-tab activation with a duplicate URL or replace Quick or Private Windows with normal windows.
