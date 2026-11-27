<script lang="ts">
  import { ResetSpacePermissions, type SpaceState } from "@crest/contracts";

  import type { Session } from "../boot";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import { useCoreVersion } from "../use-core";
  import Confirmation from "./Confirmation.svelte";
  import { Button, Group, Row } from "./controls";
  import SitePermissionRow from "./SitePermissionRow.svelte";
  import { send } from "./space-privacy.svelte";

  /** BrowserSavedSitePermissionSection: each choice the Space saved for a site, which a menu changes or forgets. */
  let { session, space, shared }: { session: Session; space: SpaceState; shared: boolean } = $props();

  const records = $derived((useCoreVersion(session), session.core.state.sitePermissions.get(space.id) ?? []));
  let resetting = $state(false);
</script>

<Group title="Site permissions">
  {#if records.length === 0}
    <Row>{#snippet title()}<span class="settings-secondary-text">No saved permissions</span>{/snippet}</Row>
  {:else}
    {#each records as record (record.id)}
      <SitePermissionRow {session} {record} />
    {/each}
    <div class="settings-row settings-actions-row">
      <span class="settings-actions-status"></span>
      <Button destructive onClick={() => (resetting = true)}>Reset All…</Button>
    </div>
  {/if}
</Group>
<Confirmation question={resetting}>
  {#snippet children()}
    <Sheet title="Reset All" primary="Reset All" secondary="Cancel" warning destructive
      onPrimary={() => {
        resetting = false;
        void send(session, ResetSpacePermissions({ spaceId: space.id }));
      }}
      onEscape={() => (resetting = false)}>
      <p class="sheet-message">
        {shared ? "Makes every site ask again in this Space and the others of its group" : "Makes every site ask again in this Space"}
      </p>
    </Sheet>
  {/snippet}
</Confirmation>
