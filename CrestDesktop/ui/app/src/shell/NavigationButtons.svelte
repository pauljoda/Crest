<script lang="ts">
  import type { PageState } from "@crest/contracts";

  import type { Browsing } from "../browsing";
  import ChromeButton from "./ChromeButton.svelte";

  /**
   * Back, forward, and reload or stop, for the page the window shows, as the
   * Mac's sidebar draws them at its top trailing side: thin chevrons and the
   * circular arrow at the Mac's 15-point symbol size in 30-point targets,
   * bright while they can act.
   */
  let { browsing, page }: { browsing: Browsing; page: PageState | null } = $props();

  const live = $derived(page?.live);
</script>

<ChromeButton symbol="chevron.left" label="Back" disabled={!live?.canGoBack} className="navigation-button" size={23}
  onClick={() => page && void browsing.back(page.id)} />
<ChromeButton symbol="chevron.right" label="Forward" disabled={!live?.canGoForward} className="navigation-button" size={23}
  onClick={() => page && void browsing.forward(page.id)} />
<ChromeButton symbol={live?.isLoading ? "xmark" : "arrow.clockwise"} label={live?.isLoading ? "Stop" : "Reload"}
  disabled={!page} className="navigation-button" size={live?.isLoading ? 16 : 18}
  onClick={() => page && void (live?.isLoading ? browsing.stop(page.id) : browsing.reload(page.id))} />
