<script lang="ts" module>
  import type { FolderState, TabState } from "@crest/contracts";

  /** A question the sidebar asks over the page, as the Mac's sidebar asks it in a dialog. */
  export type SidebarDialog =
    | { readonly kind: "deleteFolder"; readonly spaceId: string; readonly folder: FolderState }
    | { readonly kind: "renameTab"; readonly spaceId: string; readonly tab: TabState }
    | { readonly kind: "clearHistory"; readonly spaceId: string };

  /** Motion's own fade, which the backdrop came and went on: 0.3 s on its default curve. */
  const fading = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] } as const;
</script>

<script lang="ts">
  import type { Session } from "../boot";
  import { presence } from "../motion";
  import ClearSpaceHistory from "./ClearSpaceHistory.svelte";
  import DeleteFolder from "./DeleteFolder.svelte";
  import RenamePinnedTab from "./RenamePinnedTab.svelte";

  /**
   * The sidebar's question over the page, its backdrop fading in as it comes
   * and out as it goes, however the window puts it away; another question
   * asked meanwhile takes its place on the same backdrop.
   */
  let { session, dialog, onDone }: {
    session: Session;
    dialog: SidebarDialog | null;
    onDone: () => void;
  } = $props();
</script>

{#each dialog ? [dialog] : [] as shown ("sidebar-dialog")}
  <div class="sheet-backdrop" in:presence|global={{ pose: { opacity: 0 }, timing: fading }}
    out:presence|global={{ pose: { opacity: 0 }, timing: fading }}>
    {#if shown.kind === "deleteFolder"}
      <DeleteFolder {session} spaceId={shown.spaceId} folder={shown.folder} {onDone} />
    {:else if shown.kind === "renameTab"}
      <RenamePinnedTab {session} spaceId={shown.spaceId} tab={shown.tab} {onDone} />
    {:else}
      <ClearSpaceHistory {session} spaceId={shown.spaceId} {onDone} />
    {/if}
  </div>
{/each}
