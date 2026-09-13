# Native tab content

A native tab is a `BrowserTab` with a `BrowserNativeTabContent` descriptor. It uses the existing session, Space/profile assignment, Saved and Current placement, folders, split group membership, selection, archive, duplication, and persistence paths. It does not have a website URL or a second tab collection.

`BrowserNativeTabHost` resolves the descriptor into a SwiftUI view inside the same card surface used by single pages and Split View. Layout and focus remain owned by the surrounding browser. The host receives a captured tab/Space/profile assignment. Outbound links pass through `BrowserNativeTabActions`, which checks that assignment, the current descriptor, and access to the Space before opening a website in a new tab.

The Mac and mobile page stores recognize native selection without allocating a `WKWebView`, including mixed native/website splits, extension preparation, and session reconciliation. Only website members receive pages. Assigning a website URL to a native tab explicitly converts that tab into a website. Unloading a Saved native view dismisses its presentation and retains the tab. The sidebar uses a minus control for Saved and a close control for Current. Deleting a Saved tab, or closing a Current copy, uses normal tab lifecycle rules.

## Loaded state

Each window's page store owns a `BrowserNativeTabStore`. Presenting a native card loads a runtime identified by its tab, Space, profile, and complete content descriptor. The runtime owns typed content models, independent of whether SwiftUI currently mounts the card. Switching tabs or Spaces preserves those models; it does not retain hidden view hierarchies or add another presentation layer.

Explicit unload, tab removal, assignment or descriptor replacement, and window runtime teardown end that lifetime. Memory pressure may unload an offscreen native runtime under the platform's existing release limits. Presented native cards are excluded. Locking a Space preserves its loaded state behind the existing access boundary. Runtime state stays in memory and is neither synchronized nor written into session archives.

Content chooses what belongs in its model: navigation, practice edits, filters, and scroll positions can survive remounting. Focus, active gestures, authorization, and confirmation dialogs belong to the current presentation. A model must not retain a hosting controller, running task, or callback that keeps an inactive view operating. Persistent document data belongs in its own Space/profile store and outlives this runtime only according to that store's policy.

Settings activation follows the host layout: Mac and regular-width mobile windows open the native Settings page in the browsing canvas. Compact mobile layouts present a sheet while retaining the browsing selection. An unfocused Settings split card uses the same routing, validated against its captured tab, Space and profile. In compact layouts, a restored or synchronized selected Settings descriptor presents the sheet and uses the normal native-tab dismissal fallback while retaining the tab. Switching the active Space from embedded Settings also validates the owning Settings tab and destination access before opening or reusing Settings there.

## Adding a content type

1. Give it a stable `kind` string and register its view in `BrowserNativeTabHost`.
2. For content with its own data, use `resourceID` to address a document store scoped to the owning Space/profile. Keep document data and its lifecycle out of the tab descriptor. A duplicate tab currently points to the same resource; cloning a document should be an explicit action.
3. Use the existing layout's assignment and selection. Obtain a typed content model from the host's loaded runtime and pass it to the view. Do not introduce a page pool, browser controller, or global selected-tab lookup inside the content view.
4. Add only the capabilities the content needs to the native action port, with assignment and access checks at the boundary.
5. Cover persistence, unknown-kind round trips, native-only and mixed-split presentation, stale-assignment rejection, and release of runtime state when its loaded lifetime ends. Review visible state restoration through the real interface.

Notes and Widgets are not implemented by this change. The descriptor and host provide their integration point; document persistence, per-content state restoration, and platform availability belong to each future content type.

## Compatibility

The optional descriptor preserves decoding of existing website and Start Page tabs. Unknown kinds retain their descriptor and show an unavailable-content view. Cloud tab and archive records containing native content require schema 3; ordinary records retain their lower schema requirements. Existing newer-schema write-base protection prevents an older client from replacing a native record with an incomplete projection. Portable archives use schema 5 and retain descriptors through export/import.

## Getting Started

Both shells render native guides. Mac teaches tabs, Split View, and extensions; mobile has one touch-oriented page for pinned, saved, and open tabs plus folders. The practice store, artwork, and actual sidebar rows are shared. Setup and mobile Settings use the same adaptive appearance workspace; phones show a compact preview above the choices, while tablets can place the sidebar on the left.

Initial setup opens or reuses a Saved guide in the first ordered normal Space. `BrowserOnboardingCompletion` authorizes that Space and revalidates its identity after authentication before committing a pending manual plan or opening the guide. A cancelled or stale request leaves setup unfinished. The host prepares the guide before the install-local completion record retires the launch gate, so the normal startup preference cannot replace it.

Later launches and repeated first-run completion callbacks do not reopen the guide automatically. **Rerun onboarding** in Advanced settings explicitly starts at Welcome and opens the guide again on completion, without clearing the persisted completion record. Explicit Help actions remain available. Named isolated review sessions keep the completion decision in their own defaults suite.

The practice window has its own store family and in-memory session, credentials, and site permissions. It reuses the real sidebar rows, pinned grid, folder tree, drag/drop paths, and split columns. Website examples are SwiftUI documents with bundled logos, and never load their URLs. Practice edits cannot reach the person's browser session. The guide's chapter, exercise state, scroll positions, and practice split widths belong to its loaded native runtime.

The same practice window changes its frame and position between the sidebar lesson and the full Split View lesson. Reduce Motion removes this transition. Split instructions are rendered inside the practice cards.
