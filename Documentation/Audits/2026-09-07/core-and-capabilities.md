# Shared core, capability-driven UI, and consolidation audit

Audited revision: `457ac1d2`. This source review evaluates durable ownership and shared behavior against [ARCHITECTURE.md](../../../Documentation/ARCHITECTURE.md) and [RepositoryGuardrails.md](../../../Documentation/RepositoryGuardrails.md). Priorities describe maintainability investment. See [validation](validation.md) for executed checks and [implementation plan](implementation-plan.md) for the final work order.

## Assessment

Crest has a credible shared-first architecture and does not need a rewrite. Space/tab organization, identity, deletion, sync values, access decisions, and many workflow controllers already live in shared Domain/Application. The sidebar is now genuinely shared composition with explicit shell actions and interaction capabilities. The next meaningful improvements are to finish sharing runtime lifecycle orchestration and command semantics, then make the intended inward dependency direction real rather than merely an import convention.

The goal of keeping the bulk of behavior in the core is substantially met for durable session behavior and common sidebar presentation, partially met for WebKit page lifecycle and command workflows. Keeping AppKit/UIKit delegates, window mechanics, touch recognizers, and scene presentation separate is appropriate. Large platform owners are a navigation signal, not evidence by themselves that they should be split.

## Source inventory

Counts are `.swift` file counts and raw source lines, including comments/blank lines; all counts exclude tests and resources outside Swift.

| Area | Files | Raw lines |
| --- | ---: | ---: |
| CrestShared | 1,446 | 134,179 |
| Shared Domain | 249 | 18,700 |
| Shared Application | 119 | 10,658 |
| Shared Infrastructure | 266 | 23,402 |
| Shared Features | 734 | 78,069 |
| Shared DesignSystem | 77 | 3,338 |
| CrestMac | 579 | 62,680 |
| Mac Features | 430 | 39,744 |
| Mac Infrastructure | 136 | 21,753 |
| CrestMobile | 262 | 20,707 |
| Mobile Features | 212 | 14,126 |
| Mobile Infrastructure | 39 | 5,600 |
| Total production Swift | 2,287 | 217,566 |

Shared sources are 61.7% of raw lines. [BrowserTabEmojiChoices.swift](../../../CrestShared/Features/Sidebar/Components/BrowserTabOrganizationMenu/Support/BrowserTabEmojiChoices.swift) alone is a 27,625-line catalog; excluding that catalog gives 56.1% shared. Neither ratio is a percentage of business behavior or a quality target. Likewise the 7,481-line macOS extension package preparer contains substantial embedded compatibility content and should not be judged by raw file length.

## Prioritized findings

### C1 — High priority: common page-runtime lifecycle orchestration still has two production owners

Evidence:

- [BrowserPagePool.swift:974](../../../CrestMac/Infrastructure/WebKit/BrowserPagePool.swift#L974) and [MobileBrowserPageStore.swift:670](../../../CrestMobile/Infrastructure/WebKit/MobileBrowserPageStore.swift#L670) independently build the same tab/runtime/archived-assignment maps, discard stale copy state, determine invalid resident pages, archive closing tabs before releasing their pages, update navigation context, and prune archived state. The inspected implementations differ primarily in the page dictionary name and the macOS extension reconciliation hook.
- The archive-pruning implementation at macOS `BrowserPagePool.swift:1068` and mobile `MobileBrowserPageStore.swift:1631` is textually identical, including membership-change suppression of disk sweeps.
- Archive restoration at macOS `BrowserPagePool.swift:1117` and mobile `MobileBrowserPageStore.swift:1650` is textually identical: pending-copy consumption, URL matching, envelope decoding, restorable checks, and the return of WebKit interaction state.
- Content-blocking reconciliation at macOS `BrowserPagePool.swift:878` and mobile `MobileBrowserPageStore.swift:321` repeats the changed-policy detection, presented-page immediate reload decision, and background/Peek next-navigation treatment. macOS additionally visits suspended pages; that distinction belongs at the runtime edge. The changed-policy helper at macOS `:927` and mobile `:366` is identical.

Why it matters: adding a restore rule, changing archive retention, or refining a protection-level transition requires coordinated edits in both runtime implementations. These are costly state and lifecycle contracts with the same intended outcome across platforms. The issue is change amplification and future drift, not a demonstrated regression. The 2,591-line macOS pool and 1,757-line mobile store are useful pointers to this concentration, but the duplicated algorithms are the reason to act.

Recommended scope: first extract a concrete shared tab-state lifecycle owner for pending copies, archive restore/prune bookkeeping, and the shared reconciliation plan. Keep WebKit interaction-state capture and platform page release as supplied operations. Next extract content-blocking reconciliation into a shared coordinator/policy over resident/presented/transient page inputs. Retain macOS suspended-card behavior and actual page/window hosts explicitly; avoid starting with a universal cross-platform page superclass or moving entire platform files unchanged.

Validation: reuse [BrowserPagePoolTests.swift](../../../CrestTests/BrowserPagePoolTests.swift), [MobileBrowserPageStoreTests.swift](../../../CrestMobileTests/MobileBrowserPageStoreTests.swift), and existing content-blocking coverage. Exercise archived back-forward-stack restoration, duplicate-copy state consumption, profile/Space reassignment, private-mode archive suppression, protection change versus background list refresh, and multiple presented split cards. Keep platform integration coverage for release/ownership differences and place common transition assertions with the shared owner. There is no need for file-path/topology tests.

Counterevidence: residency, restore eligibility, presentation, and content-blocking value policies are already shared; the platform runtime owners correctly preserve real differences including suspended desktop pages and iOS navigation presentation. This is completion of an existing architecture, not a redesign.

### C2 — High priority: inward dependencies are not fully reflected in ownership

Evidence:

- [BrowserStore.swift:16](../../../CrestShared/Application/BrowserStore/BrowserStore.swift#L16) constructs and owns `BrowserTabDragState`, `BrowserFolderDragState`, and `BrowserSidebarReorderState`, all declared under `Features/Sidebar/...`.
- [BrowserSidebarReorderState.swift:15](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarDrag/Services/BrowserSidebarReorderState.swift#L15) holds pointer coordinates, measured row geometry, landing previews, and animation/registration lifecycle. These are presentation responsibilities, not persistent browser-session responsibilities.
- [BrowserStore+TabOrganization.swift:70](../../../CrestShared/Application/BrowserStore/BrowserStore+TabOrganization.swift#L70) updates the drag state from a generic cross-Space tab movement. Application command inputs elsewhere also use `BrowserTabDragItem` and `BrowserFolderDragItem` declared in Features; shared tab mutations therefore know the mechanism that initiated them.
- [BrowserManualSetupSpaceDraft.swift:8](../../../CrestShared/Domain/BrowserManualSetup/Models/BrowserManualSetupSpaceDraft.swift#L8) stores `BrowserImportSpaceCustomization`, declared at [BrowserImportSpaceReview.swift:24](../../../CrestShared/Features/DataPortability/Models/BrowserImportSpaceReview.swift#L24).
- [BrowserManualSetupPlan.swift:34](../../../CrestShared/Domain/BrowserManualSetup/BrowserManualSetupPlan.swift#L34) uses `BrowserPortableArchive.maximumSpaceCount`, whose type is declared at [BrowserPortableArchive.swift:3](../../../CrestShared/Features/DataPortability/Models/BrowserPortableArchive.swift#L3); the archive schema, materialization, and validation are domain/data-transfer behavior despite their Features placement.
- `project.yml:49`/`:105` compile the whole shared tree directly into each app target. The architecture gate’s `_import_violations` at [check-architecture.py:208](../../../Scripts/check-architecture.py#L208) enforces framework imports, so these references across folders do not violate that gate.

Why it matters: Domain/Application cannot currently be understood or compiled independently of parts of presentation and infrastructure. A future move toward independent core tests or a new shell will discover dependencies not visible in the architectural source map. Changing the sidebar’s interaction model reaches the application store; changing data-portability presentation folders can affect manual setup. A clean import check alone should not be reported as complete dependency isolation.

Recommended scope: give drag/reorder presentation state a window/sidebar feature owner; let shared tab mutations accept existing runtime assignments or other neutral movement values and return a result that the feature can use to reconcile its drag state. Move portable archive/customization values and materialization policies to the appropriate shared Domain/Application feature slice, keeping file reading/writing in Infrastructure and review UI in Features. Review the related `BrowserSyncCoordinator`/`BrowserBackgroundPageUpdate` placement opportunistically rather than adding interfaces mechanically. A separate core build target can follow after the real dependencies are cleaned up, if independent validation has a concrete payoff; it need not be the first change.

Validation: shared BrowserStore/session, manual-setup, portable-archive, multiwindow, and reorder workflow suites; build both app targets. For UI-state extraction validate dragging within and across Spaces, deleting a Space during a drag, and window-local drag independence. Do not add source-topology tests forbidden by the repository.

Counterevidence: Domain imports Foundation only, Application uses the modern Observation model, actual persistence/keychain/WebKit boundaries have injected collaborators, runtime IDs are typed, and many direct session mutations already delegate to shared policy/state transitions. Some findings here are mislocated neutral types rather than intrinsically poor coupling. Preserve that distinction while moving ownership.

### C3 — Medium priority: keyboard/menu/palette command semantics are duplicated beyond native menu glue

Evidence:

- [BrowserCommandActions.swift:325](../../../CrestMac/Features/Commands/Models/BrowserCommandActions.swift#L325) and [MobileBrowserCommandController.swift:88](../../../CrestMobile/Features/Commands/Models/MobileBrowserCommandController.swift#L88) both find the most recently archived tab, restore it, select it, and synchronize pages.
- macOS `BrowserCommandActions.swift:356` and mobile `MobileBrowserCommandController.swift:116` both implement most-recent-other-tab selection with a filter/max over activation timestamps.
- macOS `BrowserCommandActions.swift:419` and mobile `MobileBrowserCommandController.swift:196` both calculate wrapped split-card focus. Creating the next eligible split repeats at macOS `:397` and mobile `:210`.
- Command availability/registration is maintained separately in macOS `BrowserCommandActions.swift:31`, mobile `MobileBrowserCommandContext+Commands.swift:10`, the corresponding platform dispatcher switches, and both native `Commands` implementations. Native menu placement and window behavior differ legitimately, but the shared tab intent algorithms above do not.

Why it matters: a common browsing command is not yet one shared workflow. A change in what “reopen,” “most recent,” or “next split card” means must be made in multiple shells; adding a command requires keeping registry, dispatch, availability, and menu bindings synchronized. For an Arc-style product whose speed comes partly from consistent keyboard behavior, this is a meaningful maintenance cost even with a functioning app today.

Recommended scope: move the repeated tab intents into a small shared Application command owner or the existing BrowserStore feature extensions, returning IDs/results for platform presentation to consume. Keep distinct close-window behavior, iPad keyboard aliases, focus routing, export sheets, and menu placement in their shells. Reuse a shared supported-command descriptor/actions value for common availability and palette metadata when actual overlap justifies it; prefer optional native actions over adding a large “platform” switch or a new protocol for every command.

Validation: characterize reopen ordering, most-recent selection, split wraparound, pinned/current transitions, and selected/locked Space behavior once in the shared workflow. Retain macOS/iPad native command smoke checks and their focused context tests, including extra iPad keyboard aliases. Shared command results must still trigger the appropriate runtime reconciliation and compact-navigation presentation.

Counterevidence: command IDs, shortcut defaults/overrides/conflicts, numbered-selection policies, and palette presentation are already shared ([BrowserShortcutStore.swift](../../../CrestShared/Application/BrowserShortcuts/BrowserShortcutStore.swift), Domain `BrowserShortcuts`, and `Features/Chrome/.../BrowserCommandPaletteCommandRegistry.swift`). Both platforms have hardware keyboard commands. The absence of a `supportsKeyboard` boolean is not itself a deficiency; an input bit is warranted only when real UI policy depends on it.

### C4 — Lower priority: a small tail of interaction decisions still selects by compiled platform

Evidence:

- [BrowserSidebarWidgetModels.swift:200](../../../CrestShared/Application/SidebarWidgets/BrowserSidebarWidgetModels.swift#L200) chooses deck gesture axis through `currentPlatformAxis` with `#if os(iOS)`. Shared widget presentation consumes it at [BrowserSidebarWidgetHost.swift:492](../../../CrestShared/Features/SidebarWidgets/BrowserSidebarWidgetHost.swift#L492) and `:503`. A shared Application policy is therefore deciding a presentation gesture from platform identity.
- [BrowserSidebarTabActivationButton.swift:33](../../../CrestShared/Features/Sidebar/Components/BrowserSidebarTabRow/Components/BrowserSidebarTabActivationButton.swift#L33) attaches double-activation restoration only to the macOS build; [BrowserTabSavedLocationIndicator.swift:12](../../../CrestShared/Features/Sidebar/Components/BrowserTabSavedLocationIndicator.swift#L12) attaches restoration on the small indicator only for iOS. These are the same saved-location intent with target-specific activation policy.
- [BrowserSpaceSwitcherCommonListsButton.swift:14](../../../CrestShared/Features/Sidebar/Components/BrowserSpaceSwitcher/Components/BrowserSpaceSwitcherCommonListsButton.swift#L14) reaches directly into macOS-only `BrowserMacDownloadFeedbackState`; the shared button then chooses its arrival trigger at `:71`.

Why it matters: the capability-based UI contract is established but not universal. Supporting a new interaction combination or reusing one of these shared components still requires changing compiled-platform branches. This is a bounded cleanup opportunity, not evidence that current touch/keyboard use is broken.

Recommended scope: pass deck-axis policy as an explicit shell/layout input, place it with presentation, and make saved-location activation an explicit interaction rule or unify behavior where harmless. Supply download-arrival feedback through a simple value/optional presentation input. Do not eliminate all conditional compilation: macOS-only menu styles, native gesture bridges, UIKit photo/file APIs, and scene presentation are real platform seams.

Validation: existing capability tests plus intentional manual/preview checks for touch, hover-only, touch+hover, compact versus regular containers, and accessibility activation. Validate the real interaction contract, not token numbers or file location.

Counterevidence: `BrowserInteractionCapabilities` has genuinely independent touch and hover bits; touch retains reachable controls with an attached pointer. `BrowserSidebarInteractionPolicy` derives row/target/reveal behavior from them. [BrowserSidebarInteractionPolicyTests.swift:65](../../../CrestTests/BrowserSidebarInteractionPolicyTests.swift#L65) covers all four combinations. There is no evidence that hard-coded `supportsHover: true` in the mobile host means it falsely claims a trackpad is currently connected: this model describes supported interactions, not device discovery.

## Existing strengths to preserve

- [BrowserSidebar.swift:17](../../../CrestShared/Features/Sidebar/BrowserSidebar.swift#L17) owns shared selection/utility/reset/confirmation behavior and accepts a shell content builder, page access, capabilities, and explicit chrome actions. It is an effective example for future consolidation.
- [SpaceSidebarBrowsingContent.swift:60](../../../CrestMac/Features/Sidebar/BrowserSidebar/Components/SpaceSidebarContent/SpaceSidebarBrowsingContent.swift#L60) and the mobile Space page compose shared pinned/tab/header sections with shell bindings rather than maintaining independent row behavior.
- [BrowserSpaceHeaderActionsMenu.swift:44](../../../CrestShared/Features/Sidebar/Components/BrowserSpaceHeader/Components/BrowserSpaceHeaderActionsMenu.swift#L44) builds a common menu from optional actions and `supportsMultipleWindows`; this follows the intended capability/action design.
- Typed `SpaceID`, `TabID`, profile-bearing runtime assignments, and centralized BrowserSession state transitions make identity and Space isolation explicit. Domain policy extraction is extensive.
- Shared stores use `@Observable`, with non-observable collaborators excluded from observation, and explicit production system boundaries. Do not replace these with generic abstraction layers merely to satisfy a pattern checklist.
- The architecture and vertical-structure guards are intentionally narrow, documented, and avoid arbitrary class-size/file-count targets. Preserve that restraint; prioritize lifecycle ownership and change amplification over further file splitting.

## Suggested implementation order

1. Common archive/reconciliation lifecycle ownership, in narrow steps with existing runtime tests.
2. Shared tab command intents and their behavioral coverage.
3. Presentation-state ownership and neutral data-transfer model placement, using current runtime-assignment types.
4. Capability tail cleanup as those UI areas next change.

No production behavior has been changed or runtime failure asserted by this review.

## Validation follow-up: failed iOS palette test

Applied systematic-debugging to the root agent’s iOS log at `/tmp/crest-audit-xcode-ios.log`; no production or test edits. Classification: **stale test expectation**, supported by implementation, current policy tests, and Git history.

[MobileBrowserRootModelTests.swift:356](../../../CrestMobileTests/MobileBrowserRootModelTests.swift#L356) creates different source/destination Spaces and profiles, then at `:375` expects cross-Space palette selection to succeed. Shared `BrowserCommandPaletteActionPolicy.swift:22`–`:23` deliberately rejects targets outside the source Space/profile. `MobileBrowserRootModel.swift:568` delegates to that policy and returns before mutating selection or creating a page. This explains the false result plus all four downstream selected Space/profile/tab/active-page assertions reported at test lines 375/381/382/383/384. Later stale-profile rejection assertions did not fail.

Countercheck: [BrowserCommandPaletteActionPolicyTests.swift:31](../../../CrestTests/BrowserCommandPaletteActionPolicyTests.swift#L31) explicitly expects cross-Space targeting to be rejected. Commit `aac042880149f71446ff01ec79d317a7656b8237` (August 25) introduced the same-Space/profile guards, removed other-Space palette results, and updated that shared policy test. Git blame shows the mobile success expectation remains from August 15. Current `BrowserCommandPaletteResults.swift:34` builds tab candidates from `input.space`, consistent with the policy.

The observed failures follow synchronously from the policy rejection and are not attributable to the Simulator’s unrelated WebKit/DNS log noise. Root owns the isolated rerun for repeatability. A future focused test cleanup should exercise successful selection of another tab inside the current Space, separately assert cross-Space rejection, and retain the stale-profile checks. This is test-maintenance evidence, not a newly diagnosed user-facing product defect.
