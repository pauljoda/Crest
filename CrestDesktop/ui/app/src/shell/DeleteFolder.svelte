<script lang="ts" module>
  function contentsMessage(tabs: number, folders: number): string {
    const tabCount = `${tabs} ${tabs === 1 ? "tab" : "tabs"}`;
    const folderCount = `${folders} ${folders === 1 ? "folder" : "folders"}`;
    if (tabs === 0 && folders === 0) return "The folder is empty.";
    if (folders === 0) return `This also deletes the ${tabCount} inside it. Deleted tabs go to the Archive.`;
    if (tabs === 0) return `This also deletes the ${folders} empty ${folders === 1 ? "folder" : "folders"} inside it.`;
    return `This also deletes everything inside it: ${tabCount} and ${folderCount}. Deleted tabs go to the Archive.`;
  }
</script>

<script lang="ts">
  import { DeleteFolderAndContents, type FolderState, SelectionPreview } from "@crest/contracts";
  import { untrack } from "svelte";

  import type { Session } from "../boot";
  import { Sheet } from "./prompts/PromptSheet";
  import { send } from "./sidebar-menus";

  /** Deleting a folder deletes what it holds, so the person confirms, told what goes, as the Mac asks. */
  let { session, spaceId, folder, onDone }: {
    session: Session; spaceId: string; folder: FolderState; onDone: () => void;
  } = $props();

  let message = $state<string | null>(null);
  $effect(() => {
    const asked = { session, spaceId, folderId: folder.id };
    untrack(() => {
      void asked.session.core.query(SelectionPreview({
        workspaceId: asked.session.workspaceId, spaceId: asked.spaceId, tabIds: [], folderIds: [asked.folderId],
      }))
        .then((preview) => {
          message = contentsMessage(preview.members.length, Math.max(0, preview.folderIds.length - 1));
        })
        .catch(() => {
          message = "";
        });
    });
  });
</script>

<Sheet title={`Delete ${folder.title}?`} primary="Delete Folder" secondary="Cancel" warning destructive
  onPrimary={() => {
    void send(session, DeleteFolderAndContents({
      workspaceId: session.workspaceId, windowId: session.windowId, spaceId, folderId: folder.id,
    }));
    onDone();
  }}
  onEscape={onDone}>
  {#if message}
    <p class="sheet-message">{message}</p>
  {/if}
</Sheet>
