import {
  BrowsingDataRange,
  ClearHistory,
  DeleteFolderAndContents,
  type FolderState,
  RenameTab,
  SelectionPreview,
  type TabState,
} from "@crest/contracts";
import { motion } from "motion/react";
import { useEffect, useState } from "react";

import type { Session } from "../boot";
import { Sheet } from "./prompts/PromptSheet";
import { send } from "./sidebar-menus";

/** A question the sidebar asks over the page, as the Mac's sidebar asks it in a dialog. */
export type SidebarDialog =
  | { readonly kind: "deleteFolder"; readonly spaceId: string; readonly folder: FolderState }
  | { readonly kind: "renameTab"; readonly spaceId: string; readonly tab: TabState }
  | { readonly kind: "clearHistory"; readonly spaceId: string };

export function SidebarDialogLayer({ session, dialog, onDone }: {
  session: Session;
  dialog: SidebarDialog | null;
  onDone: () => void;
}) {
  if (!dialog) return null;
  return (
    <motion.div className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      {dialog.kind === "deleteFolder"
        ? <DeleteFolder session={session} spaceId={dialog.spaceId} folder={dialog.folder} onDone={onDone} />
        : dialog.kind === "renameTab"
          ? <RenamePinnedTab session={session} spaceId={dialog.spaceId} tab={dialog.tab} onDone={onDone} />
          : <ClearSpaceHistory session={session} spaceId={dialog.spaceId} onDone={onDone} />}
    </motion.div>
  );
}

/**
 * Clearing a Space's history can't be undone, so the person confirms, told
 * what it reaches: the group's shared history, or the Space's alone, as the
 * Mac's BrowserSidebarClearHistoryDialog asks. The question goes with the
 * Space it was asked about.
 */
function ClearSpaceHistory({ session, spaceId, onDone }: { session: Session; spaceId: string; onDone: () => void }) {
  const state = session.core.state;
  const workspace = state.workspaces.get(session.workspaceId);
  const space = workspace?.spaces.get(spaceId);
  const shown = state.windows.get(session.windowId)?.shownSpaceId === spaceId;
  useEffect(() => {
    if (!space || !shown) onDone();
  }, [space, shown, onDone]);
  if (!space || !workspace) return null;
  const primaryId = space.membership?.primaryId ?? space.id;
  const members = [...workspace.spaces.values()].filter((candidate) => candidate.id === primaryId || candidate.membership?.primaryId === primaryId);
  const primary = workspace.spaces.get(primaryId) ?? space;
  return (
    <Sheet title={`Clear history for ${space.settings.name}?`} primary="Clear History" secondary="Cancel" warning
      onPrimary={() => {
        void send(session, ClearHistory({ workspaceId: session.workspaceId, spaceId, range: BrowsingDataRange.allTime }));
        onDone();
      }}
      onEscape={onDone}>
      <p className="sheet-message">
        {members.length > 1 ? `This clears the history ${primary.settings.name} and its Sub-Spaces share.` : "History in other Spaces is not affected."}
      </p>
    </Sheet>
  );
}

/** Deleting a folder deletes what it holds, so the person confirms, told what goes, as the Mac asks. */
function DeleteFolder({ session, spaceId, folder, onDone }: {
  session: Session; spaceId: string; folder: FolderState; onDone: () => void;
}) {
  const [message, setMessage] = useState<string | null>(null);
  useEffect(() => {
    void session.core.query(SelectionPreview({ workspaceId: session.workspaceId, spaceId, tabIds: [], folderIds: [folder.id] }))
      .then((preview) => setMessage(contentsMessage(preview.members.length, Math.max(0, preview.folderIds.length - 1))))
      .catch(() => setMessage(""));
  }, [session, spaceId, folder.id]);
  return (
    <Sheet title={`Delete ${folder.title}?`} primary="Delete Folder" secondary="Cancel" warning
      onPrimary={() => {
        void send(session, DeleteFolderAndContents({
          workspaceId: session.workspaceId, windowId: session.windowId, spaceId, folderId: folder.id,
        }));
        onDone();
      }}
      onEscape={onDone}>
      {message && <p className="sheet-message">{message}</p>}
    </Sheet>
  );
}

function contentsMessage(tabs: number, folders: number): string {
  const tabCount = `${tabs} ${tabs === 1 ? "tab" : "tabs"}`;
  const folderCount = `${folders} ${folders === 1 ? "folder" : "folders"}`;
  if (tabs === 0 && folders === 0) return "The folder is empty.";
  if (folders === 0) return `This also deletes the ${tabCount} inside it. Deleted tabs go to the Archive.`;
  if (tabs === 0) return `This also deletes the ${folders} empty ${folders === 1 ? "folder" : "folders"} inside it.`;
  return `This also deletes everything inside it: ${tabCount} and ${folderCount}. Deleted tabs go to the Archive.`;
}

/** A pinned tile has no room for a field, so its rename asks in a dialog, as the Mac's does. */
function RenamePinnedTab({ session, spaceId, tab, onDone }: {
  session: Session; spaceId: string; tab: TabState; onDone: () => void;
}) {
  const [title, setTitle] = useState(tab.displayTitle);
  return (
    <Sheet title="Rename Tab" primary="Rename" secondary="Cancel"
      onPrimary={() => {
        void send(session, RenameTab({ workspaceId: session.workspaceId, spaceId, tabId: tab.id, title }));
        onDone();
      }}
      onEscape={onDone}>
      <input className="sheet-field" placeholder="Tab Name" aria-label="Tab Name" value={title}
        onChange={(event) => setTitle(event.target.value)} onFocus={(event) => event.currentTarget.select()} data-autofocus />
    </Sheet>
  );
}
