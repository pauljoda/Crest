---
title: Route links to the right Space
description: Build Air Traffic Control-style URL rules that send links to a chosen Crest Space.
slug: /link-routing
keywords: [link routing, Air Traffic Control, URL rules, external links, page links, Space]
---

# Route links to the right Space

Link Routing is Crest’s equivalent of Arc’s Air Traffic Control: a matching link opened from another app goes to a specific Space before the normal external-link destination is considered, and a matching link you follow on a page opens as a new tab in that Space. The page you followed it from stays where it is. A link loads as usual when it stays on the site you are already on, when the first matching route names the Space you are in or a Space that cannot take another tab, or when you open it with the Peek modifier.

Routing applies to links you follow in a tab. Links in Peek, a Quick Window or a private window load as usual, a window a page opens by script, such as a sign-in popup, stays with the page that opened it, and an address typed into the address bar opens in the Space you are in.

## Create a route

1. Open **Settings → Links**.
2. In **Routing**, choose **New Route**.
3. Enter a URL pattern.
4. Choose **Contains** or **Exact**.
5. Choose the destination Space.

Routes are evaluated from top to bottom. Reorder them when a narrow rule should win before a broad one.

## Match deliberately

- **Exact** is best for one complete address that should always land in one Space.
- **Contains** is useful for a domain or stable path fragment, but a pattern that is too broad may catch unrelated links.

Start with the smallest meaningful domain or URL fragment, test a link from another app, then broaden only if needed.

## Relationship to Quick Window

Routing runs before the default **Links from other apps** choice. If no rule matches, Crest uses Quick Window, Most Recent Space, or the Chosen Space according to that default.

A route targeting a protected Private Space is hidden until that Space is unlocked. This prevents its URL patterns and destination identity from leaking through Settings. While that Space is locked, a link from another app opens in a Quick Window on the Space you are in, and a link on a page loads in place; neither unlocks the Space.

