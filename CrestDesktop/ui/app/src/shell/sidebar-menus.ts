import {
  AddSubSpace,
  CanSend,
  ChooseTabIcon,
  ClearCurrentTabs,
  CloseTab,
  CloseTabs,
  CollapseAllFolders,
  CollapseFolder,
  CreateFolder,
  CreateSpace,
  DeleteFolder,
  DeleteTab,
  DeleteTabs,
  DuplicateTab,
  DuplicateTabs,
  ExpandSavedTabs,
  FileTabs,
  type FolderState,
  FolderTabs,
  type Intent,
  type SessionIntent,
  JoinSplit,
  KeepPageLoaded,
  KeepTabsLoaded,
  LeaveSplit,
  MoveFolder,
  MoveFolderToSpace,
  MoveTab,
  MoveTabsToSpace,
  MoveTabToSpace,
  RefreshPageIcon,
  ReleasePage,
  ReplaceSavedAddress,
  ReturnToSavedAddress,
  type SelectedTabs,
  SelectionPreview,
  SeparateSplits,
  SetFolderGroup,
  type SpaceState,
  SplitTabs,
  StepSplitMember,
  TabIconMode,
  TabPlacement,
  type TabSelection,
  type TabState,
  TabSurface,
  messageOfRejection,
  WebPagesOnly,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";

import type { Session } from "../boot";
import { openPalette, spaceEditing, toggleUtility } from "../commands";
import { CopiedLink } from "../copied-link";
import type { MenuEntry } from "../menus";
import { failureNotice, notices, urlCopiedNotice } from "../notices";
import { folderItem, type SelectionItem, tabItem } from "./sidebar-selection";

/** The color a new folder or group wears, the Mac's folderDefault (Slate). */
const folderDefault = { red: 0.43, green: 0.48, blue: 0.54, alpha: 1 };

/** What the sidebar's menus act on and how they reach the rest of the window. */
export interface SidebarContext {
  readonly session: Session;
  readonly space: SpaceState;
  readonly spaces: readonly SpaceState[];
  readonly shownTabId: string | null;
  /** Each tab's live page in this window, by tab. */
  readonly pagesByTab: ReadonlyMap<string, string>;
  /** Starts renaming a tab or folder in place. */
  readonly rename: (item: { readonly tabId: string } | { readonly folderId: string }) => void;
  /** Asks the person to confirm deleting a folder and what it holds. */
  readonly confirmDeleteFolder: (folder: FolderState) => void;
  /** Opens the popover that chooses a folder's emoji or colour, beside its row. */
  readonly chooseLook: (folder: FolderState, kind: "icon" | "color") => void;
  /** Opens the popover that chooses a tab's emoji, beside its row or tile. */
  readonly chooseTabIcon: (tab: TabState) => void;
  /** Adds a row to the selection, as Ctrl-click does, and selects every row. */
  readonly addToSelection: (item: SelectionItem) => void;
  readonly selectAll: () => void;
  /** Selects what a batch action leaves selected, given the copies it made by source. */
  readonly reselect: (how: Reselection, selected: SelectedTabs, copies: ReadonlyMap<string, string>) => void;
}

/**
 * What the selection holds once a batch action is done, as the Mac's
 * BrowserTabReselection: nothing, when the tabs left the list; the copies the
 * action made; or the same picks, a copy standing in for each source copied.
 */
export type Reselection = "cleared" | "copies" | "items";

/** Sends `intent`; a refusal changes nothing, as the Mac's sidebar ignores one. */
export function send(session: Session, intent: Intent): Promise<boolean> {
  return session.core.send(intent).then(() => true, (error: unknown) => {
    if (error instanceof CoreRejection) return false;
    throw error;
  });
}

/** Whether the core would take `intent` now. */
async function allows(session: Session, intent: SessionIntent): Promise<boolean> {
  try {
    return (await session.core.query(CanSend({ intent }))).refusal === null;
  } catch {
    return false;
  }
}

/** A folder's place as menus name it: its ancestors and itself, joined by ›. */
function folderPath(space: SpaceState, folder: FolderState): string {
  const names: string[] = [];
  for (let current: FolderState | undefined = folder; current; current = space.folders.find((f) => f.id === current!.parentId)) {
    names.unshift(current.title);
  }
  return names.join(" › ");
}

function selectionOf(tabId: string): TabSelection {
  return { tabIds: [tabId], folderIds: [], memberTabIds: [tabId] };
}

/**
 * The menu of a tab row, saved row, split member or pinned tile, as the Mac's
 * BrowserTabOrganizationMenuContent builds it.
 */
export async function tabMenu(context: SidebarContext, tab: TabState): Promise<MenuEntry[]> {
  const { session, space, spaces, shownTabId, pagesByTab } = context;
  const { workspaceId, windowId } = session;
  const spaceId = space.id;
  const placement = tab.placement;
  const isStartPage = tab.surface === TabSurface.startPage;
  const isWebPage = tab.surface === TabSurface.webPage;
  const isCurrent = placement === TabPlacement.current;
  const isSaved = placement === TabPlacement.saved;
  const isPinned = placement === TabPlacement.pinned;
  const pageId = pagesByTab.get(tab.id) ?? null;
  const isLoaded = pageId !== null;
  const otherSpaces = spaces.filter((candidate) => candidate.id !== spaceId);
  // The split the sidebar draws the tab in, by its members in order.
  const split = tab.splitGroupId
    ? space.sidebar.lists.flatMap((list) => list.rows).find((row) => row.kind.groupsTabs && row.members.includes(tab.id))
    : undefined;
  const [canSplit, ...spaceMoves] = await Promise.all([
    shownTabId && shownTabId !== tab.id
      ? allows(session, JoinSplit({ workspaceId, windowId, spaceId, tabId: tab.id, targetTabId: shownTabId, index: null }))
      : Promise.resolve(false),
    ...otherSpaces.map((destination) => allows(session, MoveTabToSpace({
      workspaceId, windowId, spaceId, tabId: tab.id, destinationSpaceId: destination.id, placement: null, folderId: null,
      beforeTabId: null,
    }))),
  ]);
  const move = (to: TabPlacement, folderId: string | null = null) => () =>
    void send(session, MoveTab({ workspaceId, spaceId, tabId: tab.id, placement: to, folderId, beforeTabId: null, leavesSplit: false }));
  const file = (folderId: string | null, before: { tabId: string | null; folderId: string | null } = { tabId: null, folderId: null }) =>
    () => void send(session, FileTabs({
      workspaceId, windowId, spaceId, selection: selectionOf(tab.id), placement: TabPlacement.current, folderId,
      beforeTabId: before.tabId, beforeFolderId: before.folderId, leavesSplits: false,
    }));
  const createFolder = (isGroup: boolean) => async () => {
    const folderId = crypto.randomUUID();
    const created = await send(session, CreateFolder({
      workspaceId, spaceId, folderId, placement: TabPlacement.current, parentId: null,
      title: isGroup ? "New Group" : "New Folder", color: folderDefault, symbol: "folder", tabIds: [tab.id],
      leavesSplits: false, isGroup,
    }));
    if (created && isGroup) context.rename({ folderId });
  };
  const groups = space.folders.filter((folder) => folder.isGroup && folder.location === TabPlacement.current);
  const currentFolders = space.folders.filter((folder) => !folder.isGroup && folder.location === TabPlacement.current);
  const savedFolders = space.folders.filter((folder) => folder.location === TabPlacement.saved);
  const savedAddress = (isSaved || isPinned) && tab.savedUrl !== null;

  const entries: MenuEntry[] = [];
  if (isWebPage) {
    entries.push({
      title: "Copy Link URL",
      enabled: !!tab.url,
      run: () => void copyLink(session, tab.url!),
    }, "separator");
  }
  entries.push({ title: "Rename Tab…", run: () => context.rename({ tabId: tab.id }) });
  // The tab's icon, as the Mac's BrowserTabIconActions: its page's icon
  // fetched again, its own icon cleared back to the page's, or an emoji.
  const iconItems: MenuEntry[] = [
    ...(tab.nativeContent === null ? [{
      title: "Pull New Icon", enabled: isLoaded,
      run: () => void session.core.request(RefreshPageIcon({ pageId: pageId! })).catch(() => undefined),
    }] : []),
    {
      title: "Clear Icon", enabled: !(tab.iconMode.followsPage && tab.faviconUrl === null),
      run: () => void send(session, ChooseTabIcon({ workspaceId, spaceId, tabId: tab.id, mode: TabIconMode.automatic, emoji: null, accent: null })),
    },
    { title: "Change Icon…", run: () => context.chooseTabIcon(tab) },
  ];
  if (savedAddress && !isStartPage) {
    const away = tab.isAwayFromSavedAddress;
    entries.push("separator", {
      title: "Edit Tab",
      submenu: [
        {
          title: "Replace with Current URL", enabled: away,
          run: () => void send(session, ReplaceSavedAddress({ workspaceId, spaceId, tabId: tab.id })),
        },
        {
          title: "Return to Saved URL", enabled: away,
          run: () => void send(session, ReturnToSavedAddress({ workspaceId, spaceId, tabId: tab.id })),
        },
        "separator",
        ...iconItems,
      ],
    }, "separator");
  } else {
    entries.push(...iconItems, "separator");
  }
  entries.push(isPinned
    ? { title: "Unpin Tab", run: move(TabPlacement.current) }
    : { title: "Pin Tab", run: move(TabPlacement.pinned) });
  if (isSaved) entries.push({ title: "Unsave Tab", run: move(TabPlacement.current) });
  else if (isCurrent && !isStartPage) entries.push({ title: "Save Tab", run: move(TabPlacement.saved) });
  if (isCurrent && !isStartPage) {
    entries.push({
      title: "Add to Group",
      submenu: [
        { title: "New Group", run: () => void createFolder(true)() },
        ...(groups.length > 0 ? ["separator" as const] : []),
        ...groups.map((group) => ({ title: group.title, enabled: tab.folderId !== group.id, run: file(group.id) })),
      ],
    }, {
      title: "Add to Current Tabs Folder",
      submenu: [
        { title: "New Folder", run: () => void createFolder(false)() },
        ...(currentFolders.length > 0 ? ["separator" as const] : []),
        ...currentFolders.map((folder) => ({
          title: folderPath(space, folder), enabled: tab.folderId !== folder.id, run: file(folder.id),
        })),
      ],
    });
    if (tab.folderId) {
      const folder = space.folders.find((candidate) => candidate.id === tab.folderId);
      entries.push({
        title: folder?.isGroup ? "Remove from Group" : "Remove from Folder",
        run: file(null, slotAfterOutermostFolder(space, tab.folderId)),
      });
    }
  }
  entries.push({
    title: "Save in Folder",
    submenu: [
      { title: "Saved Tabs", enabled: !(isSaved && tab.folderId === null), run: move(TabPlacement.saved) },
      ...(savedFolders.length > 0 ? ["separator" as const] : []),
      ...savedFolders.map((folder) => ({
        title: folderPath(space, folder), enabled: !(isSaved && tab.folderId === folder.id),
        run: move(TabPlacement.saved, folder.id),
      })),
    ],
  });
  if (isSaved) entries.push({ title: "Move to Current Tabs", run: move(TabPlacement.current) });
  if (otherSpaces.length > 0) {
    entries.push({
      title: "Move to Space",
      submenu: otherSpaces.map((destination, index) => ({
        title: destination.settings.name,
        enabled: spaceMoves[index],
        run: () => void send(session, MoveTabToSpace({
          workspaceId, windowId, spaceId, tabId: tab.id, destinationSpaceId: destination.id, placement: null,
          folderId: null, beforeTabId: null,
        })),
      })),
    });
  }
  entries.push("separator", {
    title: "Split with Current Tab", enabled: canSplit,
    run: () => void send(session, JoinSplit({ workspaceId, windowId, spaceId, tabId: tab.id, targetTabId: shownTabId!, index: null })),
  });
  if (split) {
    const index = split.members.indexOf(tab.id);
    entries.push(
      {
        title: "Move Left", enabled: index > 0,
        run: () => void send(session, StepSplitMember({ workspaceId, spaceId, tabId: tab.id, offset: -1 })),
      },
      {
        title: "Move Right", enabled: index >= 0 && index < split.members.length - 1,
        run: () => void send(session, StepSplitMember({ workspaceId, spaceId, tabId: tab.id, offset: 1 })),
      },
      { title: "Remove from Split", run: () => void send(session, LeaveSplit({ workspaceId, spaceId, tabId: tab.id })) },
    );
  }
  entries.push("separator");
  if (!tab.nativeContent) {
    entries.push({
      title: tab.keepsPageLoaded ? "Stop Keeping Loaded" : "Keep Loaded",
      run: () => void send(session, KeepPageLoaded({ workspaceId, spaceId, tabId: tab.id, keeps: !tab.keepsPageLoaded })),
    });
  }
  if (pageId && (!tab.nativeContent || !isCurrent)) {
    entries.push(isCurrent
      ? { title: "Unload Tab", run: () => void send(session, ReleasePage({ pageId, keepsState: true })) }
      : { title: "Close Tab", run: () => void send(session, CloseTab({ workspaceId, windowId, spaceId, tabId: tab.id, returnTabId: null })) });
  }
  entries.push({
    title: "Duplicate Tab",
    run: () => void send(session, DuplicateTab({ workspaceId, windowId, spaceId, tabId: tab.id, placement: null, shows: true })),
  });
  entries.push(isCurrent
    ? { title: "Close Tab", run: () => void send(session, CloseTab({ workspaceId, windowId, spaceId, tabId: tab.id, returnTabId: null })) }
    : { title: "Delete Tab", run: () => void send(session, DeleteTab({ workspaceId, windowId, spaceId, tabId: tab.id })) });
  entries.push(
    "separator",
    { title: "Add to Selection", run: () => context.addToSelection(tabItem(tab.id)) },
    { title: "Select All Tabs", run: context.selectAll },
  );
  return entries;
}

/**
 * The menu of a folder or group header, as the Mac's
 * BrowserFolderOrganizationMenuContent builds it. The icon and color
 * pickers wait for Windows' pickers.
 */
export async function folderMenu(context: SidebarContext, folder: FolderState): Promise<MenuEntry[]> {
  const { session, space, spaces } = context;
  const { workspaceId, windowId } = session;
  const spaceId = space.id;
  const isGroup = folder.isGroup;
  const isCurrent = folder.location === TabPlacement.current;
  const nestedId = crypto.randomUUID();
  const nested = CreateFolder({
    workspaceId, spaceId, folderId: nestedId, placement: folder.location, parentId: folder.id, title: "New Folder",
    color: folderDefault, symbol: "folder", tabIds: [], leavesSplits: false, isGroup: false,
  });
  const convert = SetFolderGroup({ workspaceId, spaceId, folderId: folder.id, isGroup: !isGroup });
  const preview = await session.core.query(SelectionPreview({ workspaceId, spaceId, tabIds: [], folderIds: [folder.id] }))
    .catch(() => null);
  const archive = preview && preview.members.length > 0
    ? CloseTabs({ workspaceId, windowId, spaceId, selection: { tabIds: preview.members.map((member) => member.id), folderIds: [], memberTabIds: preview.members.map((member) => member.id) } })
    : null;
  // A folder may move under any folder of a section that holds folders but
  // itself and what it holds; the core refuses what it would not take.
  const descendants = new Set<string>([folder.id]);
  for (let grew = true; grew;) {
    grew = false;
    for (const candidate of space.folders) {
      if (candidate.parentId && descendants.has(candidate.parentId) && !descendants.has(candidate.id)) {
        descendants.add(candidate.id);
        grew = true;
      }
    }
  }
  const destinations = space.folders.filter((candidate) => !candidate.isGroup && !descendants.has(candidate.id));
  const [canNest, canConvert, canArchive, ...moves] = await Promise.all([
    isGroup ? Promise.resolve(false) : allows(session, nested),
    isCurrent ? allows(session, convert) : Promise.resolve(false),
    archive ? allows(session, archive) : Promise.resolve(false),
    ...destinations.map((destination) => allows(session, MoveFolder({
      workspaceId, spaceId, folderId: folder.id, placement: destination.location, parentId: destination.id,
      beforeFolderId: null, beforeTabId: null,
    }))),
  ]);
  const sectionName = (placement: TabPlacement) => (placement === TabPlacement.saved ? "Saved Tabs" : "Current Tabs");

  const entries: MenuEntry[] = [];
  if (!isGroup) {
    entries.push({
      title: "New Nested Folder", enabled: canNest,
      run: async () => {
        if (!(await send(session, nested))) return;
        if (folder.isCollapsed) await send(session, CollapseFolder({ workspaceId, spaceId, folderId: folder.id, collapsed: false }));
        context.rename({ folderId: nestedId });
      },
    });
  }
  entries.push({ title: isGroup ? "Rename Group" : "Rename Folder", run: () => context.rename({ folderId: folder.id }) });
  // A folder wears a drawn icon a group doesn't; both wear a colour.
  if (!isGroup) entries.push({ title: "Folder Icon…", run: () => context.chooseLook(folder, "icon") });
  entries.push({ title: isGroup ? "Group Color…" : "Folder Color…", run: () => context.chooseLook(folder, "color") });
  if (isCurrent) {
    entries.push({ title: isGroup ? "Convert to Folder" : "Convert to Group", enabled: canConvert, run: () => void send(session, convert) });
  }
  entries.push(isCurrent
    ? {
      title: isGroup ? "Move to Saved Tabs as Folder" : "Move to Saved Tabs",
      run: () => void send(session, MoveFolder({
        workspaceId, spaceId, folderId: folder.id, placement: TabPlacement.saved, parentId: null, beforeFolderId: null,
        beforeTabId: null,
      })),
    }
    : {
      title: "Move to Current Tabs",
      run: () => void send(session, MoveFolder({
        workspaceId, spaceId, folderId: folder.id, placement: TabPlacement.current, parentId: null, beforeFolderId: null,
        beforeTabId: null,
      })),
    });
  if (!isGroup) {
    entries.push({
      title: "Move to Folder",
      submenu: [
        {
          title: "Top Level", enabled: folder.parentId !== null,
          run: () => void send(session, MoveFolder({
            workspaceId, spaceId, folderId: folder.id, placement: null, parentId: null, beforeFolderId: null, beforeTabId: null,
          })),
        },
        ...(destinations.length > 0 ? ["separator" as const] : []),
        ...destinations.flatMap((destination, index) => moves[index]
          ? [{
            title: `${sectionName(destination.location)} › ${folderPath(space, destination)}`,
            enabled: folder.parentId !== destination.id,
            run: () => void send(session, MoveFolder({
              workspaceId, spaceId, folderId: folder.id, placement: destination.location, parentId: destination.id,
              beforeFolderId: null, beforeTabId: null,
            })),
          }]
          : []),
      ],
    });
  }
  const otherSpaces = spaces.filter((candidate) => candidate.id !== spaceId);
  if (otherSpaces.length > 0) {
    entries.push({
      title: "Move to Space",
      submenu: otherSpaces.map((destination) => ({
        title: destination.settings.name,
        run: () => void send(session, MoveFolderToSpace({ workspaceId, windowId, spaceId, folderId: folder.id, destinationSpaceId: destination.id })),
      })),
    });
  }
  if (isCurrent) {
    entries.push("separator", { title: "Archive Tabs", enabled: canArchive, run: () => archive && void send(session, archive) });
  }
  entries.push("separator", isGroup
    ? { title: "Ungroup", run: () => void send(session, DeleteFolder({ workspaceId, spaceId, folderId: folder.id })) }
    : { title: "Delete Folder", run: () => context.confirmDeleteFolder(folder) });
  entries.push(
    "separator",
    { title: "Add to Selection", run: () => context.addToSelection(folderItem(folder.id)) },
    { title: "Select All Items", run: context.selectAll },
  );
  return entries;
}

/**
 * The selection's actions as one intent each, with what each leaves
 * selected, as the Mac's BrowserTabBatch makes them.
 */
export function batchIntents(session: Session, spaceId: string, selection: TabSelection) {
  const { workspaceId, windowId } = session;
  return {
    copying: DuplicateTabs({ workspaceId, windowId, spaceId, selection }),
    closing: CloseTabs({ workspaceId, windowId, spaceId, selection }),
    deleting: DeleteTabs({ workspaceId, windowId, spaceId, selection }),
    releasing: KeepTabsLoaded({ workspaceId, windowId, spaceId, selection, keeps: false }),
  };
}

/**
 * Performs a batch action and selects what it leaves selected, as the Mac's
 * BrowserTabBatchActions does; a refusal tells the person why in a notice.
 */
export async function performBatch(context: SidebarContext, selected: SelectedTabs, intent: SessionIntent,
  reselection: Reselection): Promise<boolean> {
  try {
    const changes = await context.session.core.send(intent);
    const copies = new Map(changes.flatMap((change) =>
      change.$kind === "TabCopied" && change.workspaceId === context.session.workspaceId
        ? [[change.sourceTabId, change.copyTabId] as const] : []));
    context.reselect(reselection, selected, copies);
    return true;
  } catch (error) {
    if (!(error instanceof CoreRejection)) throw error;
    notices.post(failureNotice(messageOfRejection(error.rejection) ?? "Crest couldn’t do that."));
    return false;
  }
}

/** Why the core would refuse `intent` now, in its own words, or null when it would take it. */
async function refusalOf(session: Session, intent: SessionIntent): Promise<string | null> {
  try {
    const refusal = (await session.core.query(CanSend({ intent }))).refusal;
    return refusal ? messageOfRejection(refusal) ?? "Crest couldn’t do that." : null;
  } catch {
    return "Crest couldn’t do that.";
  }
}

/**
 * Copies the selected pages' addresses, one a line, each as Super Copy
 * leaves it, when every selected tab is a page, as the Mac's copyLinks does.
 */
export async function copySelectedLinks(context: SidebarContext, selected: SelectedTabs) {
  const { session, space } = context;
  if (!session.shell) return;
  const refused = await refusalOf(session, batchIntents(session, space.id, selected.selection).releasing);
  if (refused) {
    notices.post(failureNotice(refused));
    return;
  }
  const urls: string[] = [];
  for (const member of selected.members) {
    const tab = space.tabs.find((candidate) => candidate.id === member.id);
    if (!tab?.url || tab.surface !== TabSurface.webPage) {
      notices.post(failureNotice(messageOfRejection(WebPagesOnly({ tabId: member.id }))!));
      return;
    }
    urls.push(tab.url);
  }
  const links = await Promise.all(urls.map((url) => CopiedLink.of(session.core, url)));
  await session.shell.copy(links.map((link) => link.url).join("\n"));
  notices.post(urlCopiedNotice);
}

/**
 * The menu of an engaged selection, as the Mac's BrowserTabBatchMenu builds
 * it: what the selection holds, then what moves, keeps, copies, archives or
 * deletes it, each offered only when the core would take it.
 */
export async function batchMenu(context: SidebarContext, selected: SelectedTabs): Promise<MenuEntry[]> {
  const { session, space, spaces, pagesByTab } = context;
  const { workspaceId, windowId } = session;
  const spaceId = space.id;
  const selection = selected.selection;
  const members = selected.members;
  const count = members.length;
  const hasFolders = selection.folderIds.length > 0;
  const file = (placement: TabPlacement, folderId: string | null = null) =>
    FileTabs({ workspaceId, windowId, spaceId, selection, placement, folderId, beforeTabId: null, beforeFolderId: null, leavesSplits: false });
  const folderTabs = (placement: TabPlacement, isGroup: boolean) =>
    FolderTabs({ workspaceId, windowId, spaceId, selection, placement, title: isGroup ? "New Group" : "New Folder", isGroup });
  const otherSpaces = spaces.filter((candidate) => candidate.id !== spaceId);
  const groups = space.folders.filter((folder) => folder.isGroup && folder.location === TabPlacement.current);
  const plainFolders = space.folders.filter((folder) => !folder.isGroup && !selection.folderIds.includes(folder.id));
  const ordered = [
    ...plainFolders.filter((folder) => folder.location === TabPlacement.saved),
    ...plainFolders.filter((folder) => folder.location !== TabPlacement.saved),
  ];
  const batch = batchIntents(session, spaceId, selection);

  const intents = {
    pin: file(TabPlacement.pinned),
    save: file(TabPlacement.saved),
    current: file(TabPlacement.current),
    newGroup: folderTabs(TabPlacement.current, true),
    newCurrentFolder: folderTabs(TabPlacement.current, false),
    newSavedFolder: folderTabs(TabPlacement.saved, false),
    split: SplitTabs({ workspaceId, windowId, spaceId, selection, targetTabId: null, index: null }),
    separate: SeparateSplits({ workspaceId, windowId, spaceId, selection }),
    keep: KeepTabsLoaded({ workspaceId, windowId, spaceId, selection, keeps: true }),
    release: batch.releasing,
    duplicate: batch.copying,
    archive: batch.closing,
    delete: batch.deleting,
  };
  const names = Object.keys(intents) as (keyof typeof intents)[];
  const groupFiles = groups.map((group) => file(TabPlacement.current, group.id));
  const folderFiles = ordered.map((folder) => file(folder.location, folder.id));
  const spaceMoves = otherSpaces.map((destination) =>
    MoveTabsToSpace({ workspaceId, windowId, spaceId, selection, destinationSpaceId: destination.id }));
  const allowed = await Promise.all([...names.map((name) => allows(session, intents[name])),
    ...groupFiles.map((intent) => allows(session, intent)),
    ...folderFiles.map((intent) => allows(session, intent)),
    ...spaceMoves.map((intent) => allows(session, intent))]);
  const can = Object.fromEntries(names.map((name, index) => [name, allowed[index]])) as Record<keyof typeof intents, boolean>;
  const canGroup = allowed.slice(names.length, names.length + groupFiles.length);
  const canFolder = allowed.slice(names.length + groupFiles.length, names.length + groupFiles.length + folderFiles.length);
  const canSpace = allowed.slice(names.length + groupFiles.length + folderFiles.length);
  const act = (intent: SessionIntent, reselection: Reselection = "items") => () =>
    void performBatch(context, selected, intent, reselection);
  // A new group's name starts editing once the selection is in it.
  const newGroup = async () => {
    const before = new Set(space.folders.map((folder) => folder.id));
    try {
      const changes = await session.core.send(intents.newGroup);
      context.reselect("items", selected, new Map());
      const made = changes.flatMap((change) => (change.$kind === "FoldersChanged" ? change.updated : []))
        .find((folder) => folder.isGroup && !before.has(folder.id));
      if (made) context.rename({ folderId: made.id });
    } catch (error) {
      if (!(error instanceof CoreRejection)) throw error;
      notices.post(failureNotice(messageOfRejection(error.rejection) ?? "Crest couldn’t do that."));
    }
  };
  const newFolders: MenuEntry[] = [
    { title: "New Current Tabs Folder", enabled: can.newCurrentFolder, run: act(intents.newCurrentFolder) },
    { title: "New Saved Folder", enabled: can.newSavedFolder, run: act(intents.newSavedFolder) },
  ];
  // Each folder by its own name and its ancestors', as the Mac's batch menu names them.
  const folderEntries = ordered.map((folder, index) => ({
    title: folderPath(space, folder),
    enabled: canFolder[index], run: act(folderFiles[index]),
  }));

  if (hasFolders) {
    const items = selected.roots.length;
    return [
      { title: items === 1 ? "1 item selected" : `${items} items selected`, enabled: false, run: () => {} },
      "separator",
      { title: "Move to Current Tabs", enabled: can.current, run: act(intents.current) },
      { title: "Move to Saved Tabs", enabled: can.save, run: act(intents.save) },
      { title: "Move to Folder", submenu: [...newFolders, ...folderEntries] },
      "separator",
      { title: "Select All Items", run: context.selectAll },
      { title: "Deselect All", run: () => context.reselect("cleared", selected, new Map()) },
    ];
  }

  const counted = (title: string) => (count === 1 ? `${title} Tab` : `${title} ${count} Tabs`);
  const entries: MenuEntry[] = [
    { title: count === 1 ? "1 tab selected" : `${count} tabs selected`, enabled: false, run: () => {} },
    "separator",
    { title: "Copy Link URLs", run: () => void copySelectedLinks(context, selected) },
    "separator",
  ];
  // Pinned tabs alone are unpinned, and saved tabs alone unsaved; any other
  // selection may hold tabs to pin or save.
  if (members.every((member) => member.placement === TabPlacement.pinned)) {
    entries.push({ title: counted("Unpin"), enabled: can.current, run: act(intents.current) });
  } else if (members.every((member) => member.placement === TabPlacement.saved)) {
    entries.push({ title: counted("Pin"), enabled: can.pin, run: act(intents.pin) },
      { title: counted("Unsave"), enabled: can.current, run: act(intents.current) });
  } else {
    entries.push({ title: counted("Pin"), enabled: can.pin, run: act(intents.pin) },
      { title: counted("Save"), enabled: can.save, run: act(intents.save) },
      { title: "Move to Current Tabs", enabled: can.current, run: act(intents.current) });
  }
  entries.push({
    title: "Move to Group",
    submenu: [
      { title: "New Group", enabled: can.newGroup, run: () => void newGroup() },
      ...groups.map((group, index) => ({ title: group.title, enabled: canGroup[index], run: act(groupFiles[index]) })),
    ],
  }, {
    title: "Move to Folder",
    submenu: [...newFolders, { title: "Saved Tabs", enabled: can.save, run: act(intents.save) }, ...folderEntries],
  });
  if (otherSpaces.length > 0) {
    entries.push({
      title: "Move to Space",
      submenu: otherSpaces.map((destination, index) => ({
        title: destination.settings.name, enabled: canSpace[index], run: act(spaceMoves[index], "cleared"),
      })),
    });
  }
  entries.push({ title: "Combine in Split View", enabled: can.split, run: act(intents.split) });
  if (members.some((member) => member.splitGroupId)) {
    entries.push({ title: "Separate Selected Splits", enabled: can.separate, run: act(intents.separate) });
  }
  entries.push(
    "separator",
    { title: "Keep Pages Loaded", enabled: can.keep, run: act(intents.keep) },
    { title: "Stop Keeping Pages Loaded", enabled: can.release, run: act(intents.release) },
    { title: `Duplicate ${count} Tabs`, enabled: can.duplicate, run: act(intents.duplicate, "copies") },
    {
      // Each selected tab's page goes, and the selection with them.
      title: `Unload ${count} Pages`, enabled: can.release,
      run: () => {
        for (const member of members) {
          const pageId = pagesByTab.get(member.id);
          if (pageId) void send(session, ReleasePage({ pageId, keepsState: true }));
        }
        context.reselect("cleared", selected, new Map());
      },
    },
    { title: "Archive Selected Tabs", enabled: can.archive, run: act(intents.archive, "cleared") },
    { title: `Delete ${count} Tabs`, enabled: can.delete, run: act(intents.delete, "cleared") },
    "separator",
    { title: "Select All Tabs", run: context.selectAll },
    { title: "Deselect All", run: () => context.reselect("cleared", selected, new Map()) },
  );
  return entries;
}

/** The Space header's actions, as the Mac's BrowserSpaceHeaderActionsMenu lists them on the Mac. */
export function spaceHeaderMenu(context: SidebarContext): MenuEntry[] {
  const { session, space } = context;
  const { workspaceId, windowId } = session;
  const spaceId = space.id;
  const hasOpenFolder = space.folders.some((folder) => !folder.isCollapsed);
  return [
    { title: "New Tab", run: () => openPalette("newTab") },
    { title: "New Folder", run: () => void newSavedFolder(context) },
    {
      title: "Collapse All Folders", enabled: hasOpenFolder,
      run: () => void send(session, CollapseAllFolders({ workspaceId, spaceId })),
    },
    { title: "Show History", run: () => toggleUtility("history") },
    { title: "Clear Other Tabs", run: () => void send(session, ClearCurrentTabs({ workspaceId, windowId, spaceId, keepsShownTab: true })) },
    { title: "Clear All Tabs", run: () => void send(session, ClearCurrentTabs({ workspaceId, windowId, spaceId, keepsShownTab: false })) },
  ];
}

/** The menu of the sidebar's empty area, as the Mac's BrowserSidebarBackgroundAction lists it. */
export async function backgroundMenu(context: SidebarContext): Promise<MenuEntry[]> {
  const { session, space } = context;
  const { workspaceId, windowId } = session;
  const collapse = CollapseAllFolders({ workspaceId, spaceId: space.id });
  // A new Space goes last and the window shows it; a Sub-Space follows this one and shares its sign-ins.
  const newSpace = CreateSpace({ workspaceId, windowId, spaceId: crypto.randomUUID() });
  const subSpace = AddSubSpace({ workspaceId, windowId, spaceId: crypto.randomUUID(), fromSpaceId: space.id });
  const [canCollapse, canCreate, canAddSubSpace] = await Promise.all([
    allows(session, collapse), allows(session, newSpace), allows(session, subSpace),
  ]);
  return [
    // The Mac edits a Space in its own sheet; Windows edits it on its page in Settings.
    { title: "Edit Space…", run: () => spaceEditing.open(space.id) },
    { title: "Collapse All Folders", enabled: canCollapse, run: () => void send(session, collapse) },
    // A new Space opens for editing, as the Mac's does, once the core has made it.
    ...(canCreate ? [{
      title: "New Space…",
      run: () => void send(session, newSpace).then((made) => made && spaceEditing.open(newSpace.spaceId)),
    }] : []),
    ...(canAddSubSpace ? [{ title: "New Sub-Space", run: () => void send(session, subSpace) }] : []),
  ];
}

/** A new saved folder from the Space header: Saved Tabs opens, and the folder's name is ready to type. */
async function newSavedFolder(context: SidebarContext) {
  const { session, space } = context;
  const folderId = crypto.randomUUID();
  const created = await send(session, CreateFolder({
    workspaceId: session.workspaceId, spaceId: space.id, folderId, placement: TabPlacement.saved, parentId: null,
    title: "New Folder", color: folderDefault, symbol: "folder", tabIds: [], leavesSplits: false, isGroup: false,
  }));
  if (!created) return;
  await send(session, ExpandSavedTabs({ workspaceId: session.workspaceId, spaceId: space.id, isExpanded: true }));
  context.rename({ folderId });
}

/** The row after the outermost folder holding `folderId`, in the current tabs' top level, where a tab leaving the folder lands. */
function slotAfterOutermostFolder(space: SpaceState, folderId: string): { tabId: string | null; folderId: string | null } {
  let outermost = space.folders.find((folder) => folder.id === folderId);
  while (outermost?.parentId) outermost = space.folders.find((folder) => folder.id === outermost!.parentId);
  const top = space.sidebar.lists.find((list) => list.section === TabPlacement.current && list.folderId === null);
  if (!outermost || !top) return { tabId: null, folderId: null };
  const index = top.rows.findIndex((row) => row.id === outermost!.id);
  const next = index >= 0 ? top.rows[index + 1] : undefined;
  if (!next) return { tabId: null, folderId: null };
  if (next.kind.name === "folder") return { tabId: null, folderId: next.id };
  return { tabId: next.kind.groupsTabs ? next.members[0] ?? null : next.id, folderId: null };
}

async function copyLink(session: Session, url: string) {
  if (!session.shell) return;
  const link = await CopiedLink.of(session.core, url);
  await session.shell.copy(link.url);
  notices.post(urlCopiedNotice);
}
