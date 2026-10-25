# GitHub live folders

On macOS with WebKit, signing into github.com lets the selected, unlocked Space
create a GitHub saved folder. No pinned GitHub tab, loaded page, token, or separate
account is required. Private workspaces do not run integrations.

Space actions → Live Folder → GitHub also adds the folder or restores it after
deletion. Deleting the live folder archives its tabs and dismisses automatic
creation in that Space. Ordinary folder deletion keeps its existing behavior.

The folder menu offers Refresh, Created by Me, Assigned to Me, Review Requests,
Include Drafts, repository exclusions, and refresh intervals from 15 minutes to
8 hours. Created by Me and Assigned to Me start enabled, drafts are included,
and the default interval is 30 minutes. Related queries are combined and capped
at 100 unique results; this is a dashboard collection rather than a complete
GitHub search client. Organization SSO still needs renewal on GitHub when it
expires. Connect GitHub opens a new tab without replacing a pull request.

CrestCore owns folder identity, options, tab reconciliation, dismissal, persistence,
and sync. Refresh keeps tab IDs, personal names, and navigation; expired unchanged
entries are archived. Personally navigated entries move out of the managed folder.
Persisted folders and tabs are visible on mobile, but collection refresh currently
runs only on macOS.

The collector consumes a reusable engine session interface. The core resolves the
engine using the same default and site rules as new user navigations. Unsupported
engines, including Chromium, show an unavailable state and never borrow WebKit
cookies. WebKit supplies only the matching profile store to an ephemeral,
origin-bound session with no shared cookie jar, credential storage, or cache.
Response cookies are never written to the browser. Requests do not follow
redirects or answer authentication challenges. Cookie changes, logout, profile
changes, Space locks, deletion, and engine changes invalidate in-flight work;
results recheck authorization and filters before publication.

The GitHub dashboard supports its JSON response and legacy HTML without executing
scripts or creating a web view. These website formats can change independently of
Crest. The query and dashboard extraction approach is adapted from Zen; attribution
and its MPL 2.0 notice ship with the app.
