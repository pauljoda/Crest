<script lang="ts" module>
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

  import type { Session } from "../boot";
  import { TabIcon } from "./Sidebar";

  /** The card of the tab the pointer rests on (TabPreviewLayer). */
  let { session, tab, pageId, picture }: {
    session: Session;
    tab: TabState;
    pageId: string | null;
    picture: string | null;
  } = $props();

  // The page's last picture, as wide as the card allows and no taller than 168, its top kept.
  let aspect = $state(0.75);
  $effect.pre(() => {
    if (!picture) aspect = 0.75;
  });
  const domain = $derived(siteOf(tab.url));
  const pictureWidth = 280 - 8 * 2;
</script>

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
    <img class="tab-preview-picture" src={picture} alt="" style:height="{Math.min(pictureWidth * aspect, 168)}px"
      onload={(event) => {
        const image = event.currentTarget as HTMLImageElement;
        if (image.naturalWidth > 0) aspect = image.naturalHeight / image.naturalWidth;
      }} />
  {/if}
