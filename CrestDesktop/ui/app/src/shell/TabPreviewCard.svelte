<script lang="ts" module>
  /** BrowserTabPreviewSurface and BrowserTabPreviewCard's measures. */
  const card = { width: 280, padding: 8, gap: 8, margin: 8, rise: 6, pictureHeight: 168, estimatedHeight: 220 };

  /** The site a tab's address names, without its scheme or a leading www. */
  function siteOf(url: string | null): string | null {
    if (!url) return null;
    try {
      const host = new URL(url).hostname;
      return host ? host.replace(/^www\./, "") : null;
    } catch {
      return null;
    }
  }
</script>

<script lang="ts">
  import type { TabState } from "@crest/contracts";
  import { entranceScale, motion as tokens } from "@crest/design";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { presence, reducesMotion } from "../motion";
  import { TabIcon } from "./Sidebar";
  import { tabPreview } from "./TabPreview.svelte";

  /** The card of the tab the pointer rests on (TabPreviewLayer). */
  let { session, tab, row, pageId, picture }: {
    session: Session;
    tab: TabState;
    row: DOMRect;
    pageId: string | null;
    picture: string | null;
  } = $props();

  let element = $state<HTMLDivElement>();
  let height = $state(card.estimatedHeight);
  // The page's last picture, as wide as the card allows and no taller than 168, its top kept.
  let aspect = $state(0.75);
  $effect.pre(() => {
    if (!picture) aspect = 0.75;
  });
  // Measured as drawn, so the card stays inside the window.
  $effect(() => {
    void [tab, row, pageId, picture, aspect];
    untrack(() => {
      if (element) height = element.offsetHeight;
    });
  });
  const left = $derived.by(() => {
    const sidebar = document.querySelector(".sidebar")?.getBoundingClientRect();
    return Math.min((sidebar?.right ?? row.right) + card.gap, innerWidth - card.width - card.margin);
  });
  const top = $derived(Math.max(card.margin, Math.min(row.top - card.rise, innerHeight - height - card.margin)));
  // It grows from the row's side, at the row's middle.
  const origin = $derived(`0px ${row.top + row.height / 2 - top}px`);
  const domain = $derived(siteOf(tab.url));
  const pictureWidth = card.width - card.padding * 2;
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div bind:this={element} class="tab-preview" style:left="{left}px" style:top="{top}px" style:transform-origin={origin}
  in:presence={{ pose: { opacity: 0, scale: entranceScale }, timing: reducesMotion() ? tokens.hover : tokens.tabPreview }}
  out:presence={{ pose: { opacity: 0 }, timing: tokens.hover }}
  onpointerenter={() => tabPreview.enterCard()} onpointerleave={() => tabPreview.leaveCard()}>
  <div class="tab-preview-header">
    <TabIcon {session} {tab} {pageId} size={16} />
    <div class="tab-preview-text">
      <span class="tab-preview-title">{tab.displayTitle}</span>
      {#if domain}
        <span class="tab-preview-site">{domain}</span>
      {/if}
    </div>
  </div>
  {#if picture}
    <img class="tab-preview-picture" src={picture} alt="" style:height="{Math.min(pictureWidth * aspect, card.pictureHeight)}px"
      onload={(event) => {
        const image = event.currentTarget as HTMLImageElement;
        if (image.naturalWidth > 0) aspect = image.naturalHeight / image.naturalWidth;
      }} />
  {/if}
</div>
