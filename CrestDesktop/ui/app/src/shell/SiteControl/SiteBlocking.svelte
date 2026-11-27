<script lang="ts">
  import type { SiteOrigin } from "@crest/contracts";

  import type { Session } from "../../boot";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { setSiteContentBlocking, useSiteContentBlocking } from "../site-control.svelte";

  /**
   * Whether the Space blocks ads and trackers on the site, which the Mac offers
   * among a page's actions ("Turn Off Blocking on example.com") and Windows
   * offers where its browsers keep a site's tracking prevention: beside how
   * the connection is secured. Shown only where the Space blocks.
   */
  let { session, spaceId, origin, onChanged }: {
    session: Session;
    spaceId: string;
    origin: SiteOrigin;
    /** Reloads the page, so the change shows. */
    onChanged: () => void;
  } = $props();

  const blocking = useSiteContentBlocking(() => ({ session, spaceId, origin }));
  const title = "Block Ads and Trackers";
</script>

{#if blocking.current !== null}
  {@const blocks = blocking.current}
  <div class="site-control-divider"></div>
  <div class="site-blocking">
    <span class="site-permission-label">
      <SymbolIcon name="shield" size={12} />
      {title}
    </span>
    <button type="button" role="switch" aria-checked={blocks} aria-label="{title} on {origin.host}"
      title={blocks ? `Turn Off Blocking on ${origin.host}` : `Turn On Blocking on ${origin.host}`}
      class={["site-blocking-switch", blocks && "on"]}
      onclick={() => void setSiteContentBlocking(session.core, spaceId, origin, !blocks).then((changed) => changed && onChanged())}>
      <span class="site-blocking-knob"></span>
    </button>
  </div>
{/if}
