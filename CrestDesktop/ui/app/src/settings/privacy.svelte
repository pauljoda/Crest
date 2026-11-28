<script lang="ts" module>
  import type { SpaceState } from "@crest/contracts";

  /** The group `space` belongs to, as the Mac's BrowserStore finds it: its primary, then every Space that stays in it. */
  export function groupOf(space: SpaceState, spaces: readonly SpaceState[]) {
    const primary = spaces.find((candidate) => candidate.id === space.membership?.primaryId) ?? space;
    const members = spaces.filter((candidate) => candidate.id === primary.id || candidate.membership?.primaryId === primary.id);
    return { primary, members };
  }

  /** The saved choices reach the read model once a window asks the core to publish them. */
  let askedForPermissions = false;
</script>

<script lang="ts">
  import { AdoptSitePermissions } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import SymbolIcon from "../SymbolIcon.svelte";
  import ClearBrowsingDataSection from "./ClearBrowsingDataSection.svelte";
  import { Group, Row } from "./controls";
  import RetentionSection from "./RetentionSection.svelte";
  import SitePermissionsSection from "./SitePermissionsSection.svelte";
  import { send, useWebsiteData } from "./space-privacy.svelte";
  import WebsiteDataSection from "./WebsiteDataSection.svelte";

  /**
   * The Mac's BrowserPrivacySettingsPane for one Space: what it keeps, the
   * choices it saved for sites, the sites that keep data in it, and clearing
   * what it browsed, then a note when its group shares all of that.
   */
  let { session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] } = $props();

  $effect(() => {
    void session;
    untrack(() => {
      if (askedForPermissions) return;
      askedForPermissions = true;
      // A refused request is asked again the next time the page opens.
      void send(session, AdoptSitePermissions({ records: null })).then((sent) => {
        if (!sent) askedForPermissions = false;
      });
    });
  });
  const group = $derived(groupOf(space, spaces));
  const shared = $derived(group.members.length > 1);
  const sites = useWebsiteData(() => session, () => space);
</script>

{#if sites.locked}
  <Group footer="Unlock this Space to see its privacy settings.">
    <Row>{#snippet title()}<SymbolIcon name="lock.fill" size={12} /> {space.settings.name} is locked{/snippet}</Row>
  </Group>
{:else}
  <RetentionSection {session} {space} />
  <SitePermissionsSection {session} {space} {shared} />
  <WebsiteDataSection {session} {space} {sites} {shared} />
  <ClearBrowsingDataSection {session} {space} didClear={sites.read} />
  {#if shared}<p class="settings-footer">Shared by {group.primary.settings.name}’s Sub-Spaces.</p>{/if}
{/if}
