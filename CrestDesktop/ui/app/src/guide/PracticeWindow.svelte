<script lang="ts" module>
  import type { BrandColor } from "@crest/contracts";
  import { brand } from "@crest/design";

  import { transitionStyle } from "../motion";

  /** The Mac's CrestBrandPalette coral, the practice's split ring. */
  const coral: BrandColor = { red: brand.coral[0] / 255, green: brand.coral[1] / 255, blue: brand.coral[2] / 255, alpha: 1 };

  function rgb(color: readonly number[]): string {
    return `rgb(${color.join(" ")})`;
  }
</script>

<script lang="ts">
  import { PracticeTab, type TabState } from "@crest/contracts";

  import { Browsing } from "../browsing";
  import type { Timing } from "../motion";
  import PageColumns from "../shell/PageColumns.svelte";
  import { Sidebar, TabIcon } from "../shell/Sidebar";
  import { shortcutText } from "../shortcuts";
  import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import type { Chapter } from "./guide";
  import Fits from "./Fits.svelte";
  import type { Practice } from "./practice";

  /**
   * BrowserGettingStartedPracticeWindow: a small window, three dots and a
   * title over the practice's sidebar and its document area, where the shown
   * tab's card stands, or a split's cards side by side.
   */
  let { practice, chapter, width, transition }: {
    practice: Practice;
    chapter: Chapter;
    width: number;
    transition: Timing;
  } = $props();

  const session = $derived(practice.session);
  const browsing = $derived(new Browsing(session));
  const space = $derived.by(() => (useCoreVersion(session), practice.space));
  const practiceWindow = $derived.by(() => (useCoreVersion(session), practice.window));
  const roomy = $derived(width >= 620);
  const sidebarWidth = $derived(roomy ? (chapter.showsSplit ? 220 : 285) : null);
  // The column keeps the width it last had while it grows to fill the window, as Motion left it.
  let keptWidth: number | null = null;
  const columnWidth = $derived.by(() => {
    if (sidebarWidth !== null) keptWidth = sidebarWidth;
    return keptWidth;
  });
  const shownTabId = $derived.by(() => (useCoreVersion(session), practice.shownTabId));
  const shownTabs = $derived(new Map(practiceWindow?.shownTabs.flatMap((shown) => (shown.tabId ? [[shown.spaceId, shown.tabId] as const] : [])) ?? []));
  const cards = $derived.by(() => (useCoreVersion(session), practice.cards));
  const bindings = $derived.by(() => (useCoreVersion(session), session.core.state.shortcuts?.bindings ?? []));

  /** What the practice holds now, read as the core's batches change it. */
  const tabIdOf = (tab: PracticeTab) => (useCoreVersion(session), practice.tabId(tab));
  const canMove = (tabId: string, offset: number) => (useCoreVersion(session), practice.canMove(tabId, offset));

  const keys = (name: string) => {
    const bound = bindings.find((binding) => binding.command.name === name)?.keys;
    return bound ? shortcutText(bound) : null;
  };
  const stop = (run: () => void) => (event: MouseEvent) => {
    event.stopPropagation();
    run();
  };
</script>

<!-- A practice tab's example page: its icon and title over what it holds, or the split lesson it teaches. -->
{#snippet practiceDocument(tab: TabState, showsSplit: boolean)}
  {@const isPacking = tab.id === tabIdOf(PracticeTab.packing) || tab.title === PracticeTab.packing.title}
  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
  <div class="practice-document" data-testid="practice-document-{tab.id}"
    onclick={() => practice.focus(tab.id)}>
    <div class="practice-document-title">
      <TabIcon session={practice.session} {tab} pageId={null} size={18} />
      <span>{tab.displayTitle}</span>
    </div>
    <hr />
    <div class="practice-document-body">
      {#if showsSplit}
        {@render splitInstructions(tab, isPacking)}
      {:else if isPacking}
        <h3 class="practice-display packing">Packing list</h3>
        {#each ["Walking shoes", "Water bottle", "Trail map"] as item (item)}
          <span class="practice-check"><SymbolIcon name="checkmark.circle" size={13} />{item}</span>
        {/each}
      {:else}
        <span class="practice-art sage"><SymbolIcon name="mountain.2" size={54} strokeWidth={0.75} /></span>
        <h3 class="practice-display trail">Weekend trail guide</h3>
        <p class="practice-secondary">Distance: 4.2 miles<br />Duration: 2 hours<br />Route: lakeside loop</p>
      {/if}
    </div>
    <span class="practice-document-label">{showsSplit ? "Split View practice" : "Example page"}</span>
  </div>
{/snippet}

{#snippet pair(left: string, right: string, does: string)}
  {@const first = keys(left)}
  {@const second = keys(right)}
  {#if first && second}
    <p class="practice-shortcut">{first} / {second} {does}</p>
  {/if}
{/snippet}

<!-- What the Split View chapter teaches on each card: to make a split, to rearrange its cards, and to focus one. -->
{#snippet splitInstructions(tab: TabState, isPacking: boolean)}
  {#if cards.tabIds.length < 2}
    <span class="practice-art sky"><SymbolIcon name="rectangle.split.2x1" size={44} strokeWidth={0.75} /></span>
    <h3 class="practice-display">Drag another tab here</h3>
    <p class="practice-lead">Drag Packing list from the sidebar onto this page. Or right-click it and choose Split with Current Tab.</p>
    <span>
      <button type="button" class="setup-button primary" data-testid="guide-make-split"
        onclick={(event) => {
          event.stopPropagation();
          void practice.makeSplit();
        }}>
        <SymbolIcon name="plus.rectangle.on.rectangle" size={13} />Add Packing list
      </button>
    </span>
  {:else if isPacking}
    <span class="practice-art sage"><SymbolIcon name="arrow.left.arrow.right" size={32} strokeWidth={1.25} /></span>
    <h3 class="practice-display small">Rearrange cards</h3>
    <p class="practice-secondary">Move this card to either side.</p>
    {#key tab.id}
      <Fits>
        {#snippet wide()}{@render moveButtons(tab)}{/snippet}
        {#snippet narrow()}{@render moveButtons(tab)}{/snippet}
      </Fits>
    {/key}
    {@render pair("moveSplitCardLeft", "moveSplitCardRight", "moves the focused card.")}
  {:else}
    <span class="practice-art sky"><SymbolIcon name="cursorarrow" size={32} strokeWidth={1.25} /></span>
    <h3 class="practice-display small">Choose the focused card</h3>
    <p class="practice-secondary">Click either card. Its border shows which page receives your keyboard commands.</p>
    <span>
      <button type="button" class="setup-button secondary" data-testid="guide-focus-{tab.id}"
        onclick={stop(() => practice.focus(tab.id))}>
        <SymbolIcon name="cursorarrow.click" size={13} />Focus this card
      </button>
    </span>
    {@render pair("focusPreviousSplitCard", "focusNextSplitCard", "focuses the previous or next card.")}
    <hr />
    <p class="practice-secondary small">
      To focus by hovering, turn on Focus follows pointer under Split View in Settings → Tabs. Shortcuts can also be changed in Settings.
    </p>
  {/if}
{/snippet}

{#snippet moveButtons(tab: TabState)}
  <button type="button" class="setup-button secondary" disabled={!canMove(tab.id, -1)}
    data-testid="guide-move-left" onclick={stop(() => void practice.move(tab.id, -1))}>
    <SymbolIcon name="arrow.left" size={13} />Move left
  </button>
  <button type="button" class="setup-button secondary" disabled={!canMove(tab.id, 1)}
    data-testid="guide-move-right" onclick={stop(() => void practice.move(tab.id, 1))}>
    <SymbolIcon name="arrow.right" size={13} />Move right
  </button>
{/snippet}

{#if space && practiceWindow}
  <div class="practice-window" data-practice-window="true" data-testid="practice-window">
    <div class="practice-window-chrome">
      <span class="practice-window-dots" aria-hidden="true">
        <span style:background={rgb(brand.coral)}></span>
        <span style:background={rgb(brand.butter)}></span>
        <span style:background={rgb(brand.sage)}></span>
      </span>
      <span class="practice-window-title"><SymbolIcon name="leaf" size={12} />Practice window</span>
      <span class="practice-window-brand">Crest</span>
    </div>
    <div class="practice-window-body">
      <div class="practice-sidebar-column"
        style:width={columnWidth === null ? undefined : `${columnWidth}px`} style:flex-grow={sidebarWidth === null ? 1 : 0}
        style:transition="{transitionStyle('width', transition)}, {transitionStyle('flex-grow', transition)}">
        <div class="practice-sidebar-header">
          <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={30} />
          <span>
            <strong>Practice</strong>
            <small>Your example Space</small>
          </span>
        </div>
        <Sidebar {session} {browsing} {space} spaces={[space]} {shownTabId}
          {shownTabs} page={null} pagesByTab={new Map()} showsNavigation={false} permission={null}
          downloads={null} onDialog={() => {}} docked onToggleDock={() => {}}
          practice={{ openExampleTab: () => practice.openExampleTab() }} />
      </div>
      {#if roomy || chapter.showsSplit}
        <div class="practice-document-area">
          {#if cards.tabIds.length === 0}
            <div class="practice-unavailable" data-testid="practice-cleared">
              <SymbolIcon name="sun.max" size={34} />
              <strong>Open tabs cleared</strong>
              <span>Your pinned and saved tabs are still in the sidebar.</span>
            </div>
          {:else}
            <PageColumns windowId={session.windowId} {cards} focusedTabId={shownTabId} accent={coral} interactive
              onFocus={(tabId: string, byPointer: boolean) => !byPointer && practice.focus(tabId)} onResize={(shares: readonly number[]) => practice.resize(shares)}>
              {#snippet renderCard(tabId: string)}
                {@const tab = space.tabs.find((candidate) => candidate.id === tabId)}
                {#if tab}
                  {@render practiceDocument(tab, chapter.showsSplit)}
                {/if}
              {/snippet}
            </PageColumns>
          {/if}
        </div>
      {/if}
    </div>
  </div>
{/if}
