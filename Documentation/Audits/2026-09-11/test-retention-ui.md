# Manual UI review and test retention

The user confirmed that every change receives manual review of the affected UI and asked to remove automated checks for visual details that can freely change. This pass applies that standard across chrome, mobile navigation, sidebar/drag previews, settings, branding, extension presentation, split layout, command palettes and media artwork. The same rule is recorded in the local [repository instructions](../../../AGENTS.md).

**Removed 256 more test methods and 6,545 test lines, including six complete suites.** Across all three passes, the cleanup removes **439 methods net and 11,906 test/fixture lines**. These totals exclude concurrent favicon work. This pass changes tests, their project references, audit documentation and local test-retention guidance; application behavior is unchanged.

| Source | Additional methods removed | Retained declared methods, excluding concurrent favicon privacy file |
| --- | ---: | ---: |
| macOS/shared Swift | 217 | 2,696 |
| Mobile Swift | 39 | 363 |
| Python | 0 | 145 |
| Total | 256 | 3,204 |

The [inventory](test-inventory.csv) retains all 300 starting file rows and prior-stage counts, with `methods_after_ui_cleanup` and `ui_cleanup_disposition` recording the current state. The [UI removal ledger](test-removals-ui.md) names every removed method, its retired visual contract and the behavior coverage that remains. The [initial audit](test-retention.md) and [stricter retention follow-up](test-retention-followup.md) are historical records.

## Coverage now assigned to manual review

- Chrome/sidebar/card layout, safe areas, RTL placement, clipping, picker overflow, fixed dimensions, spacing, minimum hit-target sizes and Dynamic Type layout.
- Motion, opacity, transition phases, hover visibility, drag/drop previews and insertion indicators, compositor decoration synchronization, loading progress presentation and empty-page backdrops.
- Colors, contrast, artwork appearance, gradient texture, pinned-grid arrangements, extension menu icons, status/issue copy, settings catalog order and ordinary title formatting.
- The combined panel viewport/automatic-fit visual fixture. Actual requested zoom command routing, normalization and persistence remain tested separately; the exact panel-fit sequence is now manually reviewed.

The six retired suites are `BrowserFindBarMetricsTests`, `PinnedTabGridLayoutTests`, `BrowserSpaceForegroundPolicyTests`, `BrowserSettingsDestinationTests`, `BrowserExtensionSidebarSwitcherMenuModelTests`, and `BrowserSplitPanelViewportTests`. Their unused fixture code and project references were removed.

## Behavior coverage retained

UI-driven tests remain where their assertions protect a durable behavior: exact Space/profile/window ownership, late callbacks after replacement or relock, credential and permission boundaries, native key/mouse/gesture routing, accessibility actions and semantic state, persisted preferences and migrations, loaded-page form/scroll/history survival, actual extension routing and recovery, bounded resource work and one-time durable commits. Image decoding, hostile input bounds, extension screenshot API results and background-thread artwork safety remain behavioral contracts, even though they involve images or views.

Mixed tests were narrowed as well. Peek retains keyboard behavior; border customization retains migration and local persistence; appearance changes retain document/host continuity; drag tests retain the resolved destination and cancellation/ownership without asserting preview pixels. No replacement tests were added for the retired visual details.

## Validation

- Selected macOS suites: **405 tests passed**, zero failures or skips; `TEST SUCCEEDED`.
- Retained mobile suite: **363 tests passed**, zero failures or skips; `TEST SUCCEEDED`.
- All **31 surviving Swift files** edited in this pass passed strict formatting. XcodeGen regenerated the project after file removals.
- `git diff --check` passed. The inventory and removal ledger were checked against actual retained method declarations, including the four behavior-focused renames.

Both Swift runs use `CREST_ISOLATED_SESSION=1`. The mobile run uses a dedicated iPhone 17 Pro simulator on iOS 27 and excludes the concurrent favicon privacy file. Exact commands, logs and result bundles are saved under `/tmp/crest-ui-test-cleanup` as `mac-command.json`, `mobile-command.json`, `mac.log`, `mobile.log`, and the corresponding `.xcresult` bundles.

Temporary cleanup/validation scripts and the dedicated simulator were removed after verification. The ignored local `AGENTS.md` was updated in place; this report also records the manual UI review standard in repository documentation.

The macOS run covers all surviving test classes in the files edited by this pass; it is not a rerun of every macOS test. Python sources were unchanged in this pass and were not rerun. The earlier standalone architecture-audit violations are still separate from these results. Retired visual details now rely on manual review; these removals do not establish that any underlying visual bug was fixed or that the whole suite is faster.
