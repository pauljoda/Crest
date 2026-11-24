<script lang="ts" module>
  import type { PageState, PermissionAsked, SpaceState } from "@crest/contracts";

  import type { Session } from "../../boot";
  import type { Browsing } from "../../browsing";
  import type { Downloads } from "../../downloads.svelte";
  import type { SidebarDialog } from "../SidebarDialogs.svelte";
  import type { PracticeSidebar } from "./sidebar-parts.svelte";

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
    /** The Getting Started practice this sidebar serves, if it is the practice's rather than the window's. */
    readonly practice?: PracticeSidebar;
  }
</script>

<script lang="ts">
  import {
    ChooseTabIcon,
    ClearCurrentTabs,
    CollapseFolder,
    ExpandSavedTabs,
    type FolderState,
    type HistoryEntryState,
    OpenTab,
    ReleasePage,
    RenameFolder,
    RenameTab,
    SetFolderColor,
    SetFolderSymbol,
    ShowTab,
    type SidebarList,
    TabIconMode,
    TabPlacement,
    type TabState,
  } from "@crest/contracts";
  import { untrack } from "svelte";

  import { portal } from "../../attachments";
  import { css, emojiOf, indigo, primaryColor } from "../../branding";
  import { openPalette, toggleUtilityEvent } from "../../commands";
  import { type MenuEntry, showContextMenu } from "../../menus";
  import { residentNativeTabs } from "../../native-tabs";
  import { showSpace } from "../../spaces/show-space";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { spacePager } from "../../spaces/space-pager";
  import { CommonListsButton, UtilityFan } from "../../utilities/CommonLists";
  import { chooseSurface, chosenSurface, type UtilitySurfaceName } from "../../utilities/utility-list";
  import UtilityList from "../../utilities/UtilityList.svelte";
  import SpacePageStrip from "../../spaces/SpacePageStrip.svelte";
  import { SpaceIdentityIcon } from "../../spaces/SpaceIdentity";
  import SpaceSwitcher from "../../spaces/SpaceSwitcher.svelte";
  import { isLocked } from "../../spaces/space-access";
  import { coreState, useCoreVersion } from "../../use-core";
  import ChromeButton from "../ChromeButton.svelte";
  import NavigationButtons from "../NavigationButtons.svelte";
  import PermissionPrompt from "../prompts/PermissionPrompt.svelte";
  import { blockedPopups, useBlockedPopups } from "../blocked-popups";
  import { useCertificates } from "../site-control.svelte";
  import { PinnedExtensionStrip } from "../ExtensionActions";
  import { SiteControlPanel } from "../SiteControl";
  import { droppedJustNow, type LiftItem, useSidebarLift } from "../sidebar-drag.svelte";
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
  } from "../sidebar-menus";
  import {
    allSelected,
    clicked,
    folderItem,
    holds,
    inOtherSpace,
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
  } from "../sidebar-selection";
  import SidebarScrollAffordance from "../SidebarScrollAffordance.svelte";
  import SplitGroupHeader from "../SplitGroupHeader.svelte";
  import { previewHandlers, showsTabPreviews } from "../TabPreview.svelte";
  import { ColorPicker, EmojiPicker, Popover } from "../pickers";
  import AddressField from "./AddressField.svelte";
  import CurrentTabsDivider from "./CurrentTabsDivider.svelte";
  import FolderRow from "./FolderRow.svelte";
  import LiftPreview from "./LiftPreview.svelte";
  import PinnedGrid from "./PinnedGrid.svelte";
  import PinnedTileFace from "./PinnedTileFace.svelte";
  import { folderTabCount, useTabSelectionSurface } from "./sidebar-parts.svelte";
  import TabRow from "./TabRow.svelte";

  /**
   * The window's sidebar: navigation, the address field, the Space's pinned
   * tiles, its organized and open tabs, and the Space switcher. Rows come from
   * the core's sidebar outline, which already orders and nests them.
   */
  let {
    session, browsing, space, spaces, shownTabId, shownTabs, page, pagesByTab, showsNavigation, permission, downloads, onDialog,
    docked, onToggleDock, practice,
  }: SidebarProps = $props();

  let aside = $state<HTMLElement | null>(null);

  // The window's utility list, as the Mac's utility presentation: the list
  // open in place of the Space's tabs, if any. The Common Lists button opens
  // the list chosen for the Space, or Downloads while downloads finished
  // unseen, and closes it; Show Downloads opens or closes Downloads.
  let utility = $state<UtilitySurfaceName | null>(null);
  let choices = $state(0);
  let listsButton = $state<HTMLButtonElement | null>(null);
  const chosen = $derived.by(() => {
    void choices;
    return chosenSurface(space.id);
  });
  const profileDownloads = $derived.by(() => (useCoreVersion(session), downloads?.of(space.profileId) ?? []));
  const newDownloads = $derived(profileDownloads.filter((download) => !download.isAcknowledged));
  const toggleLists = () => {
    utility = utility ? null : newDownloads.length > 0 ? "downloads" : chosen;
  };
  $effect(() => {
    // The practice's sidebar opens none of the window's lists.
    if (practice) return;
    const toggle = (event: Event) => {
      const surface = (event as CustomEvent<UtilitySurfaceName>).detail;
      utility = utility === surface ? null : surface;
    };
    window.addEventListener(toggleUtilityEvent, toggle);
    return () => window.removeEventListener(toggleUtilityEvent, toggle);
  });
  const dismissUtility = () => {
    utility = null;
  };
  // The search and the filter are the window's, shared by its Spaces, and start over with each list.
  let utilitySearch = $state("");
  let utilityFilter = $state("all");
  $effect(() => {
    void utility;
    untrack(() => {
      utilitySearch = "";
      utilityFilter = "all";
    });
  });
  // A click on the page puts the list away, as the Mac's web content interaction does.
  $effect(() => {
    if (!utility) return;
    const onFocus = (event: FocusEvent) => {
      if (event.target instanceof HTMLEmbedElement) utility = null;
    };
    document.addEventListener("focusin", onFocus);
    return () => document.removeEventListener("focusin", onFocus);
  });
  let windowElement = $state<HTMLElement | null>(null);
  $effect(() => {
    windowElement = aside?.closest<HTMLElement>(".browser-window") ?? null;
  });
  // A history entry opens in a new tab after the one on show, as the Mac's list opens it.
  const openHistoryEntry = (entry: HistoryEntryState) => void send(session, OpenTab({
    workspaceId: session.workspaceId, windowId: session.windowId, spaceId: space.id, tabId: crypto.randomUUID(),
    content: { address: entry.url, view: null, title: null }, placement: TabPlacement.current, afterTabId: shownTabId,
    shows: true, placesAsNewTab: false, savesInSavedFolder: false,
  }));
  const tabs = $derived(new Map(space.tabs.map((tab) => [tab.id, tab])));
  const folders = $derived(new Map(space.folders.map((folder) => [folder.id, folder])));
  const show = (tabId: string) => void session.core.send(ShowTab({ windowId: session.windowId, spaceId: space.id, tabId }));
  // A tab is resident without a page while one of Crest's own views holds it,
  // and every practice tab is, as the Mac's practice reads its tabs as loaded.
  // The views come and go beside the core's changes, so each change reads them again.
  const residesWithoutPage = (tabId: string) => (useCoreVersion(session), !!practice || residentNativeTabs.has(tabId));
  const close = (tabId: string) => void browsing.closeTab(space.id, tabId);
  // A rename belongs to the Space it started in.
  let renaming = $state.raw<Renaming>(null);
  // A folder's icon or colour being chosen, in a popover beside its row.
  let folderLook = $state.raw<{ folderId: string; kind: "icon" | "color"; anchor: DOMRect } | null>(null);
  let tabLook = $state.raw<{ tabId: string; anchor: DOMRect } | null>(null);
  $effect(() => {
    void space.id;
    untrack(() => {
      renaming = null;
    });
  });

  // Site Controls act for the shown page while it has an address, and go
  // with the Space or the page they opened for, as the Mac's popover does.
  const siteControlPage = $derived(page?.live.url ? page : null);
  const certificates = useCertificates(() => ({ session, page: siteControlPage }));
  const popupNotice = $derived.by(() => {
    const popups = useBlockedPopups();
    return siteControlPage ? popups.notice(siteControlPage.id) : null;
  });
  let siteControlsOpen = $state(false);
  const closeSiteControls = () => {
    siteControlsOpen = false;
  };
  $effect(() => {
    void space.id;
    void siteControlPage?.id;
    untrack(closeSiteControls);
  });

  // The window's selection, which the Mac's sidebar keeps beside the shown
  // tab and the core never sees. It belongs to the Space it was made in.
  let selection = $state.raw<SidebarSelection>(noSelection);
  const select = (next: SidebarSelection) => {
    selection = next;
  };
  $effect(() => {
    void space.id;
    untrack(() => select(noSelection));
  });
  // A change to the outline keeps only what the sidebar still shows.
  $effect(() => {
    void space.sidebar;
    void space.tabs;
    void space.folders;
    untrack(() => {
      const next = reconciled(selection, unitsShown(aside));
      if (next !== selection) select(next);
    });
  });
  // Pinned tabs a lift let go of shake, as the Mac's do.
  let shaken = $state.raw<ReadonlySet<string>>(new Set());
  $effect(() => {
    if (shaken.size === 0) return;
    const timer = setTimeout(() => {
      shaken = new Set();
    }, 360);
    return () => clearTimeout(timer);
  });
  const activeItem = $derived(shownTabId ? tabItem(shownTabId) : null);
  /** The units the sidebar shows, and the selection over them as of now. */
  const selectionOverRows = () => {
    const units = unitsShown(aside);
    return { units, current: reconciled(selection, units) };
  };

  const context: SidebarContext = {
    get session() {
      return session;
    },
    get space() {
      return space;
    },
    get spaces() {
      return spaces;
    },
    get shownTabId() {
      return shownTabId;
    },
    get pagesByTab() {
      return pagesByTab;
    },
    rename: (item) => {
      const tab = "tabId" in item ? tabs.get(item.tabId) : undefined;
      // A pinned tile has no room for a field, so it asks in a dialog.
      if (tab?.placement === TabPlacement.pinned) onDialog({ kind: "renameTab", spaceId: space.id, tab });
      else renaming = item;
    },
    confirmDeleteFolder: (folder) => onDialog({ kind: "deleteFolder", spaceId: space.id, folder }),
    chooseLook: (folder, kind) => {
      const row = [...document.querySelectorAll<HTMLElement>(`[data-folder="${folder.id}"]`)].find((element) => !inOtherSpace(element));
      if (row) folderLook = { folderId: folder.id, kind, anchor: row.getBoundingClientRect() };
    },
    chooseTabIcon: (tab) => {
      const shownPage = aside?.querySelector(".space-page:not([aria-hidden])") ?? aside;
      const row = shownPage?.querySelector<HTMLElement>(`[data-row="${tab.id}"], [data-before-tab="${tab.id}"], [data-unit~="${tabItem(tab.id)}"]`);
      if (row) tabLook = { tabId: tab.id, anchor: row.getBoundingClientRect() };
    },
    addToSelection: (item) => {
      const { units, current } = selectionOverRows();
      select(clicked(current, item, units, { command: true, shift: false }, activeItem));
    },
    selectAll: () => select(allSelected(unitsShown(aside))),
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
  // svelte-ignore state_referenced_locally
  const sidebarLift = useSidebarLift(session, () => space.id, () => ({
    releasePins: (pins) => {
      const current = selection;
      const released = (item: SelectionItem | null) => item !== null && itemParts(item).kind === "tab" && pins.includes(itemParts(item).id);
      const items = new Set([...current.items].filter((item) => !released(item)));
      const first = [...items][0] ?? null;
      select({
        ...current, items, rangeBase: null,
        anchor: released(current.anchor) ? first : current.anchor,
        focused: released(current.focused) ? first : current.focused,
      });
      shaken = new Set(pins);
    },
    landed: ({ leftSpace, selected: picks, copies }) => select(leftSpace ? noSelection : allSelected(rootItems(picks, copies))),
  }));
  const lift = $derived(sidebarLift.lift);
  const press = sidebarLift.press;
  // A drag in flight owns the horizontal axis, so the Space strip holds still under it.
  const lifting = $derived(lift !== null);
  $effect(() => {
    const locked = lifting;
    untrack(() => spacePager.setLocked(locked));
  });
  /**
   * A press on a row, as the Mac's selection monitor sees it before the row:
   * Ctrl or Shift selects and goes no further; a plain press selects a row
   * the selection does not hold, quietly, and otherwise keeps the selection,
   * so pulling the row lifts every pick.
   */
  const pressRow = (item: SelectionItem, lifted: LiftItem, event: PointerEvent & { currentTarget: HTMLElement }) => {
    if (event.button !== 0) return;
    const { units, current } = selectionOverRows();
    if (event.ctrlKey || event.shiftKey) {
      select(clicked(current, item, units, { command: event.ctrlKey, shift: event.shiftKey }, activeItem));
      return;
    }
    const picked = pickedWith(current, item, units);
    if (!picked) {
      select(clicked(current, item, units, { command: false, shift: false }, activeItem));
      press(lifted, event);
      return;
    }
    select(current);
    const parts = picked.map(itemParts);
    press({
      ...lifted,
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
  const takeKey = (key: SelectionKey): boolean => {
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
      && !!aside?.contains(active) && !!active.closest("[data-unit]");
    if (!selectionHasKeyboard(current) && !onRow) return false;
    if (current !== selection) select(current);
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
      [...(aside?.querySelectorAll<HTMLElement>("[data-unit]") ?? [])]
        .filter((element) => element.offsetParent !== null && !inOtherSpace(element))[index]
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
  const takeClose = (): boolean => {
    const { units, current } = selectionOverRows();
    if (!selectionHasKeyboard(current) || !current.focused) return false;
    const picked = pickedWith(current, current.focused, units);
    if (!picked || (picked.length === 1 && picked[0] === activeItem)) return false;
    void act(picked, "close");
    return true;
  };
  $effect(() => {
    const onKey = (event: KeyboardEvent) => {
      const key = { code: event.keyCode, control: event.ctrlKey, shift: event.shiftKey, alt: event.altKey };
      if (!takeKey(key)) return;
      event.preventDefault();
      event.stopPropagation();
    };
    // A press anywhere but a row lets the selection go, as does the page taking the keys.
    const onPress = (event: PointerEvent) => {
      if (event.target instanceof Element && event.target.closest("[data-unit]")) return;
      if (selection !== noSelection) select(noSelection);
    };
    const onFocus = (event: FocusEvent) => {
      if (event.target instanceof HTMLEmbedElement && selection.engaged) select(noSelection);
    };
    window.addEventListener("keydown", onKey, true);
    window.addEventListener("pointerdown", onPress, true);
    document.addEventListener("focusin", onFocus);
    const unregister = registerSelectionTaker((command, key) =>
      (command === "closeTabOrWindow" && takeClose()) || (key !== null && takeKey(key)));
    return () => {
      window.removeEventListener("keydown", onKey, true);
      window.removeEventListener("pointerdown", onPress, true);
      document.removeEventListener("focusin", onFocus);
      unregister();
    };
  });

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

  const liftedFolders = $derived.by(() => {
    const carried = lift?.item.carried;
    const found = new Set<string>(carried ? carried.folderIds : lift?.item.kind === "folder" ? [lift.item.id] : []);
    if (found.size > 0) {
      for (let grew = true; grew;) {
        grew = false;
        for (const folder of space.folders) {
          if (folder.parentId && found.has(folder.parentId) && !found.has(folder.id)) {
            found.add(folder.id);
            grew = true;
          }
        }
      }
    }
    return found;
  });
  const isLifted = (tabId: string) => {
    const carried = lift?.item.carried;
    return carried ? carried.tabIds.includes(tabId) : lift?.item.kind === "tab" && lift.item.id === tabId;
  };
  const gapAt = (section: TabPlacement, folderId: string | null, beforeRow: string | null) =>
    lift?.aim?.kind === "list" && lift.aim.section === section && lift.aim.folderId === folderId && lift.aim.gapBefore === beforeRow;
  const finishRename = (title: string | null) => {
    const current = renaming;
    renaming = null;
    if (!current || title === null) return;
    const { workspaceId } = session;
    if ("tabId" in current) void send(session, RenameTab({ workspaceId, spaceId: space.id, tabId: current.tabId, title }));
    else void send(session, RenameFolder({ workspaceId, spaceId: space.id, folderId: current.folderId, title }));
  };
  // A locked Space's address field shows nothing of its tabs.
  const shownLocked = $derived.by(() => (useCoreVersion(session), isLocked(session.core, space)));
  const live = $derived(shownLocked ? undefined : page?.live);
  // A live site's controls: its lock, which opens its certificate, and Site Controls.
  const addressSite = $derived(siteControlPage && !shownLocked ? {
    secure: siteControlPage.live.security.isSecure,
    certificate: certificates.current.length > 0,
    reviewCertificate: () => void session.shell?.certificate(certificates.current),
    open: siteControlsOpen,
    notice: popupNotice,
    toggle: () => {
      siteControlsOpen = !siteControlsOpen;
    },
  } : null);

  const toggleSavedTabs = (pageSpace: SpaceState) => void session.core.send(ExpandSavedTabs({
    workspaceId: session.workspaceId, spaceId: pageSpace.id, isExpanded: !pageSpace.settings.isSavedTabsExpanded,
  }));
  const isPinnedTop = (list: SidebarList) => list.section.name === "pinned" && list.folderId === null;
  const isCurrentTop = (list: SidebarList) => list.folderId === null && list.section.name === "current";
  const openNewTab = () => (practice ? practice.openExampleTab() : openPalette("newTab"));
  // The card says what the tile is, where the person keeps previews, which each change reads again.
  const tileTitle = (tab: TabState) => (useCoreVersion(session), showsTabPreviews() ? undefined : tab.displayTitle);

  /**
   * What the shown Space's page draws as the person uses it. A page a slide
   * shows beside it is drawn still: no selection, lift or rename of its own.
   */
  const pageView = (pageSpace: SpaceState, isLive: boolean) => {
    const pageTabs = isLive ? tabs : new Map(pageSpace.tabs.map((tab) => [tab.id, tab]));
    const pageShownTabId = isLive ? shownTabId : shownTabs.get(pageSpace.id) ?? null;
    const pageLift = isLive ? lift : null;
    const pageIsLifted = isLive ? isLifted : () => false;
    // The practice always shows its saved tabs, as the Mac's does.
    const savedTabsExpanded = !!practice || pageSpace.settings.isSavedTabsExpanded;
    const pinned = pageSpace.sidebar.lists.filter(isPinnedTop);
    // Clear on the line archives the open tabs but the one the window shows
    // and the rest of its split, or every open tab.
    // What it clears is what the open tabs' rows hold, at the top level and in folders, as the Mac's seam reads them.
    const shownSplitId = pageShownTabId ? pageTabs.get(pageShownTabId)?.splitGroupId ?? null : null;
    const openTabs = pageSpace.sidebar.lists.filter((list) => list.section === TabPlacement.current)
      .flatMap((list) => list.rows.flatMap((row) => (row.kind.name === "folder" ? [] : row.kind.groupsTabs ? row.members : [row.id])))
      .flatMap((id) => pageTabs.get(id) ?? []);
    return {
      tabs: pageTabs,
      folders: isLive ? folders : new Map(pageSpace.folders.map((folder) => [folder.id, folder])),
      shownTabId: pageShownTabId,
      selection: isLive ? selection : noSelection,
      lift: pageLift,
      renaming: isLive ? renaming : null,
      shaken: isLive ? shaken : new Set<string>(),
      liftedFolders: isLive ? liftedFolders : new Set<string>(),
      marked: isLive ? marked : () => false,
      isLifted: pageIsLifted,
      gapAt: isLive ? gapAt : () => false,
      savedTabsExpanded,
      pinnedTabs: pinned.flatMap((list) => list.rows).flatMap((row) => pageTabs.get(row.id) ?? []),
      pinnedCount: pinned.reduce((count, list) => count + list.rows.filter((row) => pageTabs.has(row.id) && !pageIsLifted(row.id)).length, 0),
      showsPins: pinned.some((list) => list.rows.length > 0) || !!pageLift,
      // The saved tabs show while the header has them open.
      rest: pageSpace.sidebar.lists.filter((list) => !isPinnedTop(list) && (savedTabsExpanded || list.section.name !== "saved")),
      canClearAll: isLive && openTabs.length > 0,
      canClearOthers: isLive && openTabs.some((tab) => tab.id !== pageShownTabId && (shownSplitId === null || tab.splitGroupId !== shownSplitId)),
    };
  };
  type PageView = ReturnType<typeof pageView>;

  /**
   * A folder's own list follows its header, as the Mac draws it. A closed
   * folder keeps only its loaded tabs on show, and a closed group only the
   * tab the window shows.
   */
  const folderList = (view: PageView, folder: FolderState): SidebarList | null => {
    const inside = view.rest.find((candidate) => candidate.folderId === folder.id);
    if (!inside) return null;
    if (!folder.isCollapsed) return inside;
    const keeps = (id: string) => (folder.isGroup ? id === view.shownTabId
      : pagesByTab.has(id) || residesWithoutPage(id) || id === view.shownTabId);
    const rows = inside.rows.filter((candidate) => candidate.kind.name !== "folder" && candidate.members.concat(candidate.id).some(keeps));
    return { ...inside, rows };
  };

  // The selection under the shown tab moves between each page's rows as Motion's shared layout moved it.
  useTabSelectionSurface(() => aside, () => [
    useCoreVersion(session), space, spaces, shownTabId, shownTabs, page, pagesByTab, showsNavigation, permission, docked, practice,
    utility, selection, lift, renaming, shaken, siteControlsOpen, folderLook, tabLook,
  ]);

  // The folder or tab whose look is being chosen, while it stands.
  const lookedFolder = $derived(folderLook ? folders.get(folderLook.folderId) ?? null : null);
  const lookedTab = $derived(tabLook ? tabs.get(tabLook.tabId) ?? null : null);
  const sendLook = (intent: Parameters<typeof session.core.send>[0]) => void session.core.send(intent).catch(() => {});
  const closeFolderLook = () => {
    folderLook = null;
  };
  const closeTabLook = () => {
    tabLook = null;
  };
  const chooseTabLook = (tab: TabState, mode: TabIconMode, emoji: string | null) => {
    void session.core.send(ChooseTabIcon({
      workspaceId: session.workspaceId, spaceId: space.id, tabId: tab.id, mode, emoji, accent: null,
    })).catch(() => {});
    closeTabLook();
  };
</script>

<!-- One Space's page of the sidebar, as the Mac's BrowserSidebarSpacePage: its pins, its header and its tabs. -->
{#snippet renderPage(pageSpace: SpaceState, isLive: boolean)}
  {@const view = pageView(pageSpace, isLive)}
  {#snippet newTabRow()}
    <button class="sidebar-row new-tab-row" onclick={openNewTab}>
      <span class="row-glyph"><SymbolIcon name="plus" /></span>
      <span class="row-title">New Tab</span>
    </button>
  {/snippet}
  {#snippet clearLine()}
    <CurrentTabsDivider canClearAll={view.canClearAll} canClearOthers={view.canClearOthers}
      onClear={(all) => void send(session, ClearCurrentTabs({
        workspaceId: session.workspaceId, windowId: session.windowId, spaceId: pageSpace.id, keepsShownTab: !all,
      }))} />
  {/snippet}
  {#snippet renderList(list: SidebarList)}
    <section
      class={`tab-section${isCurrentTop(list) ? " current-tabs" : ""}${list.folderId && view.liftedFolders.has(list.folderId) ? " lifted" : ""}${view.gapAt(list.section, list.folderId, null) ? " drop-at-end" : ""}`}
      data-list-section={list.section.name}
      data-list-folder={list.folderId ?? ""}
    >
      {#if isCurrentTop(list)}
        {@render clearLine()}
        {@render newTabRow()}
      {/if}
      {#each list.rows as row (row.id)}
        {@const insertsBefore = view.gapAt(list.section, list.folderId, row.id)}
        {#if row.kind.name === "folder"}
          {@const folder = view.folders.get(row.id)}
          {#if folder}
            {@const renamesFolder = view.renaming !== null && "folderId" in view.renaming && view.renaming.folderId === folder.id}
            {@const inside = folderList(view, folder)}
            <FolderRow
              {folder}
              tabCount={folderTabCount(pageSpace, folder.id)}
              depth={row.depth}
              renaming={renamesFolder}
              marked={view.marked(folderItem(folder.id))}
              held={holds(view.selection, folderItem(folder.id))}
              lifted={view.liftedFolders.has(folder.id)}
              {insertsBefore}
              aimedInto={view.lift?.aim?.kind === "folder" && view.lift.aim.folderId === folder.id}
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
            {#if inside}
              {@render renderList(inside)}
            {/if}
          {/if}
        {:else}
          {@const members = row.kind.groupsTabs ? row.members : [row.id]}
          {@const memberTabs = members.map((id) => view.tabs.get(id)).filter((tab): tab is TabState => !!tab)}
          <!-- A split's group, whose collapsed header keeps only the tab the window shows. -->
          {@const groupId = row.kind.groupsTabs ? memberTabs[0]?.splitGroupId ?? null : null}
          {@const group = groupId ? pageSpace.splitGroups.find((candidate) => candidate.id === groupId) ?? null : null}
          {@const focusedMember = memberTabs.find((tab) => tab.id === view.shownTabId)?.id ?? null}
          {@const listed = group?.isCollapsed ? memberTabs.filter((tab) => tab.id === focusedMember) : memberTabs}
          {#snippet tabRows()}
            {#each listed as tab (tab.id)}
              {@const renamesTab = view.renaming !== null && "tabId" in view.renaming && view.renaming.tabId === tab.id}
              <!-- A current tab at the top level, in no split, may have a folder made around it; a split's members
                   draw the selection on the split's card. -->
              <TabRow
                {session}
                {tab}
                pageId={pagesByTab.get(tab.id) ?? null}
                resident={residesWithoutPage(tab.id)}
                depth={row.kind.groupsTabs ? row.depth + 1 : row.depth}
                inSplit={row.kind.groupsTabs}
                selected={tab.id === view.shownTabId}
                renaming={renamesTab}
                row={row.kind.groupsTabs ? null : { id: row.id, aroundTab: list.section === TabPlacement.current && list.folderId === null }}
                marked={!row.kind.groupsTabs && view.marked(tabItem(tab.id))}
                held={holds(view.selection, tabItem(tab.id))}
                lifted={view.isLifted(tab.id)}
                unit={row.kind.groupsTabs ? null : tabItem(tab.id)}
                insertsBefore={insertsBefore && !row.kind.groupsTabs}
                aimedAround={view.lift?.aim?.kind === "aroundTab" && view.lift.aim.tabId === tab.id}
                onPress={(event) => !renamesTab && pressRow(tabItem(tab.id), { kind: "tab", id: tab.id }, event)}
                onSelect={(event) => activates(event) && activate(tab.id)}
                onClose={() => close(tab.id)}
                onMiddleClick={() => middleClick(tab)}
                onContextMenu={(event) => rowMenu(event, tabItem(tab.id), () => tabMenu(context, tab))}
                onRenamed={finishRename}
              />
            {/each}
          {/snippet}
          {#if row.kind.groupsTabs}
            {@const splitMarked = row.members.some((id) => view.marked(tabItem(id)))}
            <div class={`split-card${splitMarked ? " unit-selected" : ""}${insertsBefore ? " drop-before" : ""}`}
              data-row={row.id} data-before-tab={row.members[0]} data-unit={row.members.map(tabItem).join(",")}>
              {#if groupId}
                <!-- Where the window's selection holds a member, the menu is its tabs'. -->
                <SplitGroupHeader {session} space={pageSpace} {groupId} {group} members={memberTabs}
                  focusedId={focusedMember} {pagesByTab} depth={row.depth}
                  onMenu={(event) => {
                    if (!row.members.some((id) => view.marked(tabItem(id)))) return false;
                    rowMenu(event, tabItem(row.members[0]), () => tabMenu(context, memberTabs[0]));
                    return true;
                  }} />
              {/if}
              {@render tabRows()}
            </div>
          {:else}
            {@render tabRows()}
          {/if}
        {/if}
      {/each}
    </section>
  {/snippet}
  {#snippet content()}
    {#if !practice}
      <PinnedExtensionStrip {session} space={pageSpace} pageId={page?.id ?? null} pageKey={`${page?.live.url ?? ""}|${page?.live.title ?? ""}`} />
    {/if}
    {#if view.showsPins}
      <PinnedGrid className={`pinned-grid${view.gapAt(TabPlacement.pinned, null, null) ? " drop-at-end" : ""}`}
        count={view.pinnedCount} data-list-section={TabPlacement.pinned.name} data-list-folder="">
        {#each view.pinnedTabs as tab (tab.id)}
          {@const pageId = pagesByTab.get(tab.id) ?? null}
          {@const loaded = residesWithoutPage(tab.id) || (pageId !== null && coreState(session).pages.get(pageId)?.phase.name === "live")}
          <!-- The card says what the tile is, where the person keeps previews. -->
          <!-- svelte-ignore a11y_role_supports_aria_props_implicit -->
          <button
            type="button"
            class={`pinned-tile${tab.id === view.shownTabId ? " selected" : ""}${loaded ? "" : " unloaded"}${view.marked(tabItem(tab.id)) ? " unit-selected" : ""}${view.shaken.has(tab.id) ? " shaken" : ""}${view.isLifted(tab.id) ? " lifted" : ""}${view.gapAt(TabPlacement.pinned, null, tab.id) ? " drop-before" : ""}`}
            data-row={tab.id}
            data-before-tab={tab.id}
            data-unit={tabItem(tab.id)}
            aria-selected={holds(view.selection, tabItem(tab.id))}
            onpointerdown={(event) => pressRow(tabItem(tab.id), { kind: "tab", id: tab.id }, event)}
            onclick={(event) => activates(event) && activate(tab.id)}
            onauxclick={(event) => event.button === 1 && middleClick(tab)}
            oncontextmenu={(event) => rowMenu(event, tabItem(tab.id), () => tabMenu(context, tab))}
            {...previewHandlers(tab.id)}
            title={tileTitle(tab)}
          >
            <PinnedTileFace {session} {tab} {pageId} />
          </button>
        {/each}
      </PinnedGrid>
    {/if}

    <!-- The practice names its saved tabs under a caption, where the window's sidebar has the Space's header. -->
    {#if practice}
      <p class="practice-saved-caption">Saved</p>
    {:else}
      <div class={`space-header${view.showsPins ? "" : " without-pins"}`}>
        <button
          class="space-header-title"
          onclick={() => toggleSavedTabs(pageSpace)}
          aria-label={`${pageSpace.settings.name} saved tabs`}
          aria-expanded={view.savedTabsExpanded}
          {...{ "aria-description": view.savedTabsExpanded ? "Collapses saved tabs" : "Expands saved tabs" }}
        >
          <!-- The crest and the chevron share one slot, so the title never shifts as the saved tabs open. -->
          <span class={`space-header-identity${view.savedTabsExpanded ? "" : " collapsed"}`} aria-hidden="true">
            <span class="space-header-crest">
              <SpaceIdentityIcon symbol={pageSpace.settings.symbol} branding={pageSpace.settings.look} size={20} />
            </span>
            <span class="space-header-chevron"><SymbolIcon name="chevron.right" size={9} strokeWidth={3} /></span>
          </span>
          <span class="space-name">{pageSpace.settings.name}</span>
          {#if pageSpace.settings.requiresAuthentication}
            <span class="space-header-lock" aria-label="Private Space"><SymbolIcon name="lock.fill" size={10} strokeWidth={3} /></span>
          {/if}
        </button>
        <ChromeButton symbol="ellipsis" label="Space Actions" className="space-header-actions" onClick={(button) => {
          const bounds = button.getBoundingClientRect();
          void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom }, spaceHeaderMenu(context));
        }} />
      </div>
    {/if}

    <!-- The list scrolls under its own affordance: an indicator while it moves, and Show more tabs at rest. -->
    <div class="tab-list-scroll">
      <!-- The empty area offers the Space's own actions, and a double click opens a new tab, as on the Mac. -->
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div
        class="tab-list"
        oncontextmenu={(event) => {
          if (!practice && event.target === event.currentTarget) menu(event, backgroundMenu(context));
        }}
        ondblclick={(event) => {
          if (event.target === event.currentTarget) openNewTab();
        }}
      >
        <!-- The current tabs always stand under the divider, the New Tab row at their top, as on the Mac. -->
        {#each view.rest.filter((list) => list.folderId === null && (list.rows.length > 0 || view.lift || isCurrentTop(list))) as list (`${list.section.name}-${list.folderId ?? "root"}`)}
          {@render renderList(list)}
        {/each}
        {#if !view.rest.some(isCurrentTop)}
          <section class="tab-section current-tabs">{@render clearLine()}{@render newTabRow()}</section>
        {/if}
      </div>
      {#if isLive}
        <SidebarScrollAffordance dragging={!!view.lift} />
      {/if}
    </div>
  {/snippet}
  <!-- An open utility list takes the shown Space's page: its pins, its header
       and its tabs. Another Space's page a slide passes shows nothing. -->
  {#if utility}
    {#if isLive}
      <UtilityList {session} surface={utility} space={pageSpace} {spaces} {downloads}
        searchText={utilitySearch} onSearchText={(text) => (utilitySearch = text)}
        filterName={utilityFilter} onFilterName={(name) => (utilityFilter = name)}
        onOpenHistory={openHistoryEntry} onRestored={show} onClearHistory={() => onDialog({ kind: "clearHistory", spaceId: pageSpace.id })}
        onDismiss={dismissUtility} />
    {/if}
  {:else if (useCoreVersion(session), isLocked(session.core, pageSpace))}
    <!-- A locked Space's page shows blurred and redacted, and takes nothing, as the Mac's. -->
    <div class="space-page-locked" inert aria-hidden="true" data-testid="space-page-locked">{@render content()}</div>
  {:else}
    {@render content()}
  {/if}
{/snippet}

<aside bind:this={aside} class={`sidebar${practice ? " practice-sidebar" : ""}`}>
  {#if practice}
    <!-- The practice has one Space, and no Space strip to slide. -->
    <div class="space-pages"><div class="space-page">{@render renderPage(space, true)}</div></div>
  {/if}
  {#if !practice && showsNavigation}
    <div class="sidebar-toolbar">
      <span class="window-drag"></span>
      <NavigationButtons {browsing} {page} />
    </div>
  {/if}
  <!-- An open utility list's search stands where the address field stood, as on the Mac. -->
  {#if !practice && !utility}
    <div class="address-area">
      <AddressField
        space={space.id}
        address={shownLocked ? "" : live?.address ?? live?.url ?? tabs.get(shownTabId ?? "")?.url ?? ""}
        site={addressSite}
        secure={live ? live.security.isSecure : !shownLocked && !!tabs.get(shownTabId ?? "")?.url?.toLowerCase().startsWith("https:")}
        resident={!!page}
        loading={!!live?.isLoading}
        accent={css(primaryColor(space.settings.look))}
      />
      <PermissionPrompt {session} asked={permission} spaceName={space.settings.name} />
      {#if siteControlPage && siteControlsOpen && !permission}
        <SiteControlPanel {session} {browsing} page={siteControlPage} {space}
          isPrivate={coreState(session).workspaces.get(session.workspaceId)?.kind.isPrivate ?? false}
          certificates={certificates.current} notice={popupNotice}
          onAllowPopups={() => void blockedPopups.allow(session.core,
            { pageId: siteControlPage.id, spaceId: siteControlPage.spaceId, url: siteControlPage.live.url })}
          onClose={closeSiteControls} />
      {/if}
    </div>
  {/if}

  {#if !practice}
    <SpacePageStrip {spaces} liveId={space.id} gestureArea={aside} render={renderPage} />
  {/if}

  {#if !practice}
    <SpaceSwitcher
      {spaces}
      selectedId={space.id}
      onSelect={(spaceId) => void showSpace(session.core, session.windowId, spaceId).catch(() => undefined)}
    >
      {#snippet leading()}
        <ChromeButton symbol="sidebar.left" label={docked ? "Hide Sidebar" : "Dock Sidebar"} onClick={onToggleDock} />
      {/snippet}
      {#snippet trailing()}
        <CommonListsButton {session} bind:button={listsButton} expanded={utility !== null} {chosen}
          downloads={profileDownloads} {newDownloads} badgeColor={space.settings.look.colors.colors[0] ?? indigo}
          onToggle={toggleLists} onChoose={(surface) => {
            chooseSurface(space.id, surface);
            choices += 1;
          }} />
      {/snippet}
    </SpaceSwitcher>
  {/if}
  <!-- Over the page beside the sidebar, in the window's colours, whatever moves the sidebar's card. -->
  {#if !practice && windowElement}
    <div style:display="contents" {@attach portal(() => windowElement)}>
      <UtilityFan expanded={utility !== null} trigger={listsButton} selected={utility}
        badgeColor={space.settings.look.colors.colors[0] ?? indigo} downloads={profileDownloads}
        newDownloadCount={newDownloads.length} onSelect={(surface) => (utility = surface)} />
    </div>
  {/if}
  {#if folderLook?.kind === "color" && lookedFolder}
    <Popover anchor={folderLook.anchor} label={lookedFolder.isGroup ? "Group Color" : "Folder Color"} onClose={closeFolderLook}>
      <ColorPicker title={lookedFolder.isGroup ? "Group Color" : "Folder Color"} color={lookedFolder.displayColor} resetTitle={null}
        onChoose={(color) => sendLook(SetFolderColor({ workspaceId: session.workspaceId, spaceId: space.id, folderId: lookedFolder.id, color }))}
        onReset={closeFolderLook} />
    </Popover>
  {/if}
  {#if folderLook?.kind === "icon" && lookedFolder}
    {@const drawn = lookedFolder.displaySymbol !== "folder" && lookedFolder.displaySymbol !== "folder.fill"}
    <Popover anchor={folderLook.anchor} label="Folder Icon" onClose={closeFolderLook}>
      <EmojiPicker title="Folder Icon" current={emojiOf(lookedFolder.displaySymbol)} resetTitle={drawn ? "Use Folder Icon" : null}
        onChoose={(emoji) => {
          sendLook(SetFolderSymbol({ workspaceId: session.workspaceId, spaceId: space.id, folderId: lookedFolder.id, symbol: `crest.emoji:${emoji}` }));
          closeFolderLook();
        }}
        onReset={() => {
          sendLook(SetFolderSymbol({ workspaceId: session.workspaceId, spaceId: space.id, folderId: lookedFolder.id, symbol: "folder" }));
          closeFolderLook();
        }} />
    </Popover>
  {/if}
  {#if tabLook && lookedTab}
    <!-- The Mac's BrowserIconCustomizationPresentation for a tab. -->
    <Popover anchor={tabLook.anchor} label="Tab Icon" onClose={closeTabLook}>
      <EmojiPicker title="Tab Icon" current={emojiOf(lookedTab.symbol)}
        resetTitle={lookedTab.iconMode.followsPage ? null : "Use Website Icon"}
        onChoose={(emoji) => chooseTabLook(lookedTab, TabIconMode.emoji, emoji)}
        onReset={() => chooseTabLook(lookedTab, TabIconMode.automatic, null)} />
    </Popover>
  {/if}
  {#if lift}
    <LiftPreview {session} {lift} tab={lift.item.kind === "tab" ? tabs.get(lift.item.id) : undefined}
      folder={lift.item.kind === "folder" ? folders.get(lift.item.id) : undefined}
      pageId={lift.item.kind === "tab" ? pagesByTab.get(lift.item.id) ?? null : null} />
  {/if}
</aside>
