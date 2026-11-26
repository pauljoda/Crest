import {
  AdjacentDirection,
  ClearCurrentTabs,
  CloseTab,
  CollapseAllFolders,
  DissolveSplit,
  DuplicateTab,
  type Intent,
  JoinSplit,
  LeaveSplit,
  MoveTab,
  messageOfRejection,
  NumberedSelections,
  NumberedSelectionTarget,
  OpenInspector,
  type PageState,
  ReopenClosedTab,
  ShowAdjacentTab,
  ShowLeastRecentTab,
  ShowMostRecentTab,
  ShowTab,
  type SpaceState,
  SplitJoinCandidate,
  StepSplitMember,
  TabPlacement,
  type TabState,
  TabSurface,
  TogglePin,
  type SetupEntry,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";

import type { Session } from "./boot";
import type { Browsing } from "./browsing";
import { CopiedLink } from "./copied-link";
import { failureNotice, notices, urlCopiedNotice } from "./notices";
import { pageTools, zoomPercentage } from "./shell/page-tools";
import { toggleSiteContentBlocking } from "./shell/site-control.svelte";
import type { CommandHandlers } from "./shortcuts";
import { showAdjacentSpace, showSpaceNow } from "./spaces/show-space";

/**
 * Asks the window's sidebar to open one of its utility lists, or close it
 * when it is the one open, as Show Archive, Show History and Show Downloads
 * do; the event's detail names the list.
 */
export const toggleUtilityEvent = "crest-toggle-utility";

export const toggleUtility = (surface: "archive" | "history" | "downloads") =>
  window.dispatchEvent(new CustomEvent(toggleUtilityEvent, { detail: surface }));

/** Asks the window to open its command palette, for a new tab or to edit its location. */
export const openPaletteEvent = "crest-open-palette";

/** Opens the window's command palette, as the sidebar's address field and New Tab do. */
export function openPalette(kind: "newTab" | "editLocation") {
  window.dispatchEvent(new CustomEvent(openPaletteEvent, { detail: kind }));
}

/**
 * Opens a Space's page in the window's Settings, where Windows edits a
 * Space's name, icon and profile, as the Mac's Edit Space… opens its
 * editor. The window sets it.
 */
export const spaceEditing = { open: (_spaceId: string) => {} };

/** Opens Crest Setup over the window for `entry`, as Settings' Setup actions do; the app sets it once it starts. */
export const setupLauncher = { open: (_entry: SetupEntry) => {} };

/** What a window shows now, which its commands act on. */
export interface WindowView {
  readonly space: SpaceState | undefined;
  readonly tab: TabState | undefined;
  readonly page: PageState | null;
  /** The tabs the window's cards show, in column order: a split's members, or the tab alone. */
  readonly cards: readonly string[];
}

/** What the person is told of a refused action whose rule says nothing of its own. */
const unexplained = "Crest couldn’t complete that. Try again.";

/**
 * The commands a window runs, by the core's command names, as the Mac's
 * BrowserCommandActions runs them: each sends the core the intent the Mac's
 * sends, or asks the page's engine for view work. A command not here is not
 * built on Windows yet, so its keys stay the page's.
 */
export function windowCommands(session: Session, browsing: Browsing, view: () => WindowView): CommandHandlers {
  const { core, shell, windowId, workspaceId } = session;
  /** Sends `intent`; a refusal changes nothing, as the Mac's command does. */
  const send = (intent: Intent) => void core.send(intent).catch(ignoreRefusal);
  const inSpace = (act: (space: SpaceState) => void) => () => {
    const space = view().space;
    if (space) act(space);
  };
  const onTab = (act: (space: SpaceState, tab: TabState) => void) => () => {
    const { space, tab } = view();
    if (space && tab) act(space, tab);
  };
  const onPage = (act: (page: PageState) => void) => () => {
    const page = view().page;
    if (page) act(page);
  };
  const closeWindow = () => void shell?.window("requestClose");
  const zoom = async (page: PageState, step: "in" | "out" | "reset") => {
    const reached = await pageTools.setZoom(core, page.id, step);
    if (reached === null) return;
    const label = zoomPercentage(reached);
    notices.post({ message: label, symbol: "textformat.size", key: "page-zoom", accessibilityLabel: `Page zoom ${label}` });
  };
  const copyLink = async (page: PageState, text: (link: CopiedLink) => string) => {
    const address = page.live.url;
    if (!shell || !address) return;
    await shell.copy(text(await CopiedLink.of(core, address)));
    notices.post(urlCopiedNotice);
  };

  /** Shows where a numbered command leads, as the core answers it for this window. */
  const selectNumbered = (name: string) => async () => {
    const { selections } = await core.query(NumberedSelections({ windowId }));
    const selection = selections.find((candidate) => candidate.command.name === name);
    if (!selection) return;
    if (selection.target === NumberedSelectionTarget.space) void showSpaceNow(core, windowId, selection.spaceId).catch(ignoreRefusal);
    else if (selection.spaceId === view().space?.id) send(ShowTab({ windowId, spaceId: selection.spaceId, tabId: selection.tabId }));
  };
  /** Moves focus one card along the split the window shows, wrapping at both ends. */
  const focusAdjacentCard = (offset: number) => () => {
    const { space, tab, cards } = view();
    const index = tab ? cards.indexOf(tab.id) : -1;
    if (!space || cards.length < 2 || index < 0) return;
    send(ShowTab({ windowId, spaceId: space.id, tabId: cards[(index + offset + cards.length) % cards.length] }));
  };
  const splitCommands = {
    // Adds the next tab the core finds for it to the shown tab's split, making one if there is none.
    splitWithNextTab: onTab((space, tab) => void core.query(SplitJoinCandidate({ windowId })).then(({ tabId }) => {
      if (tabId) send(JoinSplit({ workspaceId, windowId, spaceId: space.id, tabId, targetTabId: tab.id, index: null }));
    })),
    focusNextSplitCard: focusAdjacentCard(1),
    focusPreviousSplitCard: focusAdjacentCard(-1),
    removeTabFromSplit: onTab((space, tab) => send(LeaveSplit({ workspaceId, spaceId: space.id, tabId: tab.id }))),
    separateSplitTabs: onTab((space, tab) => {
      if (tab.splitGroupId) send(DissolveSplit({ workspaceId, spaceId: space.id, groupId: tab.splitGroupId }));
    }),
    moveSplitCardLeft: onTab((space, tab) => send(StepSplitMember({ workspaceId, spaceId: space.id, tabId: tab.id, offset: -1 }))),
    moveSplitCardRight: onTab((space, tab) => send(StepSplitMember({ workspaceId, spaceId: space.id, tabId: tab.id, offset: 1 }))),
  };
  const numbered = Object.fromEntries(Array.from({ length: 9 }, (_, index) => [
    [`selectTab${index + 1}`, selectNumbered(`selectTab${index + 1}`)],
    [`selectSpace${index + 1}`, selectNumbered(`selectSpace${index + 1}`)],
  ]).flat());

  // New Tab and Open Location open the command palette, which the window owns.
  return {
    newWindow: () => void shell?.window("new"),
    // Closes the shown tab the way its section closes one, or the window
    // when the core says only the window is left to close.
    closeTabOrWindow: () => {
      const { space, tab } = view();
      if (!space || !tab) return closeWindow();
      void core.send(CloseTab({ workspaceId, windowId, spaceId: space.id, tabId: tab.id, returnTabId: null }))
        .catch((error) => {
          if (error instanceof CoreRejection && error.rejection.$kind === "LastStartPage") closeWindow();
          else ignoreRefusal(error);
        });
    },
    closeWindow,
    back: onPage((page) => void browsing.back(page.id)),
    forward: onPage((page) => void browsing.forward(page.id)),
    reloadPage: onPage((page) => void browsing.reload(page.id)),
    reloadFromOrigin: onPage((page) => void browsing.reload(page.id, true)),
    toggleContentBlocking: () => {
      const { space, page } = view();
      if (space && page) void toggleSiteContentBlocking(core, space.id, page.live.url, () => void browsing.reload(page.id)).catch(() => {});
    },
    stopLoading: onPage((page) => void browsing.stop(page.id)),
    // Pins or unpins the shown tab, and says why the core refused it, such
    // as a full pinned section.
    toggleSelectedTabPinned: onTab((space, tab) =>
      void core.send(TogglePin({ workspaceId, spaceId: space.id, tabId: tab.id })).catch((error) => {
        if (!(error instanceof CoreRejection)) throw error;
        notices.post(failureNotice(messageOfRejection(error.rejection) ?? unexplained));
      })),
    toggleSelectedTabSaved: onTab((space, tab) => {
      if (tab.surface === TabSurface.startPage) return;
      const placement = tab.placement === TabPlacement.saved ? TabPlacement.current : TabPlacement.saved;
      // The core takes a tab out of its split for a section that keeps none.
      send(MoveTab({ workspaceId, spaceId: space.id, tabId: tab.id, placement, folderId: null, beforeTabId: null,
        leavesSplit: false }));
    }),
    duplicateTab: onTab((space, tab) =>
      send(DuplicateTab({ workspaceId, windowId, spaceId: space.id, tabId: tab.id, placement: null, shows: true }))),
    reopenClosedTab: inSpace((space) => send(ReopenClosedTab({ workspaceId, windowId, spaceId: space.id }))),
    clearUnpinnedTabs: inSpace((space) =>
      send(ClearCurrentTabs({ workspaceId, windowId, spaceId: space.id, keepsShownTab: true }))),
    clearAllTabs: inSpace((space) =>
      send(ClearCurrentTabs({ workspaceId, windowId, spaceId: space.id, keepsShownTab: false }))),
    archiveTab: onTab((space, tab) =>
      send(CloseTab({ workspaceId, windowId, spaceId: space.id, tabId: tab.id, returnTabId: null }))),
    previousTab: () => send(ShowAdjacentTab({ windowId, direction: AdjacentDirection.previous })),
    nextTab: () => send(ShowAdjacentTab({ windowId, direction: AdjacentDirection.next })),
    // The Mac shows its recent-tab switcher while the keys are held; until it
    // is built here, a press goes straight to the tab.
    mostRecentTab: () => send(ShowMostRecentTab({ windowId })),
    mostRecentTabBackward: () => send(ShowLeastRecentTab({ windowId })),
    ...numbered,
    ...splitCommands,
    // A step slides the Space strip one page, around the ends where it wraps.
    previousSpace: () => void showAdjacentSpace(core, windowId, -1).catch(ignoreRefusal),
    nextSpace: () => void showAdjacentSpace(core, windowId, 1).catch(ignoreRefusal),
    collapseAllFolders: inSpace((space) => send(CollapseAllFolders({ workspaceId, spaceId: space.id }))),
    // The sidebar's lists, each opened or closed by its command, as the Mac's toggle them.
    showHistory: () => toggleUtility("history"),
    showArchive: () => toggleUtility("archive"),
    // Find in page and zoom are the page's, as on the Mac: the bar shows on
    // a page that has loaded something, finding again repeats the query
    // there is, and each zoom says where it went.
    // An open utility list's search takes Find, as the Mac's does.
    findInPage: () => {
      const listSearch = document.querySelector<HTMLInputElement>(".utility-search-input");
      if (listSearch) {
        listSearch.focus();
        listSearch.select();
        return;
      }
      onPage((page) => pageTools.present(page.id, page.live.url !== null))();
    },
    findNext: onPage((page) => pageTools.findAgain(core, page.id, false, page.live.url !== null)),
    findPrevious: onPage((page) => pageTools.findAgain(core, page.id, true, page.live.url !== null)),
    zoomIn: onPage((page) => void zoom(page, "in")),
    zoomOut: onPage((page) => void zoom(page, "out")),
    actualSize: onPage((page) => void zoom(page, "reset")),
    ...(shell ? {
      // Copies the page's address as Super Copy leaves it, and says so.
      copyPageLink: onPage((page) => void copyLink(page, (link) => link.url)),
      copyPageLinkAsMarkdown: onPage((page) => void copyLink(page, (link) => link.markdown(page.live.title))),
      showDownloads: () => toggleUtility("downloads"),
      webInspectorInstructions: onPage((page) => void core.request(OpenInspector({ pageId: page.id, panel: null }))),
    } : {}),
  };
}

/** A refusal means the command had nothing to do; anything else is a bug worth seeing. */
function ignoreRefusal(error: unknown) {
  if (!(error instanceof CoreRejection)) throw error;
}
