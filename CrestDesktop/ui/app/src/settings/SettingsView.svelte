<script lang="ts" module>
  import { Listeners } from "../reactive";
  import type { SettingsPageName } from "./catalog";
  import type { SpacePageTab } from "./SpacePage.svelte";

  /** What Settings shows: one of its pages, or a Space's page. */
  export type SettingsSelection = { readonly kind: "page"; readonly name: SettingsPageName } | { readonly kind: "space"; readonly spaceId: string; readonly tab?: SpacePageTab };

  /**
   * Where a Settings tab is asked to go, from the palette's Settings Pages or
   * a menu's Edit Space…: each request names its tab and carries a revision,
   * and the tab takes only a newer one, as the Mac's do.
   */
  let request: { readonly tabId: string; readonly selection: SettingsSelection; readonly revision: number } | null = null;
  const listeners = new Listeners();
  const settingsRequest = listeners.reader(() => request);

  export function requestSettings(tabId: string, selection: SettingsSelection) {
    request = { tabId, selection, revision: (request?.revision ?? 0) + 1 };
    listeners.notify();
  }

  /**
   * What one Settings tab keeps while it stays open, as the Mac's
   * BrowserSettingsTabState: the page it shows, the tab a Space's page shows
   * as the selection moves between Spaces, the last request it took, and
   * where each page was scrolled.
   */
  interface SettingsTabState {
    selection: SettingsSelection;
    spaceTab: SpacePageTab;
    taken: number;
    readonly scrolls: Map<string, number>;
  }

  const tabStates = new Map<string, SettingsTabState>();

  function tabState(tabId: string): SettingsTabState {
    let state = tabStates.get(tabId);
    if (!state) {
      state = { selection: { kind: "page", name: "general" }, spaceTab: "appearance", taken: 0, scrolls: new Map() };
      tabStates.set(tabId, state);
    }
    return state;
  }

  /**
   * The Chromium build the window runs, as its engine credits name it: the
   * full version where the browser tells it, which the user agent string
   * shortens.
   */
  function useEngineCredit(): { readonly current: string | null } {
    const short = /Chrome\/([\d.]+)/.exec(navigator.userAgent)?.[1] ?? null;
    let full = $state<string | null>(null);
    $effect(() => {
      const data = (navigator as Navigator & {
        userAgentData?: { getHighEntropyValues(hints: string[]): Promise<{ fullVersionList?: { brand: string; version: string }[] }> };
      }).userAgentData;
      void data?.getHighEntropyValues(["fullVersionList"]).then((values) => {
        const chromium = values.fullVersionList?.find((entry) => entry.brand === "Chromium" || entry.brand === "Google Chrome");
        if (chromium) full = chromium.version;
      }).catch(() => {});
    });
    return {
      get current() {
        const version = full ?? short;
        return version ? `Chromium ${version}` : null;
      },
    };
  }
</script>

<script lang="ts">
  import type { SpaceState } from "@crest/contracts";
  import { untrack } from "svelte";
  import { MediaQuery } from "svelte/reactivity";

  import AppIcon from "../shell/AppIcon.svelte";
  import type { Session } from "../boot";
  import { residentNativeTabs } from "../native-tabs";
  import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { destinations, leadingRows, matches, sidebarTint, trailingRows } from "./catalog";
  import { keptScroll } from "./controls";
  import SettingsPane from "./panes.svelte";
  import SpacePage from "./SpacePage.svelte";
  import "./settings.css";

  /**
   * The Mac's BrowserSettingsView, the Settings tab's content: a 224-wide
   * sidebar with the build, a search field, Settings' pages and the Spaces,
   * then the chosen page, its title over one centred column of grouped
   * settings. Pages change at once.
   */
  let { session, tabId, spaces, shownSpace }: {
    session: Session;
    /** The Settings tab, whose page and scroll positions stay while it does. */
    tabId: string;
    spaces: readonly SpaceState[];
    /** The Space the window shows, whose Settings tab this is. */
    shownSpace: SpaceState;
  } = $props();

  const kept = $derived(tabState(tabId));
  let selection = $state.raw<SettingsSelection>(untrack(() => kept.selection));
  const setSelection = (next: SettingsSelection) => {
    kept.selection = next;
    selection = next;
  };
  let spaceTab = $state<SpacePageTab>(untrack(() => kept.spaceTab));
  let search = $state("");
  $effect(() => {
    const asked = settingsRequest();
    const id = tabId;
    untrack(() => {
      if (!asked || asked.tabId !== id || asked.revision <= kept.taken) return;
      kept.taken = asked.revision;
      setSelection(asked.selection);
      // A request for a Space's page may name its tab, as Extensions does.
      if (asked.selection.kind === "space" && asked.selection.tab) {
        kept.spaceTab = asked.selection.tab;
        spaceTab = asked.selection.tab;
      }
    });
  });
  // The tab holds Settings while its state lives, so its row reads loaded;
  // a closed Settings tab's state goes with it.
  $effect(() => {
    residentNativeTabs.add(tabId);
  });
  $effect(() => {
    const open = new Set(spaces.flatMap((space) => space.tabs.map((tab) => tab.id)));
    for (const id of tabStates.keys()) {
      if (open.has(id)) continue;
      tabStates.delete(id);
      residentNativeTabs.delete(id);
    }
  });
  // A Space that left goes back to General.
  const selectedSpace = $derived.by(() => {
    const shown = selection;
    return shown.kind === "space" ? spaces.find((space) => space.id === shown.spaceId) : undefined;
  });
  $effect(() => {
    if (selection.kind === "space" && !selectedSpace) untrack(() => setSelection({ kind: "page", name: "general" }));
  });
  const darkScheme = new MediaQuery("(prefers-color-scheme: dark)");
  const rowsFor = (names: readonly SettingsPageName[]) => names.filter((name) => matches(destinations[name], search));
  const leading = $derived(rowsFor(leadingRows));
  const trailing = $derived(rowsFor(trailingRows));
  const spaceMatches = (space: SpaceState) => !search.trim() || matches(destinations.spaces, search)
    || space.settings.name.toLowerCase().includes(search.trim().toLowerCase());
  const listedSpaces = $derived(spaces.filter(spaceMatches));
  const credit = useEngineCredit();
</script>

{#snippet pageRow(name: SettingsPageName)}
  {@const destination = destinations[name]}
  {@const selected = selection.kind === "page" && selection.name === name}
  <button type="button" class={["settings-nav-row", selected && "selected"]} aria-current={selected || undefined}
    onclick={() => setSelection({ kind: "page", name })}>
    <span class="settings-nav-symbol" style:color={sidebarTint(destination.color, darkScheme.current)}>
      <SymbolIcon name={destination.symbol} size={15} />
    </span>
    <span class="settings-nav-title">{destination.navigationTitle}</span>
  </button>
{/snippet}

<div class="settings" data-testid="settings">
  <aside class="settings-sidebar" aria-label="Settings">
    <div class="settings-build">
      <AppIcon size={40} />
      <div>
        <div class="settings-build-name">Crest Browser</div>
        <div class="settings-build-detail">Version {__CREST_VERSION__}</div>
        {#if credit.current}<div class="settings-build-detail">{credit.current}</div>{/if}
      </div>
    </div>
    <div class="settings-search">
      <SymbolIcon name="magnifyingglass" size={13} />
      <input bind:value={search} placeholder="Search settings" aria-label="Search settings" />
      {#if search}
        <button type="button" aria-label="Clear" onclick={() => (search = "")}>
          <SymbolIcon name="xmark.circle.fill" size={13} />
        </button>
      {/if}
    </div>
    <nav class="settings-nav">
      {#each leading as name (name)}{@render pageRow(name)}{/each}
      {#if listedSpaces.length > 0}
        <div class="settings-nav-heading">Spaces</div>
        {#each listedSpaces as space (space.id)}
          {@const selected = selection.kind === "space" && selection.spaceId === space.id}
          {@const sub = space.membership?.primaryId && space.membership.primaryId !== space.id}
          <button type="button" class={["settings-nav-row space", selected && "selected", sub && "sub"]}
            aria-current={selected || undefined} onclick={() => setSelection({ kind: "space", spaceId: space.id })}>
            <span class="settings-nav-symbol">
              <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={18} />
            </span>
            <span class="settings-nav-title">{space.settings.name || "Untitled Space"}</span>
            {#if space.settings.requiresAuthentication}<SymbolIcon name="lock.fill" size={10} class="settings-nav-lock" />{/if}
          </button>
        {/each}
      {/if}
      {#if trailing.length > 0}<div class="settings-nav-gap"></div>{/if}
      {#each trailing as name (name)}{@render pageRow(name)}{/each}
    </nav>
  </aside>
  <div class="settings-divider"></div>
  <main class="settings-page">
    {#if selection.kind === "page"}
      <header class="settings-page-header"><h2>{destinations[selection.name].title}</h2></header>
      {#key selection.name}
        <div class="settings-scroll" {...keptScroll(kept.scrolls, selection.name)}>
          <div class="settings-column">
            <SettingsPane name={selection.name} {session} {spaces} {shownSpace} />
          </div>
        </div>
      {/key}
    {:else if selectedSpace}
      <SpacePage {session} space={selectedSpace} {spaces} scrolls={kept.scrolls} tab={spaceTab}
        onOpenSpace={(spaceId) => setSelection({ kind: "space", spaceId })}
        onTab={(next) => {
          kept.spaceTab = next;
          spaceTab = next;
        }} />
    {/if}
  </main>
</div>
