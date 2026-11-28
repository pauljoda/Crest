<script lang="ts" module>
  /** The modifiers the switcher's keys hold, whose release picks the highlighted tab. */
  export interface SwitcherHold {
    readonly control: boolean;
    readonly shift: boolean;
    readonly alt: boolean;
  }

  /**
   * How a switcher began, which the window keeps from the first press on: the
   * window takes the keyboard for it at once, before the switcher draws, so a
   * quick release still arrives, and notes here what came before the switcher
   * could hear it.
   */
  export interface SwitcherStart {
    /** The step the first press took. */
    readonly direction: 1 | -1;
    readonly hold: SwitcherHold;
    /** Further steps taken before the switcher drew. */
    steps: number;
    /** Whether the held keys were let go before the switcher drew. */
    released: boolean;
    /** Whether the keyboard went elsewhere before the switcher drew. */
    lost: boolean;
  }

  /** What the window passes on to a switcher while it is held. */
  export interface SwitcherControls {
    /** Another press of the keys that opened it, or the other direction's, that the window heard. */
    step(direction: 1 | -1): void;
    keyDown(event: KeyboardEvent): void;
    keyUp(event: KeyboardEvent): void;
    /** The keyboard went elsewhere: a click away, or the window going to the background. */
    lostKeys(): void;
  }

  /** Whether a key coming up is one of the modifiers the switcher's keys hold. */
  export function releasesHold(event: { readonly key: string }, hold: SwitcherHold): boolean {
    return (event.key === "Control" && hold.control) || (event.key === "Shift" && hold.shift) || (event.key === "Alt" && hold.alt);
  }

  /** RecentTabSwitcherMetrics. */
  const metrics = Object.freeze({
    small: 8,
    cardSpacing: 8,
    panelPadding: 16,
    thumbnailHeight: 112,
    singlePageWidth: 176,
    splitPageWidth: 136,
    titleRowHeight: 24,
    windowMargin: 16,
  });

  function pageWidth(count: number): number {
    return count > 1 ? metrics.splitPageWidth : metrics.singlePageWidth;
  }

  function cardWidth(count: number): number {
    const pages = Math.max(count, 1);
    return pageWidth(count) * pages + metrics.small * (pages - 1) + metrics.small * 2;
  }
</script>

<script lang="ts">
  import { type RecentTabItem, RecentTabs, ShowTab, type SpaceState, type TabState } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { transitionStyle } from "../motion";
  import { TabIcon } from "../shell/Sidebar";
  import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
  import { type TabPictures, useTabPictures } from "./tab-pictures";

  /**
   * The Mac's recent-tab switcher: while the keys of Most Recent Tab are held,
   * a panel over the window shows the tabs the window showed lately, the one
   * it shows first, and each further press moves the highlight; letting the
   * keys go shows the highlighted one. A quick press goes straight to the tab
   * before last without the panel showing. The window gives the switcher the
   * keyboard while it lasts, so the release arrives; arrows, digits and Return
   * work as they do on the Mac, and Esc, a click outside, or the window going
   * to the background leave things as they were.
   */
  let { session, spaces, pagesByTab, pictures, start, register, onEnd }: {
    session: Session;
    spaces: readonly SpaceState[];
    pagesByTab: ReadonlyMap<string, string>;
    pictures: TabPictures;
    start: SwitcherStart;
    register: (controls: SwitcherControls | null) => void;
    onEnd: () => void;
  } = $props();

  let items = $state.raw<readonly RecentTabItem[] | null>(null);
  let index = $state(0);
  let shown = $state(false);
  let ended = false;
  // A release before the list arrives picks from the list once it does.
  let commitsWhenListed = false;

  const finish = (commits: boolean) => {
    if (ended) return;
    if (commits && !items) {
      commitsWhenListed = true;
      return;
    }
    ended = true;
    const list = items;
    const item = commits && list && index > 0 ? list[index] : undefined;
    if (item) void session.core.send(ShowTab({ windowId: session.windowId, spaceId: item.spaceId, tabId: item.focusedTabId })).catch(() => {});
    onEnd();
  };
  const highlight = (next: number) => {
    const count = items?.length ?? 0;
    if (count === 0) return;
    index = ((next % count) + count) % count;
  };
  // Steps that come before the list are counted from where the list starts.
  let earlySteps = 0;
  const step = (by: 1 | -1) => {
    shown = true;
    if (!items) earlySteps += by;
    else highlight(index + by);
  };

  /** Whether an event says the keys were let go without the switcher hearing it. */
  const releasedUnheard = (event: { ctrlKey: boolean; altKey: boolean }) =>
    (start.hold.control && !event.ctrlKey) || (start.hold.alt && !event.altKey);
  const keyDown = (event: KeyboardEvent) => {
    // A held modifier repeating says nothing new.
    if (event.key === "Control" || event.key === "Shift" || event.key === "Alt") return;
    // A key without the modifier the keys hold is a release that went
    // elsewhere; Shift only turns a step around.
    if (releasedUnheard(event)) return finish(event.key !== "Escape");
    shown = true;
    const count = items?.length ?? 0;
    if (event.key === "Escape") finish(false);
    else if (event.key === "Enter") finish(true);
    else if (event.key === "ArrowLeft" || event.key === "ArrowUp") step(-1);
    else if (event.key === "ArrowRight" || event.key === "ArrowDown") step(1);
    else if (event.key === "Tab") step(event.shiftKey ? -1 : 1);
    else if (/^[1-5]$/.test(event.key) && Number(event.key) <= count) highlight(Number(event.key) - 1);
  };
  $effect(() => {
    const report = register;
    untrack(() => report({
      step,
      keyDown,
      keyUp: (event) => releasesHold(event, start.hold) && finish(true),
      lostKeys: () => finish(false),
    }));
    return () => report(null);
  });

  // The list, asked again every quarter second while the keys are held; the
  // highlight stays on its tab while the tab is listed, and an empty list ends it.
  // The list is the window's; the direction is the opening press's, which the
  // first answer that arrives takes, whichever ask it answers.
  $effect(() => {
    const { core, windowId } = session;
    let current = true;
    const ask = async () => {
      let listed: readonly RecentTabItem[];
      try {
        ({ items: listed } = await core.query(RecentTabs({ windowId })));
      } catch {
        // A failed ask leaves the list as it was, or still to come: the next one asks again.
        return;
      }
      if (!current || ended) return;
      const capped = listed.slice(0, 5);
      if (capped.length === 0) return finish(false);
      const first = items === null;
      let next: number;
      if (first) {
        const opening = start.direction > 0 ? Math.min(1, capped.length - 1) : capped.length - 1;
        const steps = start.steps + earlySteps;
        next = (((opening + steps) % capped.length) + capped.length) % capped.length;
      } else {
        const highlighted = items?.[index];
        const kept = highlighted ? capped.findIndex((item) => item.tabIds.includes(highlighted.focusedTabId)) : -1;
        next = kept >= 0 ? kept : Math.min(index, capped.length - 1);
      }
      items = capped;
      index = next;
      // What happened before the list came: the keyboard gone, or the keys let go.
      if (first && start.lost) finish(false);
      else if (first && (start.released || commitsWhenListed)) finish(true);
    };
    void ask();
    const timer = setInterval(() => void ask(), 250);
    return () => {
      current = false;
      clearInterval(timer);
    };
  });

  // The panel shows once the keys have been held a tenth of a second, and the
  // tab the window shows is pictured afresh for it.
  $effect(() => {
    const timer = setTimeout(() => (shown = true), 100);
    return () => clearTimeout(timer);
  });
  const shownTabId = $derived(items?.[0]?.focusedTabId);
  $effect(() => {
    // Once, as the panel shows.
    const showing = shown;
    void shownTabId;
    untrack(() => {
      const shownItem = items?.[0];
      if (!showing || !shownItem) return;
      for (const tabId of shownItem.tabIds) {
        const pageId = pagesByTab.get(tabId);
        const page = pageId ? session.core.state.pages.get(pageId) : undefined;
        if (pageId && page?.live.url) pictures.capture(session.core, { pageId, tabId, address: page.live.url }, true);
      }
    });
  });

  let pointer: { x: number; y: number; moved: boolean } | null = null;
  const pointed = (event: PointerEvent, at: number) => {
    const resting = pointer;
    if (!resting) {
      pointer = { x: event.clientX, y: event.clientY, moved: false };
      return;
    }
    if (!resting.moved) resting.moved = Math.hypot(event.clientX - resting.x, event.clientY - resting.y) > 1;
    if (resting.moved && at !== index) highlight(at);
  };

  const tabsById = $derived(new Map(spaces.flatMap((space) => space.tabs.map((tab) => [tab.id, tab] as const))));
  const spacesById = $derived(new Map(spaces.map((space) => [space.id, space])));
  const list = $derived(items ?? []);
  const mixesSpaces = $derived(new Set(list.map((item) => item.spaceId)).size > 1);
  const widths = $derived(list.map((item) => cardWidth(item.tabIds.length)));
  const natural = $derived({
    width: widths.reduce((sum, width) => sum + width, 0) + metrics.cardSpacing * Math.max(widths.length - 1, 0) + metrics.panelPadding * 2,
    height: metrics.thumbnailHeight + metrics.titleRowHeight + metrics.small * 3 + metrics.panelPadding * 2,
  });
  const scale = $derived(Math.min(1, (window.innerWidth - metrics.windowMargin * 2) / Math.max(natural.width, 1)));
  const highlightX = $derived(widths.slice(0, index).reduce((sum, width) => sum + width + metrics.cardSpacing, 0));
  const highlightTransition = $derived([transitionStyle("transform", tokens.surface), transitionStyle("width", tokens.surface)].join(", "));
  const spoken = (at: number) => {
    const item = list[at];
    if (!item) return "";
    const title = item.tabIds.map((tabId) => tabsById.get(tabId)?.displayTitle ?? "").join(", ");
    const space = mixesSpaces ? spacesById.get(item.spaceId)?.settings.name : undefined;
    return `${title}${space ? `, ${space}` : ""}, ${at + 1} of ${list.length}`;
  };
</script>

<!--
  A page's picture over its icon and title, or its icon large on the tab's
  colour while no picture exists, with its Space's icon in the picture's
  corner when the list mixes Spaces.
-->
{#snippet switcherPage(tab: TabState, pageId: string | null, picture: string | null, width: number, badge: SpaceState | null)}
  {@const accent = tab.iconAccent}
  <div class="recent-tabs-page" style:width="{width}px">
    <div class="recent-tabs-thumbnail"
      style:background={!picture && accent ? `rgb(${accent.red * 255} ${accent.green * 255} ${accent.blue * 255} / 0.6)` : undefined}>
      {#if picture}
        <img src={picture} alt="" />
      {:else}
        <TabIcon {session} {tab} {pageId} size={40} />
      {/if}
      {#if badge}
        <span class="recent-tabs-badge">
          <SpaceIdentityIcon symbol={badge.settings.symbol} branding={badge.settings.look} size={20} />
        </span>
      {/if}
    </div>
    <div class="recent-tabs-title">
      <TabIcon {session} {tab} {pageId} size={16} />
      <span>{tab.displayTitle}</span>
    </div>
  </div>
{/snippet}

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="recent-tabs-layer" onpointermove={(event) => {
  // The pointer moving with the keys let go is a release the switcher missed.
  if (releasedUnheard(event)) finish(true);
}}>
  {#if shown && items}
    <!-- A click outside the panel leaves things as they were, and goes no further. -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="recent-tabs-backdrop" onpointerdown={(event) => {
      event.preventDefault();
      finish(false);
    }}></div>
    <div class="recent-tabs-panel" role="group" aria-label="Recent tabs"
      style:width="{natural.width * scale}px" style:height="{natural.height * scale}px"
      onpointerdown={(event) => event.preventDefault()}>
      <div class="recent-tabs-cards" style:transform={scale < 1 ? `scale(${scale})` : undefined}>
        {#if widths.length > 0}
          <div class="recent-tabs-highlight" aria-hidden="true" style:transform="translateX({highlightX}px)"
            style:width="{widths[index] ?? 0}px" style:transition={highlightTransition}></div>
        {/if}
        {#each list as item, at (`${item.spaceId}-${item.tabIds.join()}`)}
          <button class="recent-tabs-card" tabindex={-1}
            aria-label={spoken(at)} aria-current={at === index || undefined}
            onpointermove={(event) => pointed(event, at)}
            onclick={() => {
              index = at;
              finish(true);
            }}>
            {#each item.tabIds as tabId, page (tabId)}
              {@const tab = tabsById.get(tabId)}
              {#if tab}
                {@const space = spacesById.get(item.spaceId)}
                {@const picture = (useTabPictures(pictures), pictures.picture(tabId))}
                {@render switcherPage(tab, pagesByTab.get(tabId) ?? null, picture, pageWidth(item.tabIds.length),
                  mixesSpaces && page === item.tabIds.length - 1 ? space ?? null : null)}
              {/if}
            {/each}
          </button>
        {/each}
      </div>
    </div>
  {/if}
  <div class="visually-hidden" aria-live="polite">{shown ? spoken(index) : ""}</div>
</div>
