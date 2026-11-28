<script lang="ts">
  import { type FolderState, TabPlacement, type TabState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import type { Lift } from "../sidebar-drag.svelte";
  import TabIcon from "./TabIcon.svelte";

  /**
   * What a lift carries, under the pointer where it grabbed it, as the Mac's
   * lift preview: a row, or a tile for a pinned tab, a little larger than
   * itself, with a shadow; and why the aimed drop is refused, beside it.
   */
  let { session, lift, tab, folder, pageId }: {
    session: Session; lift: Lift; tab: TabState | undefined; folder: FolderState | undefined; pageId: string | null;
  } = $props();

  const tile = $derived(tab?.placement === TabPlacement.pinned && lift.aim?.kind === "list" && lift.aim.section === TabPlacement.pinned);
  // Over the page area the row becomes the page card it would be, as the
  // Mac's preview does: 240 by 160, the icon large over the title.
  const card = $derived(lift.aim?.kind === "split");
  const width = $derived(card ? 240 : tile ? 52 : Math.min(364, Math.max(220, lift.width)));
  const height = $derived(card ? 160 : tile ? 52 : 40);
  const left = $derived(lift.pointer.x - (card ? width / 2 : Math.min(lift.grab.x, width)));
  const top = $derived(lift.pointer.y - (card ? height / 2 : Math.min(lift.grab.y, height)));
</script>

<div class={`lift-preview${tile ? " tile" : ""}${card ? " card" : ""}`} style:left="{left}px" style:top="{top}px"
  style:width="{width}px" style:height="{height}px" aria-hidden="true">
  {#if tab}
    <TabIcon {session} {tab} {pageId} size={card ? 32 : tile ? 20 : 16} />
  {/if}
  {#if folder}
    <SymbolIcon name="folder.fill" />
  {/if}
  {#if !tile}
    <span class="row-title">{tab?.displayTitle ?? folder?.title}</span>
  {/if}
</div>
{#if lift.refusal}
  <div class="lift-refusal" style:left="{lift.pointer.x + 12}px" style:top="{top + height + 12}px" role="status">
    <SymbolIcon name="nosign" size={12} />
    {lift.refusal}
  </div>
{/if}
