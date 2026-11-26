<script lang="ts">
  import { ExtensionChange, type SpaceState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { change, extensions } from "../../extensions";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import ActionArtwork from "./ActionArtwork.svelte";
  import { extensionMenu, runExtensionAction, useExtensionActions } from "./extension-actions.svelte";

  /**
   * The Mac's BrowserSiteExtensionsSection in Site Controls: every action the
   * page offers, four to a row, each running on a click, with a pin that shows
   * on hover; and the way to manage extensions.
   */
  let { session, space, pageId, pageKey, onRun, onManage }: {
    session: Session;
    space: SpaceState;
    pageId: string;
    pageKey: string;
    /** Puts Site Controls away before an action runs, so its popup opens over the page. */
    onRun: (run: () => void) => void;
    onManage: () => void;
  } = $props();

  // A window's session is its own for as long as it is open.
  // svelte-ignore state_referenced_locally
  const actions = useExtensionActions(session, () => space.profileId, () => pageId, () => pageKey);
  const page = $derived(actions.current.page);
</script>

<div class="site-extensions">
  <div class="site-extensions-header">
    <span>Extensions</span>
    <button type="button" class="site-extensions-manage" aria-label="Manage Extensions" title="Manage Extensions" onclick={onManage}>
      <SymbolIcon name="plus" size={11} strokeWidth={2.5} />
    </button>
  </div>
  {#if page.length === 0}
    <span class="site-extensions-empty"><SymbolIcon name="puzzlepiece.extension" size={12} /> No extension actions for this page</span>
  {:else}
    <div class="site-extensions-grid">
      {#each page as action (action.id)}
        <div class="site-extension">
          <button type="button" class={["site-extension-action", !action.enabled && "unavailable"]} aria-label={action.name}
            title={action.name}
            onclick={(event) => {
              const button = event.currentTarget;
              const bounds = button.getBoundingClientRect();
              // The popup opens where the button was, once the panel has gone.
              onRun(() => void runExtensionAction(session, action, pageId, { getBoundingClientRect: () => bounds } as Element));
            }}
            oncontextmenu={(event) => {
              event.preventDefault();
              extensionMenu(session, space, action, event);
            }}>
            <ActionArtwork {action} size={17} />
          </button>
          <button type="button" class={["site-extension-pin", action.pinned && "pinned"]}
            aria-label={action.pinned ? `Unpin ${action.name}` : `Pin ${action.name}`} title={action.pinned ? "Unpin" : "Pin to Sidebar"}
            onclick={() => void change(session, space.id, action.id, action.pinned ? ExtensionChange.Unpin : ExtensionChange.Pin)
              .then(() => extensions.changedHere())}>
            <SymbolIcon name={action.pinned ? "pin.fill" : "pin"} size={9} />
          </button>
        </div>
      {/each}
    </div>
  {/if}
</div>
