<script lang="ts">
  import type { SpaceState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import ActionArtwork from "./ActionArtwork.svelte";
  import { extensionMenu, runExtensionAction, useExtensionActions } from "./extension-actions.svelte";

  /**
   * The Mac's BrowserPinnedExtensionStrip in the sidebar: the Space's pinned
   * actions above its tabs, each a 24-point tile that runs it, on the same
   * surface as the address field, shown only while it holds any.
   */
  let { session, space, pageId, pageKey }: {
    session: Session;
    space: SpaceState;
    pageId: string | null;
    pageKey: string;
  } = $props();

  // A window's session is its own for as long as it is open.
  // svelte-ignore state_referenced_locally
  const actions = useExtensionActions(session, () => space.profileId, () => pageId, () => pageKey);
  const pinned = $derived(actions.current.pinned);
</script>

{#if pinned.length > 0}
  <div class="extension-strip" role="toolbar" aria-label="Pinned Extensions">
    {#each pinned as action (action.id)}
      <button type="button" class={["extension-tile", !action.enabled && "unavailable"]}
        aria-label={action.name} title={action.name}
        onclick={(event) => void runExtensionAction(session, action, pageId, event.currentTarget)}
        oncontextmenu={(event) => {
          event.preventDefault();
          extensionMenu(session, space, action, event);
        }}>
        <ActionArtwork {action} size={16} />
      </button>
    {/each}
  </div>
{/if}
