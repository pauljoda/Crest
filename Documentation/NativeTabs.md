# Native tab content

A native tab is a `BrowserTab` with a `BrowserNativeTabContent` descriptor. It uses the existing session, Space/profile assignment, Saved and Current placement, folders, split group membership, selection, archive, duplication, and persistence paths. It does not have a website URL or a second tab collection.

`BrowserNativeTabHost` resolves the descriptor into a SwiftUI view inside the same card surface used by single pages and Split View. Layout and focus remain owned by the surrounding browser. The host receives a captured tab/Space/profile assignment. Outbound links pass through `BrowserNativeTabActions`, which checks that assignment, the current descriptor, and access to the Space before opening a website in a new tab.

The Mac and mobile page stores recognize native selection without allocating a `WKWebView`, including mixed native/website splits, extension preparation, and session reconciliation. Only website members receive pages. Assigning a website URL to a native tab explicitly converts that tab into a website. Unloading a Saved native view dismisses its presentation and retains the tab. The sidebar uses a minus control for Saved and a close control for Current. Deleting a Saved tab, or closing a Current copy, uses normal tab lifecycle rules.

## Adding a content type

1. Give it a stable `kind` string and register its view in `BrowserNativeTabHost`.
2. For content with its own data, use `resourceID` to address a document store scoped to the owning Space/profile. Keep document data and its lifecycle out of the tab descriptor. A duplicate tab currently points to the same resource; cloning a document should be an explicit action.
3. Use the existing layout's assignment and selection. Do not introduce a page pool, browser controller, or global selected-tab lookup inside the content view.
4. Add only the capabilities the content needs to the native action port, with assignment and access checks at the boundary.
5. Cover persistence, unknown-kind round trips, native-only and mixed-split presentation, and stale-assignment rejection.

Notes and Widgets are not implemented by this change. The descriptor and host provide their integration point; document persistence, per-content state restoration, and platform availability belong to each future content type.

## Compatibility

The optional descriptor preserves decoding of existing website and Start Page tabs. Unknown kinds retain their descriptor and show an unavailable-content view. Cloud tab and archive records containing native content require schema 3; ordinary records retain their lower schema requirements. Existing newer-schema write-base protection prevents an older client from replacing a native record with an incomplete projection. Portable archives use schema 5 and retain descriptors through export/import.

## Getting Started

Both shells render native guides. Mac teaches tabs, Split View, and extensions; mobile has one touch-oriented page for pinned, saved, and open tabs plus folders. The practice store, artwork, and actual sidebar rows are shared. Setup and mobile Settings use the same adaptive appearance workspace; phones show a compact preview above the choices, while tablets can place the sidebar on the left.

Automatic presentation is an install-local completion action. `completeSetup(for:)` reads and consumes the persisted completion record before either shell opens a Saved guide. Repeated completion callbacks, forced welcome/setup, manual replay, and later launches cannot reopen it automatically. Explicit Help actions remain available. Named isolated review sessions persist the same completion decision in their own defaults suite.

The practice window has its own store family and in-memory session, credentials, and site permissions. It reuses the real sidebar rows, pinned grid, folder tree, drag/drop paths, and split columns. Website examples are SwiftUI documents with bundled logos, and never load their URLs. Practice edits cannot reach the person's browser session. The guide's chapter and exercise state are local to its current SwiftUI presentation.

The same practice window changes its frame and position between the sidebar lesson and the full Split View lesson. Reduce Motion removes this transition. Split instructions are rendered inside the practice cards.
