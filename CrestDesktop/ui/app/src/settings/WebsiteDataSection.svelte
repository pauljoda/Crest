<script lang="ts">
  import type { SpaceState } from "@crest/contracts";

  import type { Session } from "../boot";
  import { showContextMenu } from "../menus";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import SymbolIcon from "../SymbolIcon.svelte";
  import Confirmation from "./Confirmation.svelte";
  import { Button, Group, Row } from "./controls";
  import { listed, type WebsiteData } from "./space-privacy.svelte";

  /** BrowserWebsiteDataSection: the sites that keep data, with Remove for one and Remove All. */
  let { session, space, sites, shared }: { session: Session; space: SpaceState; sites: WebsiteData; shared: boolean } = $props();

  let query = $state("");
  let removingAll = $state(false);
  const matching = $derived.by(() => {
    const wanted = query.trim().toLowerCase();
    return (sites.sites ?? []).filter((site) => !wanted || site.site.toLowerCase().includes(wanted));
  });
</script>

<Group title="Website data">
  {#if sites.sites === null}
    <div class="settings-row settings-progress-row"><span class="settings-progress" role="progressbar" aria-label="Loading"></span></div>
  {:else if sites.sites.length === 0 && sites.complete}
    <Row>{#snippet title()}<span class="settings-secondary-text">No website data</span>{/snippet}</Row>
  {:else}
    {#if sites.sites.length > 0}
      <div class="settings-row">
        <span class="settings-search-field settings-row-search">
          <SymbolIcon name="magnifyingglass" size={13} />
          <input bind:value={query} placeholder="Search Websites" aria-label="Search Websites" />
        </span>
      </div>
      {#each matching as site (site.site)}
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div class="settings-row" oncontextmenu={(event) => {
          event.preventDefault();
          void showContextMenu(event, [{ title: "Remove", icon: "trash", run: () => sites.remove([site]) }]);
        }}>
          <div class="settings-row-text">
            <span class="settings-row-title settings-truncates">{site.site}</span>
            <span class="settings-row-subtitle settings-truncates">{listed(site.kinds.map((kind) => kind.title))}</span>
          </div>
          <button type="button" class="settings-button" disabled={sites.removing} aria-label={`Remove data for ${site.site}`}
            onclick={() => sites.remove([site])}>
            Remove
          </button>
        </div>
      {/each}
    {/if}
    <div class="settings-row settings-actions-row">
      <span class="settings-actions-status">
        {#if sites.removalFailed}<SymbolIcon name="exclamationmark.triangle" size={11} /> Some data couldn’t be removed{/if}
      </span>
      <Button destructive disabled={sites.removing} onClick={() => (removingAll = true)}>Remove All…</Button>
    </div>
  {/if}
  {#if sites.sites !== null && !sites.complete}
    <div class="settings-row"><span class="settings-actions-status">Some sites may be missing.</span></div>
  {/if}
</Group>
<Confirmation question={removingAll}>
  {#snippet children()}
    <Sheet title={`Remove all website data in “${space.settings.name}”?`} primary="Remove All" secondary="Cancel" warning destructive
      onPrimary={() => {
        removingAll = false;
        sites.removeAll();
      }}
      onEscape={() => (removingAll = false)}>
      <p class="sheet-message">
        {shared ? "You’ll be signed out of every site in this Space and the others of its group." : "You’ll be signed out of every site in this Space."}
      </p>
    </Sheet>
  {/snippet}
</Confirmation>
