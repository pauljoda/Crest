import {
  CloseWindow,
  CloseWorkspace,
  CreateFolder,
  JoinSplit,
  MoveSplitMember,
  MoveTab,
  OpenTab,
  OpenWindow,
  OpenWorkspace,
  PracticeTab,
  ShowTab,
  type SpaceState,
  TabPlacement,
  type WindowState,
  WorkspaceKind,
  type WorkspaceOpened,
} from "@crest/contracts";

import type { Session } from "../boot";
import { bundledTabIcons } from "../page-icon.svelte";
import { send } from "../shell/sidebar-menus";
import { type SpaceCards, spaceCards } from "../shell/shown-cards";

/** The marks the practice's tabs wear, shared with the Mac, by asset name. */
const artwork: Record<string, string> = Object.fromEntries(
  Object.entries(import.meta.glob<string>("../../../../../CrestShared/Resources/GettingStartedLogos.xcassets/*/*.svg", {
    eager: true,
    query: "?url",
    import: "default",
  })).map(([path, url]) => [path.split("/").at(-2)?.replace(/\.imageset$/, "") ?? "", url]),
);

/** The color a new folder wears, the Mac's folderDefault (Slate). */
const folderDefault = { red: 0.43, green: 0.48, blue: 0.54, alpha: 1 };

/**
 * The Getting Started practice, as the Mac's BrowserGettingStartedPractice:
 * a practice workspace, which starts from the core's practice Space and
 * keeps nothing, shown in a window of its own. The Mac runs it in a core of
 * its own; here it shares the window's core, whose practice workspace no
 * gesture can carry a person's tabs into or out of, and whose pages load
 * only when a window asks for one, which the practice never does. So each
 * practice tab wears the mark bundled for it, as a loaded page would leave it.
 */
export class Practice {
  /** The practice's own session: its workspace and window, through the window's core and engine. */
  readonly session: Session;
  /** Each practice tab's identity in this practice. */
  readonly #tabIds: ReadonlyMap<PracticeTab, string>;

  private constructor(session: Session, tabIds: ReadonlyMap<PracticeTab, string>) {
    this.session = session;
    this.#tabIds = tabIds;
  }

  /** Opens a new practice beside `base`'s workspace. */
  static async open(base: Session): Promise<Practice> {
    const changes = await base.core.send(OpenWorkspace({ kind: WorkspaceKind.practice, seed: null }));
    const opened = changes.find((change): change is WorkspaceOpened => change.$kind === "WorkspaceOpened");
    if (!opened) throw new Error("The core opened no practice workspace.");
    const windowId = crypto.randomUUID();
    await base.core.send(OpenWindow({
      windowId, workspaceId: opened.workspaceId, saved: false, copyingWindowId: null, showingSpaceId: null,
      showingTabs: [], restoresTabs: true,
    }));
    const session: Session = {
      core: base.core, workspaceId: opened.workspaceId, windowId, engine: null, shell: base.shell,
      closing: { current: false }, setup: { current: null },
    };
    const tabIds = new Map<PracticeTab, string>();
    const space = practiceSpace(session);
    for (const tab of space?.tabs ?? []) {
      const practiceTab = PracticeTab.all.find((candidate) => candidate.url === tab.url);
      if (!practiceTab) continue;
      tabIds.set(practiceTab, tab.id);
      const icon = artwork[practiceTab.artwork];
      if (icon) bundledTabIcons.set(tab.id, icon);
    }
    return new Practice(session, tabIds);
  }

  /** Closes the practice, which leaves nothing behind. */
  async close() {
    for (const tab of this.space?.tabs ?? []) bundledTabIcons.delete(tab.id);
    const { core, windowId, workspaceId } = this.session;
    await core.send(CloseWindow({ windowId })).catch(() => undefined);
    await core.send(CloseWorkspace({ workspaceId })).catch(() => undefined);
  }

  /** The practice Space as the core holds it: the practice workspace's one Space. */
  get space(): SpaceState | undefined {
    return practiceSpace(this.session);
  }

  get window(): WindowState | undefined {
    return this.session.core.state.windows.get(this.session.windowId);
  }

  /** The tab the practice window shows, if any. */
  get shownTabId(): string | null {
    const window = this.window;
    return window?.shownTabs.find((shown) => shown.spaceId === window.shownSpaceId)?.tabId ?? null;
  }

  /** The cards the practice shows: the split the shown tab is in, or the shown tab alone, or none. */
  get cards(): SpaceCards {
    return spaceCards(this.window, this.space?.id ?? "", this.shownTabId);
  }

  /** The identity `tab` has in this practice, while the practice still holds it. */
  tabId(tab: PracticeTab): string | null {
    const id = this.#tabIds.get(tab);
    return id && this.space?.tabs.some((candidate) => candidate.id === id) ? id : null;
  }

  /** Pins or saves a practice tab, as Pin Tab and Save Tab do. */
  place(tab: PracticeTab, placement: TabPlacement) {
    const tabId = this.tabId(tab);
    const space = this.space;
    if (!tabId || !space) return;
    void send(this.session, MoveTab({
      workspaceId: this.session.workspaceId, spaceId: space.id, tabId, placement, folderId: null, beforeTabId: null,
      leavesSplit: false,
    }));
  }

  /** Adds Weekends to the saved tabs, and with `nested`, Ideas inside it, once each. */
  async addFolder(nested: boolean) {
    const space = this.space;
    if (!space) return;
    const create = async (title: string, parentId: string | null) => {
      const folderId = crypto.randomUUID();
      const made = await send(this.session, CreateFolder({
        workspaceId: this.session.workspaceId, spaceId: space.id, folderId, placement: TabPlacement.saved, parentId,
        title, color: folderDefault, symbol: "folder", tabIds: [], leavesSplits: false, isGroup: false,
      }));
      return made ? folderId : null;
    };
    const parent = space.folders.find((folder) => folder.title === "Weekends" && folder.parentId === null)?.id
      ?? await create("Weekends", null);
    if (nested && parent && !this.space?.folders.some((folder) => folder.parentId === parent)) await create("Ideas", parent);
  }

  /** Shows the trail guide and joins the packing list to it in a split, as Add Packing list does. */
  async makeSplit() {
    const space = this.space;
    const packing = this.tabId(PracticeTab.packing);
    const trail = this.tabId(PracticeTab.trail);
    if (!space || !packing || !trail) return;
    const { workspaceId, windowId } = this.session;
    await send(this.session, ShowTab({ windowId, spaceId: space.id, tabId: trail }));
    await send(this.session, JoinSplit({ workspaceId, windowId, spaceId: space.id, tabId: packing, targetTabId: trail, index: null }));
  }

  /**
   * The practice has no pages, so the example tab opens as a loaded page
   * would leave it: titled, and wearing the site's icon.
   */
  openExampleTab() {
    const space = this.space;
    if (!space) return;
    const example = PracticeTab.reading;
    const tabId = crypto.randomUUID();
    const icon = artwork[example.artwork];
    if (icon) bundledTabIcons.set(tabId, icon);
    void send(this.session, OpenTab({
      workspaceId: this.session.workspaceId, windowId: this.session.windowId, spaceId: space.id, tabId,
      content: { address: example.url, view: null, title: example.title }, placement: TabPlacement.current,
      afterTabId: null, shows: true, placesAsNewTab: false, savesInSavedFolder: false,
    }));
  }

  /** Makes a card the focused one. */
  focus(tabId: string) {
    const space = this.space;
    if (space) void send(this.session, ShowTab({ windowId: this.session.windowId, spaceId: space.id, tabId }));
  }

  /** Whether a split member can move `offset` places. */
  canMove(tabId: string, offset: number): boolean {
    const { tabIds, groupId } = this.cards;
    const index = tabIds.indexOf(tabId);
    return groupId !== null && index >= 0 && index + offset >= 0 && index + offset < tabIds.length;
  }

  /** Focuses a split member and moves it `offset` places. */
  async move(tabId: string, offset: number) {
    const space = this.space;
    const index = this.cards.tabIds.indexOf(tabId);
    if (!space || index < 0 || !this.canMove(tabId, offset)) return;
    await send(this.session, ShowTab({ windowId: this.session.windowId, spaceId: space.id, tabId }));
    await send(this.session, MoveSplitMember({ workspaceId: this.session.workspaceId, spaceId: space.id, tabId, index: index + offset }));
  }
}

function practiceSpace(session: Session): SpaceState | undefined {
  const workspace = session.core.state.workspaces.get(session.workspaceId);
  const first = workspace?.order[0];
  return first ? workspace.spaces.get(first) : undefined;
}
