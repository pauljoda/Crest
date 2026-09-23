---
title: Translate, read, and use page tools
description: Translate webpages on device, use Reader, find text, adjust zoom, share, and export pages.
slug: /page-tools
keywords: [translate, translation, languages, Reader, find, zoom, share, Markdown, PDF, web archive, print, reload]
---

# Translate, read, and use page tools

Page actions operate on the focused page. In Split View, click or tap a card first so the intended page owns the command.

Crest for Mac runs on one of two engines. Experimental builds use Chromium by default and offer a WebKit build as an alternate. Other Mac builds, and Crest on iPhone and iPad, use WebKit. A few page tools depend on the engine, and this page notes where.

## Translate a page

Translate webpages on device using Apple’s Translation framework. Whole-page translation works on iPhone, iPad, and the WebKit build for Mac. In the Chromium build, select text on the page and translate the selection from the page's context menu; it uses the same on-device translation.

In the WebKit build for Mac, open the translation toolbar with **Shift-Command-L**. On iPhone and iPad, tap the address bar’s translation button for options, or touch and hold it to translate immediately.

Choose **Detect Language** or a source language, pick a target language, then translate. **Show Original** restores the page’s original text. Language availability depends on Apple’s support; Apple asks before downloading a language that is needed.

**Automatically Translate** is off by default. When enabled, Crest uses your preferred device language and languages already downloaded. Showing the original keeps that page untranslated until you navigate or reload.

Downloaded language packs are shared with other apps and remain on the device after Private Browsing ends.

## Read and search

- **Reader** converts a supported article into a focused reading surface. Use the page controls, menu, command palette, or assign a shortcut. Reader is not available in the Chromium build.
- **Find in Page** uses **Command-F**. Step through matches and close Find when finished. The Chromium build shows how many matches the page has and which one is selected; WebKit shows whether a match exists.
- **Zoom In**, **Zoom Out**, and **Actual Size** use **Command-+**, **Command--**, and **Command-0**.

Set a default zoom for pages in **Settings → Look and Feel**, from **25% to 500%**.

## Video and audio

Use the sidebar’s Now Playing controls for eligible active media. On Mac, supported videos can open in **Picture in Picture**, with an optional automatic PiP setting. Availability depends on the website and its player.

## Copy and share

- **Copy Page Link** uses **Shift-Command-C**.
- **Copy Page Link as Markdown** uses **Option-Shift-Command-C** and produces a title-and-URL link suitable for notes or issue trackers.
- **Share Page** opens the platform share sheet when available.

## Export

- **Print Page** uses **Command-P**.
- **Export as PDF** writes a portable rendered document.
- **Save Web Archive** saves the whole page in one file. The WebKit build writes a `.webarchive` file, and the Chromium build writes an `.mhtml` file.

Each build opens only its own archive format with **File → Open File…**. The Chromium build cannot open a `.webarchive`, and the WebKit build cannot open an `.mhtml` file.

Export and Share are available through menus and the command palette even when no default shortcut is assigned.

## Reload choices

**Command-R** performs a normal reload. **Shift-Command-R** reloads from the origin when a cached response is not what you need. **Command-.** stops the current load.

## Content and site controls

The contextual site controls also expose Reader and content blocking where the engine offers them, permissions, extension actions, and developer status. In the Chromium build, blocking ads and trackers comes from the extensions you install. Decisions for camera, microphone, automatic downloads, popups, or external-app handoff are remembered within the current Space.
