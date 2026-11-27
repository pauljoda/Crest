<script lang="ts">
  import type { TabState } from "@crest/contracts";
  import { motion } from "@crest/design";
  import { onMount, type Snippet } from "svelte";

  import { reducesMotion, timed } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { addressPresentation } from "./Sidebar/sidebar-parts.svelte";
  import { tabPreview, type PreviewState } from "./preview-state.svelte";

  let { tabs, inner, row, onSelect, recentlyTyped }: {
    tabs: readonly TabState[]; inner: PreviewState; row: Snippet<[TabState, PreviewState]>;
    onSelect: (id: string) => void; recentlyTyped: () => boolean;
  } = $props();
  let search = $state<HTMLInputElement>();
  let query = $state("");
  const fold = (text: string) => text.normalize("NFD").replace(/\p{Mark}/gu, "").toLocaleLowerCase();
  const matches = $derived.by(() => {
    const needle = fold(query.trim());
    return needle ? tabs.filter(tab => fold(tab.displayTitle).includes(needle)
      || (tab.url && fold(addressPresentation(tab.url).domain).includes(needle))) : tabs;
  });
  $effect(() => {
    tabPreview.held = query !== "";
    return () => { tabPreview.held = false; };
  });
  function focus() {
    if (search && !recentlyTyped()) search.focus({ preventScroll: true });
  }
  onMount(() => {
    const timer = setTimeout(focus, reducesMotion() ? 0 : timed(motion.tabPreview).duration);
    return () => clearTimeout(timer);
  });
  function openFirst(event: KeyboardEvent) {
    if (event.key === "Enter" && !event.isComposing && matches[0]) {
      event.preventDefault();
      onSelect(matches[0].id);
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="folder-preview" onpointerenter={focus}>
  <label class="folder-preview-search">
    <SymbolIcon name="magnifyingglass" size={14} />
    <input bind:this={search} bind:value={query} aria-label="Search Tabs" placeholder="Search Tabs" onkeydown={openFirst} />
  </label>
  <div class="folder-preview-list">
    {#each matches as tab (tab.id)}
      {@render row(tab, inner)}
    {:else}
      <span class="folder-preview-empty">{tabs.length ? "No Results" : "No Tabs"}</span>
    {/each}
  </div>
</div>
