"""The shell every page the product site generates at deploy time shares.

The release notes and the credits are written by scripts rather than by hand.
Each of their pages takes its head, header and footer from here, so they keep
the hand-written pages' navigation, links and stylesheet.
"""

from __future__ import annotations

import html
from typing import Optional


SITE_URL = "https://crestbrowser.com"
SITE_STYLESHEET = "/styles.css?v=20261119-allo-1"
BANNER_PATH = "M4 5.4Q4 2 7.4 2L24.6 2Q28 2 28 5.4L28 30.6Q28 34 25.06 32.29L18.94 28.71Q16 27 13.06 28.71L6.94 32.29Q4 34 4 30.6Z"


def icon(paths: str, *, filled: bool = False) -> str:
    """A 24-point glyph drawn in the text color: stroked, or `filled`."""
    style = (
        'fill="currentColor"'
        if filled
        else 'fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"'
    )
    return f'<svg viewBox="0 0 24 24" {style} aria-hidden="true">{paths}</svg>'


def banner(color: str, css_class: str) -> str:
    """The Crest banner in `color`, the shape every channel and tier wears."""
    return f'<svg class="{css_class}" viewBox="0 0 32 36" aria-hidden="true"><path d="{BANNER_PATH}" fill="{color}"/></svg>'


def head_html(
    title: str, description: str, canonical: str, *, stylesheet: str, json_path: Optional[str] = None
) -> str:
    """The document head of the page at `canonical`, with the site's
    stylesheet, then the page's own, and its JSON beside it when it has one."""
    alternate = f'\n  <link rel="alternate" type="application/json" href="{json_path}">' if json_path else ""
    title_text = html.escape(title)
    description_text = html.escape(description)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="theme-color" content="#FBF5E6">
  <meta name="color-scheme" content="light">
  <meta name="description" content="{description_text}">
  <link rel="canonical" href="{SITE_URL}{canonical}">
  <meta property="og:site_name" content="Crest">
  <meta property="og:locale" content="en_US">
  <meta property="og:type" content="article">
  <meta property="og:url" content="{SITE_URL}{canonical}">
  <meta property="og:title" content="{title_text}">
  <meta property="og:description" content="{description_text}">
  <meta property="og:image" content="{SITE_URL}/assets/og-card.jpg">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{title_text}">
  <meta name="twitter:description" content="{description_text}">
  <meta name="twitter:image" content="{SITE_URL}/assets/og-card.jpg">
  <title>{title_text}</title>
  <link rel="icon" href="/favicon.ico" sizes="48x48">
  <link rel="icon" type="image/svg+xml" href="/assets/crest-favicon.svg">
  <link rel="icon" type="image/png" sizes="32x32" href="/assets/crest-icon-32.png">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
  <link rel="manifest" href="/site.webmanifest">
  <link rel="stylesheet" href="{SITE_STYLESHEET}">
  <link rel="stylesheet" href="{stylesheet}">{alternate}
</head>"""


def header_html(*, body_class: str, main_id: str, skip_label: str) -> str:
    """The page's body opening: the skip link to `main_id`, and the site's header."""
    return f"""<body class="{body_class}">
  <a class="skip-link" href="#{main_id}">{html.escape(skip_label)}</a>
  <header class="site-header">
    <a class="brand" href="/"><img src="/assets/crest-logo.svg" alt="" width="38" height="38">Crest</a>
    <span class="spacer"></span>
    <nav class="site-nav" aria-label="Site">
      <a class="nav-section" href="/#spaces">Spaces</a>
      <a class="nav-section" href="/#studio">Studio</a>
      <a class="nav-section" href="/#privacy">Privacy</a>
      <a href="/guides/">Guides</a>
      <a class="button button-primary button-small" href="/#get">Download</a>
    </nav>
  </header>
"""


FOOTER = """
  <div class="page-footer">
    <footer class="site-footer">
      <p>Crest is in early access, and its security has not been independently audited.</p>
      <nav aria-label="Footer">
        <a href="/guides/">Guides</a>
        <a href="/docs/">Field guide</a>
        <a href="/support/">Support</a>
        <a href="/releases/">Release notes</a>
        <a href="/credits/">Credits</a>
        <a href="/privacy/">Privacy</a>
        <a href="/press/">Press kit</a>
        <a href="https://github.com/crest-browser/Crest">GitHub</a>
        <a href="https://www.reddit.com/r/CrestBrowser">Reddit</a>
        <a href="https://discord.gg/gjrM5qMB6x">Discord</a>
        <a href="https://ko-fi.com/pauljoda/tiers">Donate</a>
      </nav>
    </footer>
  </div>
</body>
</html>
"""
