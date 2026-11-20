import {
  CollapseFolder,
  ExpandSavedTabs,
  type FolderState,
  type HistoryEntryState,
  OpenTab,
  type PageState,
  type PermissionAsked,
  ReleasePage,
  RenameFolder,
  RenameTab,
  SetFolderColor,
  SetFolderSymbol,
  ShowSpace,
  ShowTab,
  type SidebarList,
  type SpaceState,
  TabPlacement,
  type TabState,
} from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, LayoutGroup, motion } from "motion/react";
import { type KeyboardEvent, type MouseEvent, type ReactElement, useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

import type { Session } from "../boot";
import type { Browsing } from "../browsing";
import { openPalette, toggleUtilityEvent } from "../commands";
import { insideCrest } from "../environment";
import { type MenuEntry, showContextMenu } from "../menus";
import { useTabIcon } from "../page-icon";
import { pageStills } from "../spaces/page-stills";
import { Symbol } from "../symbols";
import type { Downloads } from "../downloads";
import { emojiOf, indigo } from "../branding";
import { spacePager } from "../spaces/space-pager";
import { CommonListsButton, UtilityFan } from "../utilities/CommonLists";
import { chooseSurface, chosenSurface, type UtilitySurfaceName } from "../utilities/utility-list";
import { UtilityList } from "../utilities/UtilityList";
import { SpacePageStrip } from "../spaces/SpacePageStrip";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { SpaceSwitcher } from "../spaces/SpaceSwitcher";
import { useFieldHandedOff } from "../palette/palette-morph";
import { ChromeButton } from "./ChromeButton";
import { NavigationButtons } from "./NavigationButtons";
import { PermissionPrompt } from "./prompts/PermissionPrompt";
import { type BlockedPopupNotice, blockedPopups, useBlockedPopups } from "./blocked-popups";
import { useCertificates } from "./site-control";
import { PinnedExtensionStrip } from "./ExtensionActions";
import { AddressSecurityButton, SiteControlPanel, SiteControlTrigger } from "./SiteControl";
import { droppedJustNow, type Lift, type LiftItem, useSidebarLift } from "./sidebar-drag";
import {
  backgroundMenu,
  batchIntents,
  batchMenu,
  copySelectedLinks,
  folderMenu,
  performBatch,
  send,
  type SidebarContext,
  spaceHeaderMenu,
  tabMenu,
} from "./sidebar-menus";
import {
  allSelected,
  clicked,
  folderItem,
  holds,
  itemParts,
  noSelection,
  pickedWith,
  preview,
  reconciled,
  registerSelectionTaker,
  rootItems,
  type SelectionItem,
  type SelectionKey,
  selectionHasKeyboard,
  type SidebarSelection,
  tabItem,
  unitsShown,
} from "./sidebar-selection";
import type { SidebarDialog } from "./SidebarDialogs";
import { SplitGroupHeader } from "./SplitGroupHeader";
import { previewHandlers, showsTabPreviews } from "./TabPreview";
import { FolderArtwork } from "./FolderArtwork";
import { ColorPicker, EmojiPicker, Popover } from "./pickers";

/** The virtual-key codes the selection answers. */
const keys = {
  backspace: 0x08, enter: 0x0d, escape: 0x1b, end: 0x23, home: 0x24, left: 0x25, up: 0x26, right: 0x27, down: 0x28,
  delete: 0x2e, a: 0x41, c: 0x43, d: 0x44,
} as const;

/** What the sidebar is renaming in place, if anything. */
type Renaming = { readonly tabId: string } | { readonly folderId: string } | null;

interface SidebarProps {
  readonly session: Session;
  readonly browsing: Browsing;
  readonly space: SpaceState;
  readonly spaces: readonly SpaceState[];
  readonly shownTabId: string | null;
  /** The tab the window shows in each Space, which a Space's page marks as a slide shows it. */
  readonly shownTabs: ReadonlyMap<string, string>;
  readonly page: PageState | null;
  /** Each tab's live page in this window, by tab. */
  readonly pagesByTab: ReadonlyMap<string, string>;
  /** Whether the navigation buttons head the sidebar, as on the Mac, rather than the window's title bar. */
  readonly showsNavigation: boolean;
  /** The shown page's permission request waiting on the person, if any. */
  readonly permission: PermissionAsked | null;
  /** The window's downloads, inside Crest's own window; none in development. */
  readonly downloads: Downloads | null;
  /** Asks a question over the page, as the Mac's sidebar asks in a dialog. */
  readonly onDialog: (dialog: SidebarDialog) => void;
  /** Whether the sidebar is docked beside the page rather than floating over it. */
  readonly docked: boolean;
  /** Floats a docked sidebar over the page, or docks a floating one. */
  readonly onToggleDock: () => void;
}

/**
 * The window's sidebar: navigation, the address field, the Space's pinned
 * tiles, its organized and open tabs, and the Space switcher. Rows come from
 * the core's sidebar outline, which already orders and nests them.
 */
export function Sidebar({
  session, browsing, space, spaces, shownTabId, shownTabs, page, pagesByTab, showsNavigation, permission, downloads, onDialog,
  docked, onToggleDock,
}: SidebarProps) {
  const aside = useRef<HTMLElement>(null);

  // The window's utility list, as the Mac's utility presentation: the list
  // open in place of the Space's tabs, if any. The Common Lists button opens
  // the list chosen for the Space, or Downloads while downloads finished
  // unseen, and closes it; Show Downloads opens or closes Downloads.
  const [utility, setUtility] = useState<UtilitySurfaceName | null>(null);
  const [, setChoices] = useState(0);
  const listsButton = useRef<HTMLButtonElement>(null);
  const chosen = chosenSurface(space.id);
  const profileDownloads = downloads?.of(space.profileId) ?? [];
  const newDownloads = profileDownloads.filter((download) => !download.isAcknowledged);
  const toggleLists = () => setUtility((current) => (current ? null : newDownloads.length > 0 ? "downloads" : chosen));
  useEffect(() => {
    const toggle = (event: Event) => {
      const surface = (event as CustomEvent<UtilitySurfaceName>).detail;
      setUtility((current) => (current === surface ? null : surface));
    };
    window.addEventListener(toggleUtilityEvent, toggle);
    return () => window.removeEventListener(toggleUtilityEvent, toggle);
  }, []);
  const dismissUtility = useCallback(() => setUtility(null), []);
  // The search and the filter are the window's, shared by its Spaces, and start over with each list.
  const [utilitySearch, setUtilitySearch] = useState("");
  const [utilityFilter, setUtilityFilter] = useState("all");
  useEffect(() => {
    setUtilitySearch("");
    setUtilityFilter("all");
  }, [utility]);
  // A click on the page puts the list away, as the Mac's web content interaction does.
  useEffect(() => {
    if (!utility) return;
    const onFocus = (event: FocusEvent) => {
      if (event.target instanceof HTMLEmbedElement) setUtility(null);
    };
    document.addEventListener("focusin", onFocus);
    return () => document.removeEventListener("focusin", onFocus);
  }, [utility]);
  const [windowElement, setWindowElement] = useState<HTMLElement | null>(null);
  useEffect(() => setWindowElement(aside.current?.closest<HTMLElement>(".browser-window") ?? null), []);
  // A history entry opens in a new tab after the one on show, as the Mac's list opens it.
  const openHistoryEntry = (entry: HistoryEntryState) => void send(session, OpenTab({
    workspaceId: session.workspaceId, windowId: session.windowId, spaceId: space.id, tabId: crypto.randomUUID(),
    content: { address: entry.url, view: null, title: null }, placement: TabPlacement.current, afterTabId: shownTabId,
    shows: true, placesAsNewTab: false, savesInSavedFolder: false,
  }));
  const tabs = new Map(space.tabs.map((tab) => [tab.id, tab]));
  const folders = new Map(space.folders.map((folder) => [folder.id, folder]));
  const show = (tabId: string) => void session.core.send(ShowTab({ windowId: session.windowId, spaceId: space.id, tabId }));
  const close = (tabId: string) => void browsing.closeTab(space.id, tabId);
  // A rename belongs to the Space it started in.
  const [renaming, setRenaming] = useState<Renaming>(null);
  // A folder's icon or colour being chosen, in a popover beside its row.
  const [folderLook, setFolderLook] = useState<{ folderId: string; kind: "icon" | "color"; anchor: DOMRect } | null>(null);
  useEffect(() => setRenaming(null), [space.id]);

  // Site Controls act for the shown page while it has an address, and go
  // with the Space or the page they opened for, as the Mac's popover does.
  const siteControlPage = page?.live.url ? page : null;
  const certificates = useCertificates(session, siteControlPage);
  const popups = useBlockedPopups();
  const popupNotice = siteControlPage ? popups.notice(siteControlPage.id) : null;
  const [siteControlsOpen, setSiteControlsOpen] = useState(false);
  const closeSiteControls = useCallback(() => setSiteControlsOpen(false), []);
  useEffect(() => setSiteControlsOpen(false), [space.id, siteControlPage?.id]);

  // The window's selection, which the Mac's sidebar keeps beside the shown
  // tab and the core never sees. It belongs to the Space it was made in.
  const [selection, setSelection] = useState<SidebarSelection>(noSelection);
  const selectionNow = useRef(selection);
  const select = useCallback((next: SidebarSelection) => {
    selectionNow.current = next;
    setSelection(next);
  }, []);
  useEffect(() => select(noSelection), [space.id, select]);
  // A change to the outline keeps only what the sidebar still shows.
  useEffect(() => {
    const next = reconciled(selectionNow.current, unitsShown());
    if (next !== selectionNow.current) select(next);
  }, [space.sidebar, space.tabs, space.folders, select]);
  // Pinned tabs a lift let go of shake, as the Mac's do.
  const [shaken, setShaken] = useState<ReadonlySet<string>>(new Set());
  useEffect(() => {
    if (shaken.size === 0) return;
    const timer = setTimeout(() => setShaken(new Set()), 420);
    return () => clearTimeout(timer);
  }, [shaken]);
  const activeItem = shownTabId ? tabItem(shownTabId) : null;
  /** The units the sidebar shows, and the selection over them as of now. */
  const selectionOverRows = () => {
    const units = unitsShown();
    return { units, current: reconciled(selectionNow.current, units) };
  };

  const context: SidebarContext = {
    session, space, spaces, shownTabId, pagesByTab,
    rename: (item) => {
      const tab = "tabId" in item ? tabs.get(item.tabId) : undefined;
      // A pinned tile has no room for a field, so it asks in a dialog.
      if (tab?.placement === TabPlacement.pinned) onDialog({ kind: "renameTab", spaceId: space.id, tab });
      else setRenaming(item);
    },
    confirmDeleteFolder: (folder) => onDialog({ kind: "deleteFolder", spaceId: space.id, folder }),
    chooseLook: (folder, kind) => {
      const row = document.querySelector<HTMLElement>(`[data-folder="${folder.id}"]`);
      if (row) setFolderLook({ folderId: folder.id, kind, anchor: row.getBoundingClientRect() });
    },
    addToSelection: (item) => {
      const { units, current } = selectionOverRows();
      select(clicked(current, item, units, { command: true, shift: false }, activeItem));
    },
    selectAll: () => select(allSelected(unitsShown())),
    reselect: (how, picks, copies) => select(how === "cleared" ? noSelection
      : allSelected(how === "copies" ? [...copies.values()].map((id) => [tabItem(id)]) : rootItems(picks, copies))),
  };
  const menu = (event: MouseEvent, entries: Promise<MenuEntry[]> | MenuEntry[]) => {
    event.preventDefault();
    event.stopPropagation();
    const point = { clientX: event.clientX, clientY: event.clientY };
    void Promise.resolve(entries).then((built) => showContextMenu(session.shell, point, built));
  };
  /**
   * A row's menu, as the Mac's right click: a row the selection does not
   * hold lets the selection go and offers its own menu; a held row offers
   * the selection's.
   */
  const rowMenu = (event: MouseEvent, item: SelectionItem, own: () => Promise<MenuEntry[]>) => {
    const { units, current } = selectionOverRows();
    const kept = holds(current, item) ? current : noSelection;
    select(kept);
    const picked = pickedWith(kept, item, units);
    menu(event, picked ? preview(session, space.id, picked).then((picks) => batchMenu(context, picks), own) : own());
  };
  // A middle click closes a current tab and puts a saved or pinned tab's page away.
  const middleClick = (tab: TabState) => {
    const pageId = pagesByTab.get(tab.id);
    if (tab.placement === TabPlacement.current) close(tab.id);
    else if (pageId) void send(session, ReleasePage({ pageId, keepsState: true }));
  };
  const toggleFolder = (folder: FolderState) => void session.core.send(CollapseFolder({
    workspaceId: session.workspaceId, spaceId: space.id, folderId: folder.id, collapsed: !folder.isCollapsed,
  }));
  /** Shows a tab from its row, which collapses the selection to the row, as the Mac's activation does. */
  const activate = (tabId: string) => {
    const { units, current } = selectionOverRows();
    select(clicked(current, tabItem(tabId), units, { command: false, shift: false }, activeItem));
    show(tabId);
  };
  /** Whether a click activates its row: not one the selection took, nor a drop's release. */
  const activates = (event: MouseEvent) => !event.ctrlKey && !event.shiftKey && !droppedJustNow();

  // A lift hides what it carries and marks where it would land. A lift of
  // the selection carries every pick, and the selection follows it there.
  const { lift, press } = useSidebarLift(session, space.id, {
    releasePins: (pins) => {
      const current = selectionNow.current;
      const released = (item: SelectionItem | null) => item !== null && itemParts(item).kind === "tab" && pins.includes(itemParts(item).id);
      const items = new Set([...current.items].filter((item) => !released(item)));
      const first = [...items][0] ?? null;
      select({
        ...current, items, rangeBase: null,
        anchor: released(current.anchor) ? first : current.anchor,
        focused: released(current.focused) ? first : current.focused,
      });
      setShaken(new Set(pins));
    },
    landed: ({ leftSpace, selected: picks, copies }) => select(leftSpace ? noSelection : allSelected(rootItems(picks, copies))),
  });
  // A drag in flight owns the horizontal axis, so the Space strip holds still under it.
  useEffect(() => spacePager.setLocked(lift !== null), [lift !== null]);
  /**
   * A press on a row, as the Mac's selection monitor sees it before the row:
   * Ctrl or Shift selects and goes no further; a plain press selects a row
   * the selection does not hold, quietly, and otherwise keeps the selection,
   * so pulling the row lifts every pick.
   */
  const pressRow = (item: SelectionItem, lifting: LiftItem, event: React.PointerEvent<HTMLElement>) => {
    if (event.button !== 0) return;
    const { units, current } = selectionOverRows();
    if (event.ctrlKey || event.shiftKey) {
      select(clicked(current, item, units, { command: event.ctrlKey, shift: event.shiftKey }, activeItem));
      return;
    }
    const picked = pickedWith(current, item, units);
    if (!picked) {
      select(clicked(current, item, units, { command: false, shift: false }, activeItem));
      press(lifting, event);
      return;
    }
    select(current);
    const parts = picked.map(itemParts);
    press({
      ...lifting,
      carried: {
        tabIds: parts.filter((part) => part.kind === "tab").map((part) => part.id),
        folderIds: parts.filter((part) => part.kind === "folder").map((part) => part.id),
      },
    }, event);
  };

  // What the selection does with the keys while it has them, as the Mac's
  // selection monitor: Escape lets it go, Ctrl+A selects every row, Ctrl+C,
  // Ctrl+D and Ctrl+Backspace copy, duplicate and delete it, the arrows,
  // Home and End move it (Shift extends it), and Enter opens what it rests on.
  const act = async (picked: readonly SelectionItem[], action: "copy" | "duplicate" | "delete" | "close") => {
    const picks = await preview(session, space.id, picked);
    const intents = batchIntents(session, space.id, picks.selection);
    if (action === "copy") await copySelectedLinks(context, picks);
    else if (action === "duplicate") await performBatch(context, picks, intents.copying, "copies");
    else if (action === "delete") await performBatch(context, picks, intents.deleting, "cleared");
    else await performBatch(context, picks, intents.closing, "cleared");
  };
  const takeKey = useRef<(key: SelectionKey) => boolean>(() => false);
  takeKey.current = (key) => {
    if (key.alt) return false;
    const { units, current } = selectionOverRows();
    if (key.code === keys.escape && lift) {
      select(noSelection);
      return false;
    }
    // A row the person clicked has the keys too, as the Mac's selection view
    // does once it is the window's first responder; a rename field in it keeps its own.
    const active = document.activeElement;
    const onRow = active instanceof HTMLElement && !(active instanceof HTMLInputElement) && !active.isContentEditable
      && !!active.closest(".sidebar [data-unit]");
    if (!selectionHasKeyboard(current) && !onRow) return false;
    if (current !== selectionNow.current) select(current);
    if (key.code === keys.escape) {
      select(noSelection);
      return true;
    }
    if (key.control && key.code === keys.a) {
      select(key.shift ? noSelection : allSelected(units));
      return true;
    }
    if (key.control && !key.shift && current.focused) {
      const picked = pickedWith(current, current.focused, units);
      const action = key.code === keys.c ? "copy" : key.code === keys.d ? "duplicate"
        : key.code === keys.backspace || key.code === keys.delete ? "delete" : null;
      if (picked && action) {
        void act(picked, action);
        return true;
      }
    }
    const moves: readonly number[] = [keys.left, keys.up, keys.right, keys.down, keys.home, keys.end];
    if (moves.includes(key.code) && units.length > 0) {
      const from = current.focused ?? current.anchor ?? units[0][0];
      const at = Math.max(0, units.findIndex((unit) => unit.includes(from)));
      const backwards = key.code === keys.left || key.code === keys.up || key.code === keys.home;
      const edge = key.control || key.code === keys.home || key.code === keys.end;
      const index = edge ? (backwards ? 0 : units.length - 1) : Math.min(Math.max(at + (backwards ? -1 : 1), 0), units.length - 1);
      const target = units[index][0];
      let next = clicked(current, target, units, { command: key.control && !edge, shift: key.shift }, activeItem);
      if (!key.shift) next = { ...clicked(next, target, units, { command: false, shift: false }, activeItem), engaged: true };
      select(next);
      [...document.querySelectorAll<HTMLElement>(".sidebar [data-unit]")].filter((element) => element.offsetParent !== null)[index]
        ?.scrollIntoView({ block: "nearest" });
      return true;
    }
    if (key.code === keys.enter && current.focused) {
      const { kind, id } = itemParts(current.focused);
      const folder = kind === "folder" ? folders.get(id) : undefined;
      if (kind === "tab") activate(id);
      else if (folder) toggleFolder(folder);
      return true;
    }
    return false;
  };
  /** Ctrl+W archives the selection while it has the keys, unless it is only the shown tab, as on the Mac. */
  const takeClose = useRef<() => boolean>(() => false);
  takeClose.current = () => {
    const { units, current } = selectionOverRows();
    if (!selectionHasKeyboard(current) || !current.focused) return false;
    const picked = pickedWith(current, current.focused, units);
    if (!picked || (picked.length === 1 && picked[0] === activeItem)) return false;
    void act(picked, "close");
    return true;
  };
  useEffect(() => {
    const onKey = (event: globalThis.KeyboardEvent) => {
      const key = { code: event.keyCode, control: event.ctrlKey, shift: event.shiftKey, alt: event.altKey };
      if (!takeKey.current(key)) return;
      event.preventDefault();
      event.stopPropagation();
    };
    // A press anywhere but a row lets the selection go, as does the page taking the keys.
    const onPress = (event: PointerEvent) => {
      if (event.target instanceof Element && event.target.closest("[data-unit]")) return;
      if (selectionNow.current !== noSelection) select(noSelection);
    };
    const onFocus = (event: FocusEvent) => {
      if (event.target instanceof HTMLEmbedElement && selectionNow.current.engaged) select(noSelection);
    };
    window.addEventListener("keydown", onKey, true);
    window.addEventListener("pointerdown", onPress, true);
    document.addEventListener("focusin", onFocus);
    const unregister = registerSelectionTaker((command, key) =>
      (command === "closeTabOrWindow" && takeClose.current()) || (key !== null && takeKey.current(key)));
    return () => {
      window.removeEventListener("keydown", onKey, true);
      window.removeEventListener("pointerdown", onPress, true);
      document.removeEventListener("focusin", onFocus);
      unregister();
    };
  }, [select]);

  /** Whether a row draws itself selected for tab actions: the selection holds it and no selected folder around it. */
  const marked = (item: SelectionItem) => {
    if (!holds(selection, item)) return false;
    const { kind, id } = itemParts(item);
    const seen = new Set<string>();
    for (let parent = kind === "tab" ? tabs.get(id)?.folderId ?? null : folders.get(id)?.parentId ?? null;
      parent && !seen.has(parent); parent = folders.get(parent)?.parentId ?? null) {
      seen.add(parent);
      if (selection.items.has(folderItem(parent))) return false;
    }
    return true;
  };

  const carried = lift?.item.carried;
  const liftedFolders = new Set<string>(carried ? carried.folderIds : lift?.item.kind === "folder" ? [lift.item.id] : []);
  if (liftedFolders.size > 0) {
    for (let grew = true; grew;) {
      grew = false;
      for (const folder of space.folders) {
        if (folder.parentId && liftedFolders.has(folder.parentId) && !liftedFolders.has(folder.id)) {
          liftedFolders.add(folder.id);
          grew = true;
        }
      }
    }
  }
  const isLifted = (tabId: string) => (carried ? carried.tabIds.includes(tabId) : lift?.item.kind === "tab" && lift.item.id === tabId);
  const gapAt = (section: TabPlacement, folderId: string | null, beforeRow: string | null) =>
    lift?.aim?.kind === "list" && lift.aim.section === section && lift.aim.folderId === folderId && lift.aim.gapBefore === beforeRow;
  const finishRename = (title: string | null) => {
    const current = renaming;
    setRenaming(null);
    if (!current || title === null) return;
    const { workspaceId } = session;
    if ("tabId" in current) void send(session, RenameTab({ workspaceId, spaceId: space.id, tabId: current.tabId, title }));
    else void send(session, RenameFolder({ workspaceId, spaceId: space.id, folderId: current.folderId, title }));
  };
  const live = page?.live;

  // What the shown Space's page draws as the person uses it. A page a slide
  // shows beside it is drawn still: no selection, lift or rename of its own.
  const outer = { tabs, folders, shownTabId, selection, lift, renaming, shaken, liftedFolders, marked, isLifted, gapAt };
  const toggleSavedTabs = (pageSpace: SpaceState) => void session.core.send(ExpandSavedTabs({
    workspaceId: session.workspaceId, spaceId: pageSpace.id, isExpanded: !pageSpace.settings.isSavedTabsExpanded,
  }));
  /** One Space's page of the sidebar, as the Mac's BrowserSidebarSpacePage: its pins, its header and its tabs. */
  const renderPage = (space: SpaceState, isLive: boolean): ReactElement => {
    const tabs = isLive ? outer.tabs : new Map(space.tabs.map((tab) => [tab.id, tab]));
    const folders = isLive ? outer.folders : new Map(space.folders.map((folder) => [folder.id, folder]));
    const shownTabId = isLive ? outer.shownTabId : shownTabs.get(space.id) ?? null;
    const selection = isLive ? outer.selection : noSelection;
    const lift = isLive ? outer.lift : null;
    const renaming = isLive ? outer.renaming : null;
    const shaken = isLive ? outer.shaken : new Set<string>();
    const liftedFolders = isLive ? outer.liftedFolders : new Set<string>();
    const marked = isLive ? outer.marked : () => false;
    const isLifted = isLive ? outer.isLifted : () => false;
    const gapAt = isLive ? outer.gapAt : () => false;
    const savedTabsExpanded = space.settings.isSavedTabsExpanded;
    const isPinnedTop = (list: SidebarList) => list.section.name === "pinned" && list.folderId === null;
    const pinned = space.sidebar.lists.filter(isPinnedTop);
    // The saved tabs show while the header has them open.
    const rest = space.sidebar.lists.filter((list) => !isPinnedTop(list) && (savedTabsExpanded || list.section.name !== "saved"));
    // An open utility list takes the shown Space's page: its pins, its header
    // and its tabs. Another Space's page a slide passes shows nothing.
    if (utility) {
      if (!isLive) return <></>;
      return (
        <UtilityList session={session} surface={utility} space={space} spaces={spaces} downloads={downloads}
          searchText={utilitySearch} onSearchText={setUtilitySearch} filterName={utilityFilter} onFilterName={setUtilityFilter}
          onOpenHistory={openHistoryEntry} onRestored={show} onClearHistory={() => onDialog({ kind: "clearHistory", spaceId: space.id })}
          onDismiss={dismissUtility} />
      );
    }
    return (
      <>
      <PinnedExtensionStrip session={session} space={space} pageId={page?.id ?? null} pageKey={`${page?.live.url ?? ""}|${page?.live.title ?? ""}`} />
      {(pinned.some((list) => list.rows.length > 0) || lift) && (
        <div className={`pinned-grid${gapAt(TabPlacement.pinned, null, null) ? " drop-at-end" : ""}`} data-list-section={TabPlacement.pinned.name} data-list-folder="">
          {pinned.flatMap((list) => list.rows).flatMap((row) => {
            const tab = tabs.get(row.id);
            if (!tab) return [];
            const tile = (
              <motion.button
                key={tab.id}
                className={`pinned-tile${tab.id === shownTabId ? " selected" : ""}${marked(tabItem(tab.id)) ? " unit-selected" : ""}${shaken.has(tab.id) ? " shaken" : ""}${isLifted(tab.id) ? " lifted" : ""}${gapAt(TabPlacement.pinned, null, tab.id) ? " drop-before" : ""}`}
                data-row={tab.id}
                data-before-tab={tab.id}
                data-unit={tabItem(tab.id)}
                aria-selected={holds(selection, tabItem(tab.id))}
                onPointerDown={(event) => pressRow(tabItem(tab.id), { kind: "tab", id: tab.id }, event)}
                onClick={(event) => activates(event) && activate(tab.id)}
                onAuxClick={(event) => event.button === 1 && middleClick(tab)}
                onContextMenu={(event) => rowMenu(event, tabItem(tab.id), () => tabMenu(context, tab))}
                {...previewHandlers(tab.id)}
                whileTap={{ scale: 0.96 }}
                transition={tokens.press}
                // The card says what the tile is, where the person keeps previews.
                title={showsTabPreviews() ? undefined : tab.displayTitle}
              >
                <TabIcon session={session} tab={tab} pageId={pagesByTab.get(tab.id) ?? null} size={20} />
              </motion.button>
            );
            return [tile];
          })}
        </div>
      )}

      <div className="space-header">
        <button
          className="space-header-title"
          onClick={() => toggleSavedTabs(space)}
          aria-label={`${space.settings.name} saved tabs`}
          aria-expanded={savedTabsExpanded}
          aria-description={savedTabsExpanded ? "Collapses saved tabs" : "Expands saved tabs"}
        >
          {/* The crest and the chevron share one slot, so the title never shifts as the saved tabs open. */}
          <span className={`space-header-identity${savedTabsExpanded ? "" : " collapsed"}`} aria-hidden>
            <span className="space-header-crest">
              <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={20} />
            </span>
            <span className="space-header-chevron"><Symbol name="chevron.right" size={9} strokeWidth={3} /></span>
          </span>
          <span className="space-name">{space.settings.name}</span>
          {space.settings.requiresAuthentication && (
            <span className="space-header-lock" aria-label="Private Space"><Symbol name="lock.fill" size={10} strokeWidth={3} /></span>
          )}
        </button>
        <ChromeButton symbol="ellipsis" label="Space Actions" className="space-header-actions" onClick={(button) => {
          const bounds = button.getBoundingClientRect();
          void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom }, spaceHeaderMenu(context));
        }} />
      </div>

      <LayoutGroup id={`sidebar-${space.id}`}>
        <div
          className="tab-list"
          // The empty area offers the Space's own actions, and a double click opens a new tab, as on the Mac.
          onContextMenu={(event) => event.target === event.currentTarget && menu(event, backgroundMenu(context))}
          onDoubleClick={(event) => event.target === event.currentTarget && openPalette("newTab")}
        >
          {rest.filter((list) => list.folderId === null && (list.rows.length > 0 || lift)).map(function renderList(list: SidebarList): ReactElement {
            return (
            <section
              key={`${list.section.name}-${list.folderId ?? "root"}`}
              className={`tab-section${list.folderId && liftedFolders.has(list.folderId) ? " lifted" : ""}${gapAt(list.section, list.folderId, null) ? " drop-at-end" : ""}`}
              data-list-section={list.section.name}
              data-list-folder={list.folderId ?? ""}
            >
              {list.rows.flatMap((row) => {
                const gap: ReactElement[] = [];
                const insertsBefore = gapAt(list.section, list.folderId, row.id);
                if (row.kind.name === "folder") {
                  const folder = folders.get(row.id);
                  if (!folder) return gap;
                  const renamesFolder = renaming !== null && "folderId" in renaming && renaming.folderId === folder.id;
                  return [...gap, (
                    <FolderRow
                      key={row.id}
                      folder={folder}
                      depth={row.depth}
                      renaming={renamesFolder}
                      marked={marked(folderItem(folder.id))}
                      held={holds(selection, folderItem(folder.id))}
                      lifted={liftedFolders.has(folder.id)}
                      insertsBefore={insertsBefore}
                      aimedInto={lift?.aim?.kind === "folder" && lift.aim.folderId === folder.id}
                      onPress={(event) => !renamesFolder && pressRow(folderItem(folder.id), { kind: "folder", id: folder.id }, event)}
                      onToggle={(event) => {
                        if (!activates(event)) return;
                        // The click selects the folder quietly, as the Mac's header does, then opens or closes it.
                        const { units, current } = selectionOverRows();
                        select(clicked(current, folderItem(folder.id), units, { command: false, shift: false }, activeItem));
                        toggleFolder(folder);
                      }}
                      onContextMenu={(event) => rowMenu(event, folderItem(folder.id), () => folderMenu(context, folder))}
                      onRenamed={finishRename}
                    />
                  ), ...(() => {
                    // A folder's own list follows its header, as the Mac draws it. A
                    // closed folder keeps only its loaded tabs on show, and a closed
                    // group only the tab the window shows.
                    const inside = rest.find((candidate) => candidate.folderId === folder.id);
                    if (!inside) return [];
                    if (!folder.isCollapsed) return [renderList(inside)];
                    const keeps = (id: string) => (folder.isGroup ? id === shownTabId : pagesByTab.has(id) || id === shownTabId);
                    const rows = inside.rows.filter((candidate) => candidate.kind.name !== "folder" && candidate.members.concat(candidate.id).some(keeps));
                    return [renderList({ ...inside, rows })];
                  })()];
                }
                const members = row.kind.groupsTabs ? row.members : [row.id];
                const memberTabs = members.map((id) => tabs.get(id)).filter((tab): tab is TabState => !!tab);
                // A split's group, whose collapsed header keeps only the tab the window shows.
                const groupId = row.kind.groupsTabs ? memberTabs[0]?.splitGroupId ?? null : null;
                const group = groupId ? space.splitGroups.find((candidate) => candidate.id === groupId) ?? null : null;
                const focusedMember = memberTabs.find((tab) => tab.id === shownTabId)?.id ?? null;
                const listed = group?.isCollapsed ? memberTabs.filter((tab) => tab.id === focusedMember) : memberTabs;
                const content = listed.map((tab) => {
                  const renamesTab = renaming !== null && "tabId" in renaming && renaming.tabId === tab.id;
                  return (
                    <TabRow
                      key={tab.id}
                      session={session}
                      tab={tab}
                      pageId={pagesByTab.get(tab.id) ?? null}
                      depth={row.kind.groupsTabs ? row.depth + 1 : row.depth}
                      selected={tab.id === shownTabId}
                      renaming={renamesTab}
                      row={row.kind.groupsTabs ? null : {
                        id: row.id,
                        // A current tab at the top level, in no split, may have a folder made around it.
                        aroundTab: list.section === TabPlacement.current && list.folderId === null,
                      }}
                      // A split's members draw the selection on the split's card.
                      marked={!row.kind.groupsTabs && marked(tabItem(tab.id))}
                      held={holds(selection, tabItem(tab.id))}
                      lifted={isLifted(tab.id)}
                      unit={row.kind.groupsTabs ? null : tabItem(tab.id)}
                      insertsBefore={insertsBefore && !row.kind.groupsTabs}
                      aimedAround={lift?.aim?.kind === "aroundTab" && lift.aim.tabId === tab.id}
                      onPress={(event) => !renamesTab && pressRow(tabItem(tab.id), { kind: "tab", id: tab.id }, event)}
                      onSelect={(event) => activates(event) && activate(tab.id)}
                      onClose={() => close(tab.id)}
                      onMiddleClick={() => middleClick(tab)}
                      onContextMenu={(event) => rowMenu(event, tabItem(tab.id), () => tabMenu(context, tab))}
                      onRenamed={finishRename}
                    />
                  );
                });
                const splitMarked = row.kind.groupsTabs && row.members.some((id) => marked(tabItem(id)));
                return [...gap, ...(row.kind.groupsTabs ? [(
                  <div key={row.id} className={`split-card${splitMarked ? " unit-selected" : ""}${insertsBefore ? " drop-before" : ""}`}
                    data-row={row.id} data-before-tab={row.members[0]} data-unit={row.members.map(tabItem).join(",")}>
                    {groupId && (
                      <SplitGroupHeader session={session} space={space} groupId={groupId} group={group} members={memberTabs}
                        focusedId={focusedMember} pagesByTab={pagesByTab} depth={row.depth}
                        // Where the window's selection holds a member, the menu is its tabs'.
                        onMenu={(event) => {
                          if (!row.members.some((id) => marked(tabItem(id)))) return false;
                          rowMenu(event, tabItem(row.members[0]), () => tabMenu(context, memberTabs[0]));
                          return true;
                        }} />
                    )}
                    {content}
                  </div>
                )] : content)];
              })}
            </section>
            );
          })}
          <button className="sidebar-row new-tab-row" onClick={() => openPalette("newTab")}>
            <Symbol name="plus" />
            <span className="row-title">New Tab</span>
          </button>
        </div>
      </LayoutGroup>
      </>
    );
  };

  return (
    <aside ref={aside} className="sidebar">
      {showsNavigation && (
        <div className="sidebar-toolbar">
          <span className="window-drag" />
          <NavigationButtons browsing={browsing} page={page} />
        </div>
      )}
      {/* An open utility list's search stands where the address field stood, as on the Mac. */}
      {!utility && <div className="address-area">
        <AddressField
          address={live?.address ?? live?.url ?? ""}
          // A live site's controls: its lock, which opens its certificate, and Site Controls.
          site={siteControlPage ? {
            secure: siteControlPage.live.security.isSecure,
            certificate: certificates.length > 0,
            reviewCertificate: () => void session.shell?.certificate(certificates),
            open: siteControlsOpen,
            notice: popupNotice,
            toggle: () => setSiteControlsOpen((open) => !open),
          } : null}
          secure={live ? live.security.isSecure : !!tabs.get(shownTabId ?? "")?.url?.toLowerCase().startsWith("https:")}
        />
        <PermissionPrompt session={session} asked={permission} spaceName={space.settings.name} />
        <AnimatePresence>
          {siteControlPage && siteControlsOpen && !permission && (
            <SiteControlPanel key="site-control" session={session} browsing={browsing} page={siteControlPage} space={space}
              isPrivate={session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false}
              certificates={certificates} notice={popupNotice}
              onAllowPopups={() => void blockedPopups.allow(session.core,
                { pageId: siteControlPage.id, spaceId: siteControlPage.spaceId, url: siteControlPage.live.url })}
              onClose={closeSiteControls} />
          )}
        </AnimatePresence>
      </div>}

      <SpacePageStrip spaces={spaces} liveId={space.id} gestureArea={aside} render={renderPage} />

      <SpaceSwitcher
        spaces={spaces}
        selectedId={space.id}
        onSelect={(spaceId) => {
          pageStills.leaving(session.core);
          void session.core.send(ShowSpace({ windowId: session.windowId, spaceId }));
        }}
        leading={<ChromeButton symbol="sidebar.left" label={docked ? "Hide Sidebar" : "Dock Sidebar"} onClick={onToggleDock} />}
        trailing={(
          <CommonListsButton session={session} button={listsButton} expanded={utility !== null} chosen={chosen}
            downloads={profileDownloads} newDownloads={newDownloads} badgeColor={space.settings.look.colors.colors[0] ?? indigo}
            onToggle={toggleLists} onChoose={(surface) => {
              chooseSurface(space.id, surface);
              setChoices((count) => count + 1);
            }} />
        )}
      />
      {/* Over the page beside the sidebar, in the window's colours, whatever moves the sidebar's card. */}
      {windowElement && createPortal(
        <UtilityFan expanded={utility !== null} trigger={listsButton} selected={utility}
          badgeColor={space.settings.look.colors.colors[0] ?? indigo} downloads={profileDownloads}
          newDownloadCount={newDownloads.length} onSelect={setUtility} />,
        windowElement,
      )}
      <AnimatePresence>
        {folderLook && (() => {
          const folder = folders.get(folderLook.folderId);
          if (!folder) return null;
          const { workspaceId } = session;
          const send = (intent: Parameters<typeof session.core.send>[0]) => void session.core.send(intent).catch(() => {});
          const close = () => setFolderLook(null);
          const drawn = folder.displaySymbol !== "folder" && folder.displaySymbol !== "folder.fill";
          return folderLook.kind === "color" ? (
            <Popover key="folder-color" anchor={folderLook.anchor} label={folder.isGroup ? "Group Color" : "Folder Color"} onClose={close}>
              <ColorPicker title={folder.isGroup ? "Group Color" : "Folder Color"} color={folder.displayColor} resetTitle={null}
                onChoose={(color) => send(SetFolderColor({ workspaceId, spaceId: space.id, folderId: folder.id, color }))} onReset={close} />
            </Popover>
          ) : (
            <Popover key="folder-icon" anchor={folderLook.anchor} label="Folder Icon" onClose={close}>
              <EmojiPicker title="Folder Icon" current={emojiOf(folder.displaySymbol)} resetTitle={drawn ? "Use Folder Icon" : null}
                onChoose={(emoji) => {
                  send(SetFolderSymbol({ workspaceId, spaceId: space.id, folderId: folder.id, symbol: `crest.emoji:${emoji}` }));
                  close();
                }}
                onReset={() => {
                  send(SetFolderSymbol({ workspaceId, spaceId: space.id, folderId: folder.id, symbol: "folder" }));
                  close();
                }} />
            </Popover>
          );
        })()}
      </AnimatePresence>
      {lift && <LiftPreview session={session} lift={lift} tab={lift.item.kind === "tab" ? tabs.get(lift.item.id) : undefined}
        folder={lift.item.kind === "folder" ? folders.get(lift.item.id) : undefined}
        pageId={lift.item.kind === "tab" ? pagesByTab.get(lift.item.id) ?? null : null} />}
    </aside>
  );
}

/**
 * What a lift carries, under the pointer where it grabbed it, as the Mac's
 * lift preview: a row, or a tile for a pinned tab, a little larger than
 * itself, with a shadow; and why the aimed drop is refused, beside it.
 */
function LiftPreview({ session, lift, tab, folder, pageId }: {
  session: Session; lift: Lift; tab: TabState | undefined; folder: FolderState | undefined; pageId: string | null;
}) {
  const tile = tab?.placement === TabPlacement.pinned && lift.aim?.kind === "list" && lift.aim.section === TabPlacement.pinned;
  // Over the page area the row becomes the page card it would be, as the
  // Mac's preview does: 240 by 160, the icon large over the title.
  const card = lift.aim?.kind === "split";
  const width = card ? 240 : tile ? 52 : Math.min(364, Math.max(220, lift.width));
  const height = card ? 160 : tile ? 52 : 40;
  const left = lift.pointer.x - (card ? width / 2 : Math.min(lift.grab.x, width));
  const top = lift.pointer.y - (card ? height / 2 : Math.min(lift.grab.y, height));
  return (
    <>
      <div className={`lift-preview${tile ? " tile" : ""}${card ? " card" : ""}`} style={{ left, top, width, height }} aria-hidden>
        {tab && <TabIcon session={session} tab={tab} pageId={pageId} size={card ? 32 : tile ? 20 : 16} />}
        {folder && <Symbol name="folder.fill" />}
        {!tile && <span className="row-title">{tab?.displayTitle ?? folder?.title}</span>}
      </div>
      {lift.refusal && (
        <div className="lift-refusal" style={{ left: lift.pointer.x + 12, top: top + height + 12 }} role="status">
          <Symbol name="nosign" size={12} />
          {lift.refusal}
        </div>
      )}
    </>
  );
}

interface TabRowProps {
  readonly session: Session;
  readonly tab: TabState;
  readonly pageId: string | null;
  readonly depth: number;
  readonly selected: boolean;
  /** Whether the row's title is a field the person is renaming the tab in. */
  readonly renaming: boolean;
  /** The sidebar row this tab is, for a lift's aim; null for a split's member. */
  readonly row: { readonly id: string; readonly aroundTab: boolean } | null;
  /** What a click selects on this row; null for a split's member, whose card is the unit. */
  readonly unit: SelectionItem | null;
  /** Whether the row draws itself selected for tab actions, and whether the selection holds it. */
  readonly marked: boolean;
  readonly held: boolean;
  /** Whether a lift carries this tab now. */
  readonly lifted: boolean;
  /** Whether a lift would land just above this row. */
  readonly insertsBefore: boolean;
  /** Whether a lift aims to make a folder around this tab. */
  readonly aimedAround: boolean;
  readonly onPress: (event: React.PointerEvent<HTMLElement>) => void;
  readonly onSelect: (event: MouseEvent) => void;
  readonly onClose: () => void;
  readonly onMiddleClick: () => void;
  readonly onContextMenu: (event: MouseEvent) => void;
  /** The rename ended: with the title to keep, or null when cancelled. */
  readonly onRenamed: (title: string | null) => void;
}

function TabRow({
  session, tab, pageId, depth, selected, renaming, row, unit, marked, held, lifted, insertsBefore, aimedAround, onPress,
  onSelect, onClose, onMiddleClick, onContextMenu, onRenamed,
}: TabRowProps) {
  return (
    <div
      role="button"
      tabIndex={0}
      className={`sidebar-row tab-row${selected ? " selected" : ""}${marked ? " unit-selected" : ""}${lifted ? " lifted" : ""}${insertsBefore ? " drop-before" : ""}${aimedAround ? " drop-nest" : ""}`}
      style={{ paddingInlineStart: 10 + depth * 14 }}
      data-row={row?.id}
      data-before-tab={row ? tab.id : undefined}
      data-around-tab={row?.aroundTab ? tab.id : undefined}
      data-unit={unit ?? undefined}
      aria-selected={held}
      onPointerDown={onPress}
      onClick={renaming ? undefined : onSelect}
      onAuxClick={(event: MouseEvent) => event.button === 1 && onMiddleClick()}
      onContextMenu={onContextMenu}
      {...previewHandlers(tab.id)}
    >
      <AnimatePresence>
        {selected && (
          <motion.span
            layoutId="tab-selection"
            className="row-selection"
            transition={tokens.collection}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          />
        )}
      </AnimatePresence>
      <TabIcon session={session} tab={tab} pageId={pageId} />
      {renaming
        ? <RenameField initial={tab.displayTitle} placeholder="Tab Name" onDone={onRenamed} />
        : <span className="row-title">{tab.displayTitle}</span>}
      <button
        className="row-close"
        aria-label="Close Tab"
        title="Close Tab"
        onClick={(event) => {
          event.stopPropagation();
          onClose();
        }}
      >
        <Symbol name="xmark" size={12} />
      </button>
    </div>
  );
}

/** A folder or group header: a click opens or closes it, as the Mac's does. */
function FolderRow({
  folder, depth, renaming, marked, held, lifted, insertsBefore, aimedInto, onPress, onToggle, onContextMenu, onRenamed,
}: {
  folder: FolderState;
  depth: number;
  renaming: boolean;
  /** Whether the row draws itself selected for tab actions, and whether the selection holds it. */
  marked: boolean;
  held: boolean;
  /** Whether a lift carries this folder now. */
  lifted: boolean;
  /** Whether a lift would land just above this row. */
  insertsBefore: boolean;
  /** Whether a lift aims to drop inside this collapsed folder. */
  aimedInto: boolean;
  onPress: (event: React.PointerEvent<HTMLElement>) => void;
  onToggle: (event: MouseEvent) => void;
  onContextMenu: (event: MouseEvent) => void;
  onRenamed: (title: string | null) => void;
}) {
  return (
    <div
      role="button"
      tabIndex={0}
      className={`sidebar-row folder-row${marked ? " unit-selected" : ""}${lifted ? " lifted" : ""}${insertsBefore ? " drop-before" : ""}${aimedInto ? " drop-into" : ""}`}
      style={{ paddingInlineStart: 10 + depth * 14 }}
      data-row={folder.id}
      data-before-folder={folder.id}
      data-folder={folder.id}
      data-collapsed={String(folder.isCollapsed)}
      data-location={folder.location.name}
      data-unit={folderItem(folder.id)}
      aria-selected={held}
      onPointerDown={onPress}
      onClick={renaming ? undefined : onToggle}
      onContextMenu={onContextMenu}
    >
      <FolderArtwork symbol={folder.displaySymbol} color={folder.displayColor} expanded={!folder.isCollapsed} />
      {renaming
        ? <RenameField initial={folder.title} placeholder={folder.isGroup ? "Group Name" : "Folder Name"} onDone={onRenamed} />
        : <span className="row-title">{folder.title}</span>}
    </div>
  );
}

/**
 * A title being renamed in place, as the Mac's rename field: it starts with
 * the whole name selected; Enter or leaving it keeps the name, and Escape
 * cancels.
 */
function RenameField({ initial, placeholder, onDone }: {
  initial: string;
  placeholder: string;
  onDone: (title: string | null) => void;
}) {
  const [draft, setDraft] = useState(initial);
  const [ended, setEnded] = useState(false);
  const end = (title: string | null) => {
    if (ended) return;
    setEnded(true);
    onDone(title);
  };
  return (
    <input
      className="rename-field"
      value={draft}
      placeholder={placeholder}
      aria-label={placeholder}
      spellCheck={false}
      autoFocus
      onFocus={(event) => event.currentTarget.select()}
      onChange={(event) => setDraft(event.target.value)}
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event: KeyboardEvent<HTMLInputElement>) => {
        if (event.key === "Enter") end(draft);
        else if (event.key === "Escape") end(null);
      }}
      onBlur={() => end(draft)}
    />
  );
}

export function TabIcon({ session, tab, pageId, size = 16 }: { session: Session; tab: TabState; pageId: string | null; size?: number }) {
  const [failed, setFailed] = useState(false);
  const engineIcon = useTabIcon(session, tab.id, pageId, tab.faviconUrl);
  // Inside Crest a site's icon comes from its page's engine; in development,
  // from the site.
  const icon = insideCrest ? engineIcon : (tab.faviconUrl ?? (tab.url ? faviconFor(tab.url) : null));
  if (icon && !failed) {
    return <img className="tab-icon" src={icon} width={size} height={size} alt="" onError={() => setFailed(true)} />;
  }
  return <Symbol name={tab.symbol} size={size} className="tab-icon" />;
}

function faviconFor(url: string): string | null {
  try {
    const { origin, protocol } = new URL(url);
    return protocol.startsWith("http") ? `${origin}/favicon.ico` : null;
  } catch {
    return null;
  }
}

/**
 * The shown tab's address, which opens the command palette to edit it, as
 * the Mac's sidebar address field does; typing an address happens there. A
 * live site puts its lock in the leading slot and Site Controls in the
 * trailing one; without one, the lock or the search glyph stands in.
 */
function AddressField({ address, site, secure }: {
  address: string;
  site: {
    readonly secure: boolean;
    readonly certificate: boolean;
    readonly reviewCertificate: () => void;
    readonly open: boolean;
    readonly notice: BlockedPopupNotice | null;
    readonly toggle: () => void;
  } | null;
  secure: boolean;
}) {
  // The field fades out while the palette that grew out of it is open, keeping its place.
  const handedOff = useFieldHandedOff();
  return (
    <div className={`address-field${handedOff ? " handed-off" : ""}`}>
      {site
        ? <AddressSecurityButton secure={site.secure} certificate={site.certificate} onReview={site.reviewCertificate} />
        : <Symbol name={secure ? "lock.fill" : "magnifyingglass"} size={13} className="address-glyph" />}
      <button type="button" className="address-summary" aria-label="Edit Location" onClick={() => openPalette("editLocation")}>
        <span className={`address-text ${address ? "" : "placeholder"}`}>{address || "Search or Enter URL…"}</span>
      </button>
      {site && <SiteControlTrigger open={site.open} notice={site.notice} onToggle={site.toggle} />}
    </div>
  );
}

