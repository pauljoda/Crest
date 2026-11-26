<script lang="ts">
  import type { TabState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { isGuide, useTabIconSource } from "./sidebar-parts.svelte";
  import TabIconFace from "./TabIconFace.svelte";

  let { session, tab, pageId, size = 16 }: { session: Session; tab: TabState; pageId: string | null; size?: number } = $props();

  // svelte-ignore state_referenced_locally
  const icon = useTabIconSource(session, () => tab, () => pageId);
</script>

<TabIconFace icon={icon.current} symbol={tab.symbol} guide={isGuide(tab)} {size} />
