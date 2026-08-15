# Content blocking

Crest’s Balanced protection compiles one bundled ruleset with WebKit’s native
content-rule-list API. Whether it is active remains an independent choice for
every Space.

## Built-in protection

The bundled rules block a deliberately small set of well-known third-party ad
and analytics hosts. They provide a useful privacy baseline without downloading
remote rule sources, parsing third-party filter syntax, or placing another
project’s converter inside Crest’s trusted update path.

The rules are ordinary WebKit JSON generated from
`BrowserContentBlockingRules`. Crest compiles them once, caches the resulting
`WKContentRuleList`, and applies that list to pages in Spaces where Balanced
protection is enabled. Turning protection on or off reloads the visible pages so
the change takes effect without altering another Space.

## Extensions provide broader blocking

Crest does not ship a downloadable filter-list catalog or accept custom
Adblock-style list URLs. People who want broader coverage, cosmetic filtering,
regional lists, or project-specific rules can install a compatible content
blocking extension. Extensions keep their own source, update, and licensing
decisions at the extension boundary instead of making Crest redistribute or
convert those lists.

This division is intentional:

- Crest owns a small, reviewable first-party baseline.
- Extensions own advanced blocking and user-selected list ecosystems.
- A failed extension cannot change Crest’s bundled rules or another Space’s
  extension state.

## Compatibility

Balanced protection can occasionally break a site because it blocks known
third-party hosts. The page and command menus let the person turn content
blocking off for the current Space. Installing an extension may add separate
site controls supplied by that extension.
