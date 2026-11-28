<script lang="ts">
  import type { SpaceState, TabState } from "@crest/contracts";
  import { untrack, type Snippet } from "svelte";

  import { previewFolders, previewTabs } from "../appearance.svelte";
  import { portal } from "../attachments";
  import type { Session } from "../boot";
  import { type TabPictures, useTabPictures } from "../switcher/tab-pictures";
  import { useCoreVersion } from "../use-core";
  import FolderPreviewCard from "./FolderPreviewCard.svelte";
  import PreviewSurface from "./PreviewSurface.svelte";
  import { folderTabIds } from "./Sidebar/sidebar-parts.svelte";
  import TabPreviewCard from "./TabPreviewCard.svelte";
  import { sidebarOnRight } from "../appearance.svelte";
  import { PreviewState, tabPreview } from "./preview-state.svelte";

  let { session, space, tabs, shownTabId, pagesByTab, pictures, enabled, folderRow, onSelect }: {
    session: Session; space: SpaceState; tabs: ReadonlyMap<string, TabState>; shownTabId: string | null;
    pagesByTab: ReadonlyMap<string, string>; pictures: TabPictures; enabled: boolean;
    folderRow: Snippet<[TabState, PreviewState]>; onSelect: (id: string) => void;
  } = $props();

  const inner = new PreviewState();
  const shown = $derived(tabPreview.shown);
  const tab = $derived(shown?.kind === "tab" ? tabs.get(shown.id) : undefined);
  const folder = $derived(shown?.kind === "folder" ? space.folders.find(f => f.id === shown.id) : undefined);
  const nested = $derived(inner.shown && folder ? tabs.get(inner.shown.id) : undefined);
  const folderTabs = $derived(folder ? folderTabIds(space, folder.id).flatMap(id => tabs.get(id) ?? []) : []);
  const picture = (id: string) => (useTabPictures(pictures), pictures.picture(id));
  const close = () => { inner.dismiss(); tabPreview.dismiss(); };
  let lastTyped = -Infinity;

  $effect.pre(() => {
    tabPreview.enabled = enabled;
    inner.enabled = enabled && previewTabs.current;
    if (!enabled || (shown && !(shown.kind === "folder" ? folder && previewFolders.current : tab && previewTabs.current))) close();
    if (!folder || !previewTabs.current || (inner.shown && (!nested || !folderTabs.includes(nested)))) inner.dismiss();
  });
  $effect(() => {
    void [space.id, shownTabId];
    untrack(close);
  });
  $effect(() => () => { tabPreview.enabled = false; close(); });

  function outside(event: Event) {
    if (!(event.target instanceof Element && event.target.closest(".tab-preview"))) close();
  }
  function key(event: KeyboardEvent) {
    const input = event.target instanceof HTMLInputElement || (event.target instanceof HTMLElement && event.target.isContentEditable);
    if (input && event.key.length === 1) lastTyped = performance.now();
    if ((event.key === "Enter" || event.key === " ") && event.target instanceof HTMLElement
      && event.target.matches(".folder-preview-list .tab-row")) {
      event.preventDefault();
      event.stopImmediatePropagation();
      event.target.click();
    } else if (event.key === "Escape" && shown) {
      event.preventDefault();
      event.stopImmediatePropagation();
      close();
    } else if (!event.key.startsWith("Arrow")) outside(event);
  }
  $effect(() => {
    window.addEventListener("pointerdown", outside, true);
    window.addEventListener("wheel", outside, { capture: true, passive: true });
    window.addEventListener("keydown", key, true);
    window.addEventListener("blur", close);
    return () => {
      window.removeEventListener("pointerdown", outside, true);
      window.removeEventListener("wheel", outside, true);
      window.removeEventListener("keydown", key, true);
      window.removeEventListener("blur", close);
    };
  });
  const area = $derived(shown ? (useCoreVersion(session), document.querySelector(".space-content")?.getBoundingClientRect()) : undefined);
  const near = (rect: DOMRect) => sidebarOnRight.current ? rect.left : rect.right;
  const edge = $derived(shown ? near(document.querySelector(".sidebar")?.getBoundingClientRect() ?? shown.row) : 0);
  const coverLeft = $derived(area ? (sidebarOnRight.current ? area.left : Math.max(area.left, edge)) : 0);
  const coverRight = $derived(area ? (sidebarOnRight.current ? Math.min(area.right, edge) : area.right) : 0);
</script>

<div class="tab-preview-layer" {@attach portal(() => document.querySelector(".browser-window"))}>
  {#if enabled && shown && area}
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="tab-preview-cover" style:left="{coverLeft}px" style:top="{area.top}px"
      style:width="{Math.max(0, coverRight - coverLeft)}px" style:height="{area.height}px"
      onpointermove={(e) => { tabPreview.pointerOnPage({ x: e.clientX, y: e.clientY }); inner.pointerOnPage({ x: e.clientX, y: e.clientY }); }}
      onpointerdown={close}></div>
    {#if folder || tab}
      <PreviewSurface state={tabPreview} row={shown.row} {edge}>
        {#if folder}
          {#key folder.id}
            <FolderPreviewCard tabs={folderTabs} {inner} row={folderRow} recentlyTyped={() => performance.now() - lastTyped < 1000}
              onSelect={(id) => { close(); onSelect(id); }} />
          {/key}
        {:else if tab}
          <TabPreviewCard {session} {tab} pageId={pagesByTab.get(tab.id) ?? null} picture={picture(tab.id)} />
        {/if}
      </PreviewSurface>
    {/if}
    {#if nested && inner.shown}
      <PreviewSurface state={inner} parent={tabPreview} row={inner.shown.row} edge={near(tabPreview.card?.getBoundingClientRect() ?? inner.shown.row)}>
        <TabPreviewCard {session} tab={nested} pageId={pagesByTab.get(nested.id) ?? null} picture={picture(nested.id)} />
      </PreviewSurface>
    {/if}
  {/if}
</div>
