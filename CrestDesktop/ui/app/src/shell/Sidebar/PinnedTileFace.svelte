<script lang="ts">
  import type { TabState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { useFaviconColor } from "../../favicon-palette.svelte";
  import { isGuide, useTabIconSource } from "./sidebar-parts.svelte";
  import TabIconFace from "./TabIconFace.svelte";

  /**
   * A pinned tile's icon and the ring the tile wears while its window shows
   * it, in the icon's own color, as the Mac's pins take their site's color.
   * A site without an icon rings in its grey globe's.
   */
  let { session, tab, pageId }: { session: Session; tab: TabState; pageId: string | null } = $props();

  // svelte-ignore state_referenced_locally
  const icon = useTabIconSource(session, () => tab, () => pageId);
  const accent = useFaviconColor(() => icon.current);
</script>

<span class="pin-ring" style:--pin-accent={accent.current ?? undefined} aria-hidden="true"></span>
<TabIconFace icon={icon.current} symbol={tab.symbol} guide={isGuide(tab)} size={19} />
