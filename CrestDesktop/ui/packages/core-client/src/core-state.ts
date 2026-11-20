import {
  type AppPreferences,
  AppPreferencesStatics,
  type ArchivedTabState,
  type AuthenticationAsked,
  type Change,
  type DownloadApprovalAsked,
  type DownloadDestinationAsked,
  type DownloadState,
  type EngineRoster,
  type ExtensionInstallAsked,
  type ExtensionInstallState,
  type FilterLists,
  type FolderState,
  type HistoryEntryState,
  type InstalledExtension,
  type LinkPreferences,
  type PageState,
  type PermissionAsked,
  type ScriptDialogAsked,
  type SearchCatalogChanged,
  type SessionState,
  type ShortcutsChanged,
  type SidebarList,
  type SiteContentBlocking,
  type SitePermissionRecordState,
  type SpaceState,
  type SplitGroupState,
  type TabState,
  type TransientPageClosed,
  type TransientPagePromoted,
  type WebsiteDataRead,
  type WindowState,
  type WorkspaceKind,
} from "@crest/contracts";

/** One workspace the core keeps open: the persistent session, private browsing, a borrowed one. */
export interface WorkspaceModel {
  readonly id: string;
  readonly kind: WorkspaceKind;
  readonly spaces: ReadonlyMap<string, SpaceState>;
  readonly order: readonly string[];
  readonly defaultSpaceId: string | null;
  /** The app's preferences, kept by the workspace that keeps them, or the defaults elsewhere. */
  readonly appPreferences: AppPreferences;
}

/** A question about a page that waits on the person until the core settles it. */
export type PagePrompt = ScriptDialogAsked | AuthenticationAsked | PermissionAsked;

/** A question about a download that waits until the core settles it. */
export type DownloadPrompt = DownloadApprovalAsked | DownloadDestinationAsked;

type ChangeOf<K extends Change["$kind"]> = Extract<Change, { $kind: K }>;

/**
 * What each change does to the read model. The map is typed over every
 * change, so a change the core gains does not compile until it says what it
 * does here, as Swift's generated `Change.apply(to:)` requires of its cases.
 */
type ChangeAppliers = { readonly [K in Change["$kind"]]: (state: CoreState, change: ChangeOf<K>) => void };

/** Changes that only a prompt, a feature not built yet, or the platform's services read. */
const unread = () => {};

/**
 * The interface's read model, which only the core's changes update. Each
 * entity is replaced, never edited, so a view that holds one sees exactly the
 * value it rendered, and `version` advances once for each batch applied.
 */
export class CoreState {
  workspaces = new Map<string, WorkspaceModel>();
  windows = new Map<string, WindowState>();
  pages = new Map<string, PageState>();
  /** The questions about pages that wait on the person, by prompt, in the order asked. */
  prompts = new Map<string, PagePrompt>();
  /** Every profile's downloads, in the core's order, newest first. */
  downloads: readonly DownloadState[] = [];
  /** The questions about downloads that wait, by prompt, in the order asked. */
  downloadPrompts = new Map<string, DownloadPrompt>();
  engines: EngineRoster | null = null;
  /** The keys each command this device offers answers to, in catalog order. */
  shortcuts: ShortcutsChanged | null = null;
  /** The search providers the device offers and the defaults its Spaces follow. */
  search: SearchCatalogChanged | null = null;
  /** How links open on this device: Peek, Quick Windows, routes and the link behaviours Settings shows. */
  links: LinkPreferences | null = null;
  /** Advances with every change to any Space's site permission choices, which the core answers by question. */
  sitePermissionRevision = 0;
  /** The extensions each profile's engine lists, by profile, as the core last published them. */
  installedExtensions = new Map<string, readonly InstalledExtension[]>();
  /** Each extension install, by install, as it last moved on. */
  extensionInstalls = new Map<string, ExtensionInstallState>();
  /** The questions about installs that wait on the person, by prompt. */
  extensionPrompts = new Map<string, ExtensionInstallAsked>();
  /** Ad blocking's level, its filter lists, the person's own lists and filters, as the core last published them. */
  filterLists: FilterLists | null = null;
  /** The sites where ad blocking blocks nothing, with the Space that turned each off. */
  blockingSites: readonly SiteContentBlocking[] = [];
  /** The choices each Space keeps for sites, by Space, as the core last published them. */
  sitePermissions = new Map<string, readonly SitePermissionRecordState[]>();
  /** The sites each read of website data found, by its request. */
  websiteDataReads = new Map<string, WebsiteDataRead>();
  /** Whether each data deletion the core finished erased everything, by its request. */
  deletions = new Map<string, boolean>();
  /** How each transient page, a Peek's or a Quick Window's, ended: kept as a tab, or closed by its page or engine. */
  transientOutcomes = new Map<string, TransientPagePromoted | TransientPageClosed>();
  version = 0;

  #listeners = new Set<() => void>();

  /** Applies a batch the core published, in order, then tells the listeners once. */
  apply(changes: readonly Change[]): void {
    if (changes.length === 0) return;
    for (const change of changes) (appliers[change.$kind] as (state: CoreState, change: Change) => void)(this, change);
    this.version++;
    for (const listener of this.#listeners) listener();
  }

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  space(workspaceId: string, spaceId: string): SpaceState | undefined {
    return this.workspaces.get(workspaceId)?.spaces.get(spaceId);
  }

  replaceSpace(workspaceId: string, spaceId: string, edit: (space: SpaceState) => SpaceState): void {
    const workspace = this.workspaces.get(workspaceId);
    const space = workspace?.spaces.get(spaceId);
    if (!workspace || !space) return;
    const spaces = new Map(workspace.spaces);
    spaces.set(spaceId, edit(space));
    this.workspaces.set(workspaceId, { ...workspace, spaces });
  }

  openSession(workspaceId: string, kind: WorkspaceKind, session: SessionState): void {
    this.workspaces.set(workspaceId, {
      id: workspaceId,
      kind,
      spaces: new Map(session.spaces.map((space) => [space.id, space])),
      order: session.spaces.map((space) => space.id),
      defaultSpaceId: session.defaultSpaceId,
      appPreferences: session.appPreferences ?? AppPreferencesStatics.default,
    });
  }
}

/**
 * A collection after a change that names what it updated and removed, and
 * maybe a new order. An updated item keeps its place; a new one goes last, or
 * first, newest first, where the collection `prepends` as a history does.
 */
function reconcile<T>(current: readonly T[], updated: readonly T[], removed: readonly string[],
  order: readonly string[] | null, idOf: (item: T) => string = (item) => (item as { readonly id: string }).id, prepends = false): T[] {
  const byId = new Map(current.map((item) => [idOf(item), item]));
  for (const id of removed) byId.delete(id);
  for (const item of updated) byId.set(idOf(item), item);
  const sequence = order ?? (prepends
    ? [...updated.map(idOf), ...current.map(idOf)]
    : [...current.map(idOf), ...updated.map(idOf)]);
  const seen = new Set<string>();
  const result: T[] = [];
  for (const id of sequence) {
    const item = byId.get(id);
    if (item && !seen.has(id)) {
      seen.add(id);
      result.push(item);
    }
  }
  return result;
}

const appliers: ChangeAppliers = {
  WorkspaceOpened: (state, change) => state.openSession(change.workspaceId, change.kind, change.session),
  WorkspaceClosed: (state, change) => void state.workspaces.delete(change.workspaceId),
  WorkspaceChanged: (state, change) => {
    const workspace = state.workspaces.get(change.workspaceId);
    if (workspace) state.workspaces.set(change.workspaceId, { ...workspace, defaultSpaceId: change.defaultSpaceId });
  },
  SpacesChanged: (state, change) => {
    const workspace = state.workspaces.get(change.workspaceId);
    if (!workspace) return;
    const spaces = new Map(workspace.spaces);
    for (const id of change.removed) spaces.delete(id);
    for (const space of change.added) spaces.set(space.id, space);
    const order = (change.order ?? [...workspace.order, ...change.added.map((space) => space.id)]).filter(
      (id, index, all) => spaces.has(id) && all.indexOf(id) === index);
    state.workspaces.set(change.workspaceId, { ...workspace, spaces, order });
  },
  SpaceSettingsChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => ({ ...space, settings: change.settings })),
  TabsChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => ({
      ...space,
      tabs: reconcile<TabState>(space.tabs, change.updated, change.removed, change.order),
    })),
  FoldersChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => ({
      ...space,
      folders: reconcile<FolderState>(space.folders, change.updated, change.removed, change.order),
    })),
  // Each list replaces the list of its section's top level or its folder's
  // inside, the lists of removed folders go, and every other list stays.
  SidebarChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => {
      const key = (list: SidebarList) => `${list.section.name}|${list.folderId ?? ""}`;
      const removed = new Set(change.removedFolderIds);
      const incoming = new Map(change.lists.map((list) => [key(list), list]));
      const lists = space.sidebar.lists
        .filter((list) => !(list.folderId && removed.has(list.folderId)))
        .map((list) => incoming.get(key(list)) ?? list);
      const kept = new Set(lists.map(key));
      for (const list of change.lists) if (!kept.has(key(list))) lists.push(list);
      return { ...space, sidebar: { lists } };
    }),
  SplitGroupsChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => ({
      ...space,
      splitGroups: change.groups as readonly SplitGroupState[],
    })),
  // An archived tab replaces its entry where it stands, or goes last.
  ArchiveChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => ({
      ...space,
      archivedTabs: reconcile<ArchivedTabState>(space.archivedTabs, change.archived, change.removed, change.order, (entry) => entry.tab.id),
    })),
  // Recorded entries, newest first, replace theirs and go before every other.
  HistoryChanged: (state, change) =>
    state.replaceSpace(change.workspaceId, change.spaceId, (space) => ({
      ...space,
      history: reconcile<HistoryEntryState>(space.history, change.recorded, change.removed, change.order, undefined, true),
    })),
  WindowChanged: (state, change) => void state.windows.set(change.window.id, change.window),
  WindowClosed: (state, change) => void state.windows.delete(change.windowId),
  PageOpened: (state, change) => void state.pages.set(change.page.id, change.page),
  PageChanged: (state, change) => void state.pages.set(change.page.id, change.page),
  PageRemoved: (state, change) => void state.pages.delete(change.pageId),
  EnginesChanged: (state, change) => {
    state.engines = change.roster;
  },
  ScriptDialogAsked: (state, change) => void state.prompts.set(change.promptId, change),
  AuthenticationAsked: (state, change) => void state.prompts.set(change.promptId, change),
  PermissionAsked: (state, change) => void state.prompts.set(change.promptId, change),
  PromptSettled: (state, change) => {
    state.prompts.delete(change.promptId);
    state.downloadPrompts.delete(change.promptId);
  },
  DownloadUpdated: (state, change) => {
    const index = state.downloads.findIndex((download) => download.id === change.download.id);
    const downloads = [...state.downloads];
    if (index >= 0) downloads[index] = change.download;
    else downloads.splice(Math.min(Math.max(change.position, 0), downloads.length), 0, change.download);
    state.downloads = downloads;
  },
  DownloadsRemoved: (state, change) => {
    const removed = new Set(change.downloadIds);
    state.downloads = state.downloads.filter((download) => !removed.has(download.id));
  },
  DownloadApprovalAsked: (state, change) => void state.downloadPrompts.set(change.promptId, change),
  DownloadDestinationAsked: (state, change) => void state.downloadPrompts.set(change.promptId, change),
  ShortcutsChanged: (state, change) => {
    state.shortcuts = change;
  },
  SearchCatalogChanged: (state, change) => {
    state.search = change;
  },
  SitePermissionsChanged: (state, change) => {
    state.sitePermissionRevision++;
    state.sitePermissions.set(change.spaceId, change.records);
  },
  DataDeleted: (state, change) => void state.deletions.set(change.requestId, change.deleted),

  AgentPreferencesChanged: unread,
  AgentSessionsChanged: unread,
  AppPreferencesChanged: (state, change) => {
    const workspace = state.workspaces.get(change.workspaceId);
    if (workspace) {
      state.workspaces.set(change.workspaceId, { ...workspace, appPreferences: change.preferences ?? AppPreferencesStatics.default });
    }
  },
  CloseReady: unread,
  CloudMergeBegan: unread,
  CloudSyncAdvanced: unread,
  CloudTransportChanged: unread,
  ContentRuleListsChanged: unread,
  DownloadStarted: unread,
  EnginePreferencesChanged: unread,
  ExtensionInstallAsked: (state, change) => void state.extensionPrompts.set(change.promptId, change),
  ExtensionInstallChanged: (state, change) => {
    state.extensionInstalls.set(change.install.installId, change.install);
    // An install that ended asks nothing more.
    if (change.install.stage.hasEnded) {
      for (const [promptId, asked] of state.extensionPrompts) {
        if (asked.installId === change.install.installId) state.extensionPrompts.delete(promptId);
      }
    }
  },
  FilterListsChanged: (state, change) => {
    state.filterLists = change.lists;
  },
  InstalledExtensionsChanged: (state, change) => void state.installedExtensions.set(change.profileId, change.extensions),
  LinkPreferencesChanged: (state, change) => {
    state.links = change.preferences;
  },
  NavigationRecorded: unread,
  OfferedPageAdopted: unread,
  OfferedWindowAdopted: unread,
  PageRehosted: unread,
  PageUnloaded: unread,
  QuitWithDownloadsAsked: unread,
  Saved: unread,
  SessionAdopted: unread,
  SetupCompletedChanged: unread,
  SetupDraftChanged: unread,
  SetupFinished: unread,
  SetupFlowChanged: unread,
  SiteContentBlockingChanged: (state, change) => {
    state.blockingSites = change.sites;
  },
  SpaceLockChanged: unread,
  StorageFailed: unread,
  SyncJournalChanged: unread,
  SyncRecordsSkipped: unread,
  SyncStagingFailed: unread,
  TabCopied: unread,
  TabFaviconAssigned: unread,
  TabPagePutAway: unread,
  TabSavedImageChanged: unread,
  TabsImported: unread,
  TransientPageClosed: (state, change) => void state.transientOutcomes.set(change.pageId, change),
  TransientPagePromoted: (state, change) => void state.transientOutcomes.set(change.pageId, change),
  WebsiteDataRead: (state, change) => void state.websiteDataReads.set(change.requestId, change),
  WindowBroughtForward: unread,
  WindowRecordsAdopted: unread,
};
