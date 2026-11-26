<script lang="ts" module>
  /** How many sites the section lists before it offers a field that finds one. */
  const searchableCount = 10;
</script>

<script lang="ts">
  import { SetSiteContentBlocking, type SiteContentBlocking } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { originName } from "../../shell/prompts/prompt-text";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { Group, Row } from "../controls";
  import { send } from "./ad-blocking";

  /**
   * BrowserBlockingSitesSettingsSection: the sites where Crest blocks nothing,
   * in every Space, each with a way to block on it again. A long list offers a
   * field that finds a site.
   */
  let { session, sites }: { session: Session; sites: readonly SiteContentBlocking[] } = $props();

  let query = $state("");
  // One row per site, however many Spaces turned it off.
  const unique = $derived.by(() => {
    const seen = new Set<string>();
    return sites.filter((site) => {
      const key = originName(site.origin);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  });
  const searchable = $derived(unique.length > searchableCount);
  const matches = $derived.by(() => {
    const wanted = query.trim().toLowerCase();
    return !searchable || !wanted ? unique : unique.filter((site) => originName(site.origin).toLowerCase().includes(wanted));
  });
</script>

<Group title="Sites with Blocking Off" footer="Turn blocking off for a site from its Site Controls. Ad blocking settings stay on this device.">
  {#if searchable}
    <div class="settings-row">
      <span class="settings-search-field settings-row-search">
        <SymbolIcon name="magnifyingglass" size={13} />
        <input bind:value={query} placeholder="Search Sites" aria-label="Search Sites" />
      </span>
    </div>
  {/if}
  {#each matches as site (originName(site.origin))}
    {@const name = originName(site.origin)}
    <div class="settings-row">
      <span class="settings-row-title settings-truncates">{name}</span>
      <!-- Turning it on again from any Space turns it on everywhere. -->
      <button type="button" class="settings-icon-button" aria-label={`Turn on blocking for ${name}`} title={`Turn on blocking for ${name}`}
        onclick={() => void send(session, SetSiteContentBlocking({ spaceId: site.spaceId, origin: site.origin, blocks: true }))}>
        <SymbolIcon name="shield" size={15} />
      </button>
    </div>
  {/each}
  {#if unique.length === 0}
    <Row>{#snippet title()}<span class="settings-secondary-text">None</span>{/snippet}</Row>
  {:else if matches.length === 0}
    <Row>{#snippet title()}<span class="settings-secondary-text">No Sites Found</span>{/snippet}</Row>
  {/if}
</Group>
