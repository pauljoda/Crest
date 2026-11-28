<script lang="ts" module>
  import type { StatusTone } from "@crest/contracts";

  function hostOf(url: string | null | undefined): string | null {
    if (!url) return null;
    try {
      return new URL(url).host || null;
    } catch {
      return null;
    }
  }

  /**
   * The status colour an archive reason wears, as the Mac's CrestStatusTone
   * draws it from Crest's tokens in the scheme the sidebar reads in; a reason
   * without a tone stays secondary.
   */
  function toneColor(tone: StatusTone | null): string {
    return tone ? `var(--status-${tone.name}, var(--fg-secondary))` : "var(--fg-secondary)";
  }
</script>

<script lang="ts">
  import { type ArchivedTabState, type HistoryEntryState, RestoreArchivedTab, type SpaceState } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import type { Downloads } from "../downloads.svelte";
  import { type MenuEntry, showContextMenu } from "../menus";
  import { DownloadRow } from "../shell/DownloadsPanel";
  import { TabIcon } from "../shell/Sidebar";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import {
    filterNamed,
    type UtilityItem,
    type UtilitySurfaceName,
    utilityItems,
    utilitySections,
    utilitySurfaces,
  } from "./utility-list";

  /**
   * A Space's utility list in its sidebar page, in place of its tabs, as the
   * Mac's SpaceSidebarUtilityContent: the search toolbar standing where the
   * address field stood, with its filter menu, and below it the list grouped
   * by when, or what to say when there is nothing to list. A click on the
   * list's blank space puts it away.
   */
  let { session, surface: name, space, spaces, downloads, searchText, onSearchText, filterName, onFilterName,
    onOpenHistory, onRestored, onClearHistory, onDismiss }: {
    session: Session;
    surface: UtilitySurfaceName;
    space: SpaceState;
    spaces: readonly SpaceState[];
    downloads: Downloads | null;
    /** The window's search, which every Space's list shares until the list changes. */
    searchText: string;
    onSearchText: (text: string) => void;
    filterName: string;
    onFilterName: (name: string) => void;
    onOpenHistory: (entry: HistoryEntryState) => void;
    onRestored: (tabId: string) => void;
    onClearHistory: () => void;
    onDismiss: () => void;
  } = $props();

  const surface = $derived(utilitySurfaces[name]);
  const setSearchText = (text: string) => onSearchText(text);
  const setFilterName = (filter: string) => onFilterName(filter);
  const filter = $derived(filterNamed(surface, filterName));

  // The search settles 60 ms after typing stops, as the Mac's list prepares it.
  let query = $state("");
  $effect(() => {
    const text = searchText;
    const timer = setTimeout(() => {
      query = text;
    }, text === "" ? 0 : 60);
    return () => clearTimeout(timer);
  });

  // Downloads seen here are seen.
  const profileDownloads = $derived.by(() => (useCoreVersion(session), downloads?.of(space.profileId) ?? []));
  $effect(() => {
    const [shown, seen, profileId, listed] = [name, downloads, space.profileId, profileDownloads];
    untrack(() => {
      if (shown === "downloads" && seen && listed.some((download) => !download.isAcknowledged)) {
        seen.acknowledge(profileId);
      }
    });
  });

  // Sections refresh at midnight and when a filter's window passes, as the Mac's clock does; a minute is close enough.
  let now = $state(new Date());
  $effect(() => {
    const timer = setInterval(() => {
      now = new Date();
    }, 60_000);
    return () => clearInterval(timer);
  });
  const items = $derived(utilityItems(name, space, spaces, profileDownloads));
  const sections = $derived(utilitySections(items, query, filter, now));

  const openFilterMenu = (button: HTMLButtonElement) => {
    const bounds = button.getBoundingClientRect();
    const entries: MenuEntry[] = surface.filters.map((option) => ({
      title: option.title, icon: option.symbol,
      checked: option.name === filter.name,
      run: () => setFilterName(option.name),
    }));
    if (surface.clearsHistory) entries.push("separator", { title: "Clear History", icon: "trash", run: onClearHistory });
    void showContextMenu({ clientX: bounds.left, clientY: bounds.bottom }, entries);
  };

  const restore = async (archived: ArchivedTabState) => {
    const restored = await session.core.send(RestoreArchivedTab({
      workspaceId: session.workspaceId, windowId: session.windowId, spaceId: space.id, tabId: archived.tab.id,
    })).then(() => true, () => false);
    if (restored) onRestored(archived.tab.id);
  };

  const blank = (event: MouseEvent) => {
    if (event.target === event.currentTarget) onDismiss();
  };
</script>

{#snippet utilityRow(item: UtilityItem)}
  {#if item.kind === "archive"}
    {@const { archived } = item}
    {@const host = hostOf(archived.tab.url)}
    <button class="utility-row" aria-label="Restore {archived.tab.displayTitle}" onclick={() => restore(archived)}>
      <span class="utility-row-icon"><TabIcon {session} tab={archived.tab} pageId={null} /></span>
      <span class="utility-row-text">
        <span class="utility-row-title">{archived.tab.displayTitle}</span>
        <span class="utility-row-subtitle" style:color={toneColor(archived.reason.tone)}>
          <SymbolIcon name={archived.reason.symbol} size={9} strokeWidth={2.5} />{` ${archived.reason.title}${host ? ` · ${host}` : ""}`}
        </span>
      </span>
      <span class="utility-row-trailing"><SymbolIcon name="arrow.uturn.backward" size={13} /></span>
    </button>
  {:else if item.kind === "history"}
    {@const { entry } = item}
    {@const host = hostOf(entry.url) ?? entry.url}
    <button class="utility-row" aria-label="Open {entry.title}" onclick={() => onOpenHistory(entry)}>
      <span class="utility-row-icon"><SymbolIcon name="globe" size={16} /></span>
      <span class="utility-row-text">
        <span class="utility-row-title">{entry.title}</span>
        <span class="utility-row-subtitle">{entry.visitCount > 1 ? `${host} · ${entry.visitCount} visits` : host}</span>
      </span>
      <span class="utility-row-trailing tertiary"><SymbolIcon name="arrow.up.forward" size={13} /></span>
    </button>
  {:else if item.kind === "download"}
    {#if downloads}
      <div class="utility-row-download"><DownloadRow download={item.download} {downloads} /></div>
    {/if}
  {/if}
{/snippet}

<!-- The list and its toolbar come and go at once, as the Mac's presentation swaps them. -->
<section class="utility-list" aria-label={surface.title}>
  <div class="utility-toolbar">
    <div class="utility-search">
      <SymbolIcon name="magnifyingglass" size={11} strokeWidth={2.25} class="utility-search-glyph" />
      <!-- svelte-ignore a11y_autofocus -->
      <input
        class="utility-search-input"
        placeholder={surface.searchPrompt}
        aria-label={surface.searchPrompt}
        value={searchText}
        spellcheck={false}
        autofocus
        oninput={(event) => setSearchText(event.currentTarget.value)}
        onkeydown={(event) => {
          // Escape clears the search, as a search field's does; it doesn't put the list away.
          if (event.key !== "Escape" || !searchText) return;
          event.preventDefault();
          setSearchText("");
        }}
      />
      {#if searchText}
        <button class="utility-search-clear" aria-label="Clear" title="Clear" onclick={() => setSearchText("")}>
          <SymbolIcon name="xmark.circle.fill" size={13} />
        </button>
      {/if}
    </div>
    <button class="utility-filter" aria-label={surface.filterLabel} {...{ "aria-description": filter.title }} title={surface.filterLabel}
      onclick={(event) => openFilterMenu(event.currentTarget)}>
      <SymbolIcon name="line.3.horizontal.decrease" size={15} />
    </button>
  </div>
  {#if sections.length === 0}
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="utility-empty" onclick={blank}>
      <SymbolIcon name={query.trim() ? "magnifyingglass" : surface.symbol} size={30} />
      <strong>{query.trim() ? "No Results" : surface.emptyTitle}</strong>
      <span>{query.trim() ? surface.noResults(query.trim()) : filter.name !== "all" ? "No items match the selected filter." : surface.emptyDescription}</span>
    </div>
  {:else}
    <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
    <div class="utility-sections" onclick={blank}>
      {#each sections as section (section.id)}
        <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
        <section class="utility-section" onclick={blank}>
          <h3 class="utility-section-title">{section.title}</h3>
          {#each section.items as item (item.id)}
            {@render utilityRow(item)}
          {/each}
        </section>
      {/each}
    </div>
  {/if}
</section>
