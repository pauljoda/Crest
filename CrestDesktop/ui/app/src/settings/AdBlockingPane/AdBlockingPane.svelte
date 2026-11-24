<script lang="ts">
  import type { Session } from "../../boot";
  import { useCoreVersion } from "../../use-core";
  import BlockingSitesSection from "./BlockingSitesSection.svelte";
  import CustomFiltersSection from "./CustomFiltersSection.svelte";
  import CustomListsSection from "./CustomListsSection.svelte";
  import FilterListsSection from "./FilterListsSection.svelte";
  import LevelSection from "./LevelSection.svelte";

  /**
   * The Mac's BrowserAdBlockingSettingsPane: ad blocking holds for every page
   * in every Space, so it has a pane of its own. The level it blocks at, the
   * filter lists that level turns on, the lists the person subscribes to by
   * address, their own rules, and the sites where it blocks nothing.
   * Everything below the level waits while blocking is off.
   */
  let { session }: { session: Session } = $props();

  const lists = $derived((useCoreVersion(session), session.core.state.filterLists));
  const blockingSites = $derived((useCoreVersion(session), session.core.state.blockingSites));
</script>

{#if lists}
  {@const off = !lists.level.blocksContent}
  <LevelSection {session} {lists} />
  <div class={["settings-waits", off && "off"]} aria-disabled={off || undefined} inert={off}>
    <FilterListsSection {session} {lists} />
    <CustomListsSection {session} {lists} />
    <CustomFiltersSection {session} saved={lists.customFilters} />
    <BlockingSitesSection {session} sites={blockingSites} />
  </div>
{/if}
