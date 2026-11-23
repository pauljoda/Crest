import {
  AdjacentDirection,
  DiscardStagedLink,
  MovePage,
  NativeView,
  Navigate,
  OpenTab,
  OpenPage,
  type PageState,
  type PaletteCommand,
  PagePresentation,
  type PeekRequested,
  PromoteTransientPage,
  readEnginePresentation,
  ReleasePage,
  ResizeSplitColumns,
  type ShortcutBinding,
  type ShortcutCommand,
  ShortcutModifiers,
  ShowAdjacentSpace,
  ShowSpace,
  ShowStartPage,
  ShowTab,
  type SpaceState,
  StageLink,
  TabPlacement,
  TabSurface,
  TransientPresentation,
  WireReader,
} from "@crest/contracts";
import { CoreRejection, type ShellShortcut } from "@crest/core-client";
import { AnimatePresence } from "motion/react";
import { type CSSProperties, type RefObject, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";

import type { Session } from "../boot";
import { primaryColor, readsLight } from "../branding";
import { Browsing } from "../browsing";
import { openPaletteEvent, spaceEditing, windowCommands, type WindowView } from "../commands";
import { useDownloads } from "../downloads";
import { copiedNotice, notices } from "../notices";
import { CommandPalette } from "../palette/CommandPalette";
import { PaletteModel, type PaletteMode } from "../palette/palette-model";
import { commandForKey, keyCapture, keyCode, WindowShortcuts } from "../shortcuts";
import { setSpaceStepper, spacePager, useSpacePager } from "../spaces/space-pager";
import { SpaceContentStrip } from "../spaces/SpaceContentStrip";
import { RecentTabSwitcher, releasesHold, type SwitcherControls, type SwitcherHold, type SwitcherStart } from "../switcher/RecentTabSwitcher";
import { pageStills } from "../spaces/page-stills";
import { TabPictures } from "../switcher/tab-pictures";
import type { SettingsPageName } from "../settings/catalog";
import { extensions } from "../extensions";
import { suggestionFetcher } from "../palette/suggestions";
import { GettingStartedView } from "../guide/GettingStartedView";
import { resumeSpaceDeletions } from "../spaces/space-deletion";
import { isLocked, lockWhenCrestInactive } from "../spaces/space-access";
import { SpaceAccessView } from "../spaces/SpaceAccessView";
import { requestSettings, SettingsView } from "../settings/SettingsView";
import { useCoreVersion } from "../use-core";
import { NavigationButtons } from "./NavigationButtons";
import { Notices } from "./Notices";
import { blockedPopups } from "./blocked-popups";
import { FindBar } from "./FindBar";
import { focusShownPage, PageCard } from "./PageCard";
import { type ColumnCard, PageColumns } from "./PageColumns";
import { usePagePresentation } from "./page-presentation";
import { pageTools, usePageTools } from "./page-tools";
import { type Peek, PeekLayer } from "./PeekLayer";
import { DownloadFlights } from "./DownloadFlights";
import { showsTabPreviews, TabPreviewLayer } from "./TabPreview";
import { DownloadApproval } from "./prompts/DownloadApproval";
import { ExtensionReviewLayer } from "./prompts/ExtensionReview";
import { downloadApproval, permissionPrompt, sheetPrompt } from "./prompts/prompt-text";
import { PromptSheet } from "./prompts/PromptSheet";
import { Sidebar } from "./Sidebar";
import { captureSidebar, initialSidebarIsPresented, initialSidebarWidth } from "./sidebar-layout";
import { type SelectionKey, selectionTakes } from "./sidebar-selection";
import { type SidebarDialog, SidebarDialogLayer } from "./SidebarDialogs";
import { type SidebarMorph, type SidebarPresentation, SidebarSlot } from "./SidebarSlot";
import { spaceCards } from "./shown-cards";
import { SpaceBanner } from "./SpaceBanner";
import { StartPage } from "./StartPage";
import { TitleBar } from "./TitleBar";
import { useWindowIsCornerless } from "./WindowControls";

/**
 * One Crest window: the Space's banner behind everything, the sidebar over it
 * and the page card beside it. What the window shows is the core's window
 * state; the window opens a page for the tab it shows when none is open.
 */
export function BrowserWindow({ session }: { session: Session }) {
  useCoreVersion(session);
  const browsing = useMemo(() => new Browsing(session), [session]);
  const downloads = useDownloads(session);
  const state = session.core.state;
  const window = state.windows.get(session.windowId);
  const workspace = state.workspaces.get(session.workspaceId);
  const spaces = (workspace?.order ?? []).map((id) => workspace!.spaces.get(id)).filter((space): space is SpaceState => !!space);
  const space = window ? workspace?.spaces.get(window.shownSpaceId) : undefined;
  const shownTabId = window?.shownTabs.find((shown) => shown.spaceId === window.shownSpaceId)?.tabId ?? null;
  const shownTabs = new Map((window?.shownTabs ?? []).flatMap((shown) => (shown.tabId ? [[shown.spaceId, shown.tabId] as const] : [])));

  // The Space pager follows the Space the window shows, and asks for the one a swipe settles on.
  const spaceIds = spaces.map((candidate) => candidate.id).join();
  useLayoutEffect(() => {
    if (!space) return;
    spacePager.update(spaceIds.split(","), space.id, (spaceId) => {
      pageStills.leaving(session.core);
      void session.core.send(ShowSpace({ windowId: session.windowId, spaceId }));
    });
  }, [session, spaceIds, space?.id]);
  useEffect(() => setSpaceStepper((direction) => {
    spacePager.noteStep(direction);
    pageStills.leaving(session.core);
    void session.core.send(ShowAdjacentSpace({
      windowId: session.windowId, direction: direction > 0 ? AdjacentDirection.next : AdjacentDirection.previous,
    }));
  }), [session]);
  // A Space whose deletion the last launch began goes now, as the Mac's window carries it on.
  useEffect(() => void resumeSpaceDeletions(session), [session]);
  // Spaces that ask for authentication lock once Crest is no longer in front, as the Mac's do.
  useEffect(() => lockWhenCrestInactive(session), [session]);
  const pages = [...state.pages.values()].filter((candidate) => candidate.phase.holdsEnginePage);
  const pagesByTab = new Map(pages.flatMap((candidate) => (candidate.tabId ? [[candidate.tabId, candidate.id] as const] : [])));
  const page = pages.find((candidate) => candidate.tabId === shownTabId) ?? null;
  const opening = useRef(new Set<string>());
  const tab = space?.tabs.find((candidate) => candidate.id === shownTabId);

  // What the page card shows is the core's answer for the shown tab. A tab
  // whose surface is a page and that has none restores itself, as the Mac's
  // window restores the tab it shows.
  const presentation = usePagePresentation(session.core, {
    surface: tab?.surface ?? null,
    hasPage: page !== null,
    hasNavigationFailure: !!page?.live.failure,
    hasProcessFailure: false,
    restoresUnloaded: true,
  });
  const showsStartPage = presentation === PagePresentation.startPage;

  // Entering a Space shows the pages it holds, but does not open its
  // remembered unloaded tab on the person's behalf: the window shows a Start
  // Page there instead, as the Mac's does. The tab the session remembers
  // stays as it was.
  const enteredSpace = useRef<string | null>(null);
  const enteringSpace = useRef<string | null>(null);
  const [entries, settleEntry] = useState(0);
  useEffect(() => {
    const previous = enteredSpace.current;
    enteredSpace.current = space?.id ?? null;
    if (!space || previous === null || previous === space.id) return;
    if (tab?.surface !== TabSurface.webPage || page) return;
    const spaceId = space.id;
    enteringSpace.current = spaceId;
    void session.core.send(ShowStartPage({
      workspaceId: session.workspaceId, windowId: session.windowId, spaceId, tabId: crypto.randomUUID(),
      outsideSplits: true, placesAsNewTab: false,
    })).catch((error: unknown) => {
      if (!(error instanceof CoreRejection)) throw error;
    }).finally(() => {
      if (enteringSpace.current === spaceId) enteringSpace.current = null;
      settleEntry((count) => count + 1);
    });
    // Only entering another Space asks this.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [space?.id]);

  // Each card the window shows opens its own tab's page (SpaceCard); a page's
  // first load goes through the core's Navigate.
  const loading = useRef(new Set<string>());

  // The Peek a link opened over the page that followed it, which shows while
  // that page's tab is the one the window shows. A Peek that goes back into
  // its link lets its page go once it has, and one kept as a tab, or closed
  // by its page, leaves at once.
  const [peek, setPeek] = useState<Peek | null>(null);
  const peekNow = useRef<Peek | null>(null);
  peekNow.current = peek;
  const peekAnimates = useRef(true);
  const releasing = useRef(new Set<string>());
  const closePeek = useCallback((animated: boolean, releases = true) => {
    const current = peekNow.current;
    if (!current) return;
    peekNow.current = null;
    peekAnimates.current = animated;
    if (releases) {
      if (animated) releasing.current.add(current.pageId);
      else void session.core.send(ReleasePage({ pageId: current.pageId, keepsState: false })).catch(() => {});
    }
    setPeek(null);
    // The keyboard goes back to the page beneath.
    requestAnimationFrame(focusShownPage);
  }, [session]);
  const letPeeksGo = useCallback(() => {
    for (const pageId of releasing.current) void session.core.send(ReleasePage({ pageId, keepsState: false })).catch(() => {});
    releasing.current.clear();
  }, [session]);
  // The pages the window's cards show, which a link followed in opens a Peek over.
  const shownPages = useRef<ReadonlySet<string>>(new Set());
  const openPeek = useCallback(async (request: PeekRequested) => {
    const source = session.core.state.pages.get(request.pageId);
    if (!source?.tabId || !shownPages.current.has(source.id)) return;
    const { stagedLinkId } = request;
    const discard = () => stagedLinkId
      && void session.core.send(DiscardStagedLink({ sourcePageId: source.id, stagedLinkId })).catch(() => {});
    // A link followed while a Peek is open takes its place.
    closePeek(false);
    const pageId = crypto.randomUUID();
    try {
      await session.core.send(OpenPage({
        pageId, workspaceId: session.workspaceId, spaceId: source.spaceId, tabId: null, windowId: session.windowId,
        transient: TransientPresentation.peek, openerPageId: source.id,
      }));
    } catch {
      discard();
      return;
    }
    // The page's first load runs the link the source page staged, keeping its referrer and security.
    if (stagedLinkId) {
      try {
        await session.core.send(StageLink({ pageId, sourcePageId: source.id, stagedLinkId, url: request.url }));
      } catch {
        discard();
        void session.core.send(ReleasePage({ pageId, keepsState: false })).catch(() => {});
        return;
      }
    }
    peekAnimates.current = true;
    setPeek({ pageId, sourcePageId: source.id, sourceTabId: source.tabId, spaceId: source.spaceId, url: request.url });
    void session.core.send(Navigate({ pageId, input: request.url })).catch(() => {});
  }, [session, closePeek]);
  // Open In keeps the Peek's page as a tab of a Space, which the window then
  // shows: the tab takes the live page where it can, or loads it afresh.
  // The new tab opens no page of its own until it has taken the Peek's.
  const adopting = useRef(false);
  const openPeekIn = useCallback(async (spaceId: string) => {
    const current = peekNow.current;
    if (!current || adopting.current) return;
    adopting.current = true;
    try {
      await session.core.send(PromoteTransientPage({
        workspaceId: session.workspaceId, windowId: session.windowId, pageId: current.pageId, spaceId,
        placement: TabPlacement.current,
      }));
      const outcome = session.core.state.transientOutcomes.get(current.pageId);
      if (outcome?.$kind !== "TransientPagePromoted") return;
      closePeek(false, false);
      await session.core.send(outcome.adoptsPage
        ? MovePage({ pageId: current.pageId, workspaceId: session.workspaceId, spaceId, tabId: outcome.tabId, windowId: session.windowId })
        : ReleasePage({ pageId: current.pageId, keepsState: false })).catch(() => {});
    } catch {
      // A refused promotion leaves the Peek as it was.
    } finally {
      adopting.current = false;
      settleEntry((count) => count + 1);
    }
  }, [session, closePeek]);
  // A Peek whose page closed itself, or whose link's tab left, goes at once.
  const peekOutcome = peek ? state.transientOutcomes.get(peek.pageId) : undefined;
  const peekPageGone = peek ? !state.pages.has(peek.pageId) : false;
  const peekSourceGone = peek ? !spaces.some((candidate) => candidate.tabs.some((other) => other.id === peek.sourceTabId)) : false;
  useEffect(() => {
    if (peekOutcome?.$kind === "TransientPageClosed" || peekPageGone) closePeek(false, false);
    else if (peekSourceGone) closePeek(false);
  }, [peekOutcome, peekPageGone, peekSourceGone, closePeek]);
  const showsPeek = peek !== null && peek.sourceTabId === shownTabId;

  // The window's commands act on what it shows now, from the keys the core
  // binds them to on this device, for the commands the window can run now.
  const shownCards = space ? spaceCards(window, space.id, shownTabId).tabIds : [];
  const shown = useRef<WindowView>({ space, tab, page, cards: shownCards });
  shown.current = { space, tab, page, cards: shownCards };

  // Pictures of the pages the window shows, for the recent-tab switcher:
  // taken once a page has shown for a second and a half, and again after it
  // finishes loading or goes somewhere else.
  const pictures = useMemo(() => new TabPictures(), []);
  useEffect(() => () => {
    pictures.clear();
    pageStills.clear();
  }, [pictures]);
  const pictured = shownCards.flatMap((tabId) => {
    const shownPage = pages.find((candidate) => candidate.tabId === tabId);
    return shownPage?.phase.name === "live" && shownPage.live.url && !shownPage.live.isLoading
      ? [{ pageId: shownPage.id, tabId, address: shownPage.live.url }] : [];
  });
  const picturedNow = useRef(pictured);
  picturedNow.current = pictured;
  const picturedKey = pictured.map((entry) => `${entry.pageId} ${entry.address}`).join();
  useEffect(() => {
    if (!session.shell || !picturedKey) return;
    const timer = setTimeout(() => {
      for (const entry of picturedNow.current) pictures.capture(session.core, entry);
    }, 1500);
    return () => clearTimeout(timer);
  }, [session, pictures, picturedKey]);

  // The recent-tab switcher, while the keys of Most Recent Tab are held. The
  // window gives it the keyboard on the first press, before it draws.
  const [switcher, setSwitcher] = useState<{ readonly start: SwitcherStart; readonly key: number } | null>(null);
  const switcherStart = useRef<SwitcherStart | null>(null);
  const switcherControls = useRef<SwitcherControls | null>(null);
  const switcherKeys = useRef<HTMLDivElement>(null);
  const registerSwitcher = useCallback((controls: SwitcherControls | null) => {
    switcherControls.current = controls;
  }, []);
  const endSwitcher = useCallback(() => {
    switcherStart.current = null;
    switcherControls.current = null;
    setSwitcher(null);
    requestAnimationFrame(focusShownPage);
  }, []);
  const keys = useMemo(() => new WindowShortcuts(session.shell), [session]);
  useEffect(() => keys.install(), [keys]);
  const bindings = state.shortcuts?.bindings;
  const unavailable = window?.unavailableCommands;
  const offered = useRef({ bindings, unavailable });
  offered.current = { bindings, unavailable };

  // The command palette, as the Mac's: New Tab opens it with nothing typed,
  // Open Location with the shown tab's address, and the same keys put it
  // away again. Any other command puts it away before it runs.
  const [palette, setPalette] = useState<PaletteModel | null>(null);
  // A question the sidebar asks over the page, such as confirming a folder's deletion.
  const [dialog, setDialog] = useState<SidebarDialog | null>(null);
  // Where the sidebar is: Ctrl+S hides it or docks it again, and its own
  // button floats it over the page or docks it, as on the Mac. The window
  // keeps whether it is shown, and its width, on this device.
  const sidebarMorph = useRef<SidebarMorph | null>(null);
  const [sidebar, setSidebar] = useState<SidebarPresentation>(
    () => (initialSidebarIsPresented(session.windowId) ? "docked" : "collapsed"));
  const [sidebarWidth, setSidebarWidth] = useState(() => initialSidebarWidth(session.windowId));
  const committedWidth = useRef(sidebarWidth);
  const commitSidebarWidth = useCallback((width: number) => {
    if (width === committedWidth.current) return;
    committedWidth.current = width;
    captureSidebar(session.windowId, { width });
  }, [session.windowId]);
  const presentedBefore = useRef(sidebar === "docked");
  useEffect(() => {
    const presented = sidebar === "docked";
    if (presented === presentedBefore.current) return;
    presentedBefore.current = presented;
    captureSidebar(session.windowId, { isPresented: presented });
  }, [sidebar, session.windowId]);
  const current = useRef<PaletteModel | null>(null);
  current.current = palette;
  const dismissPalette = useCallback(() => {
    if (!current.current) return;
    current.current.close();
    current.current = null;
    setPalette(null);
    // The page takes the keyboard back once the palette's field is gone.
    requestAnimationFrame(focusShownPage);
  }, []);
  /** Copies an answer a palette gives, such as the calculator's. */
  const copyAnswer = useCallback((text: string) => {
    if (!session.shell) return;
    void session.shell.copy(text);
    notices.post(copiedNotice);
  }, [session]);
  const commands = useMemo(() => {
    const base = windowCommands(session, browsing, () => shown.current);
    const handlers: Record<string, () => void> = {};
    // The sidebar's selection answers its keys before any command, and Close
    // Tab archives it, while it has the keyboard, as the Mac's does.
    const keysOf = (name: string): SelectionKey | null => {
      const bound = offered.current.bindings?.find((binding) => binding.command.name === name)?.keys;
      const code = bound ? keyCode(bound) : null;
      if (!bound || code === null) return null;
      const held = (modifier: number) => (bound.modifiers & modifier) !== 0;
      return { code, control: held(ShortcutModifiers.Command), shift: held(ShortcutModifiers.Shift), alt: held(ShortcutModifiers.Option) };
    };
    for (const [name, run] of Object.entries(base)) {
      if (run) handlers[name] = () => {
        if (selectionTakes(name, keysOf(name))) return;
        dismissPalette();
        run();
      };
    }
    const open = (kind: "newTab" | "editLocation") => {
      const { space: shownSpace, tab: shownTab, page: shownPage } = shown.current;
      if (!shownSpace) return;
      current.current?.close();
      const mode: PaletteMode = kind === "newTab" ? { kind }
        : { kind, address: shownTab?.url ?? shownPage?.live.url ?? "" };
      const model = new PaletteModel({
        core: session.core,
        // Crest's Chromium fetches the search engine's suggestions, as the Mac app does.
        fetchSuggestions: suggestionFetcher(session.shell),
        windowId: session.windowId,
        workspaceId: session.workspaceId,
        spaceId: shownSpace.id,
        tabId: shownTab?.id ?? null,
        pageId: shownPage?.id ?? null,
        get commands() {
          return paletteCommands(offered.current.bindings ?? [], offered.current.unavailable ?? [], handlers);
        },
        runCommand: (name) => handlers[name]?.(),
        copy: copyAnswer,
        dismiss: dismissPalette,
        openSettings: (page) => openSettings(page),
      }, mode);
      current.current = model;
      setPalette(model);
    };
    const toggle = (kind: "newTab" | "editLocation") => () => {
      if (current.current?.mode.kind === kind) dismissPalette();
      else open(kind);
    };
    // On a Start Page, New Tab puts the overlay away and gives the page's own
    // palette the keyboard, starting over, as the Mac's does.
    const startPageTakesNewTab = () => {
      if (shown.current.tab?.surface !== TabSurface.startPage) return false;
      dismissPalette();
      const tabId = shown.current.tab.id;
      setStartPageFocus((request) => ({ tabId, count: request.count + 1 }));
      return true;
    };
    handlers.newTab = () => startPageTakesNewTab() || toggle("newTab")();
    handlers.openLocation = toggle("editLocation");
    handlers.toggleSidebar = () => {
      dismissPalette();
      sidebarMorph.current?.toggle();
    };
    handlers.openPalette = () => startPageTakesNewTab() || open("newTab");
    handlers.editLocation = () => open("editLocation");
    // Settings is a tab of a Space, one to a Space: Ctrl+, shows the shown
    // Space's, or opens it. Edit Space… opens it on a Space's own page.
    const openSettings = (page?: string, spaceId?: string) => {
      dismissPalette();
      const { space: shownSpace, tab: shownTab } = shown.current;
      const target = spaceId ? session.core.state.workspaces.get(session.workspaceId)?.spaces.get(spaceId) : shownSpace;
      if (!target) return;
      const existing = target.tabs.find((candidate) => candidate.nativeView === NativeView.settings);
      const tabId = existing?.id ?? crypto.randomUUID();
      if (page) {
        // A Space's own pages are its Space's.
        requestSettings(tabId, ["spaces", "passwords", "extensions", "appearance"].includes(page)
          ? { kind: "space", spaceId: target.id, tab: page === "extensions" || page === "appearance" ? page : undefined }
          : { kind: "page", name: page as SettingsPageName });
      }
      if (existing) {
        void session.core.send(ShowTab({ windowId: session.windowId, spaceId: target.id, tabId: existing.id })).catch(() => {});
        return;
      }
      void session.core.send(OpenTab({
        workspaceId: session.workspaceId, windowId: session.windowId, spaceId: target.id, tabId,
        content: { address: null, view: NativeView.settings, title: null }, placement: TabPlacement.current,
        afterTabId: target.id === shownSpace?.id ? shownTab?.id ?? null : null,
        shows: true, placesAsNewTab: false, savesInSavedFolder: false,
      })).catch(() => {});
    };
    handlers.openSettings = () => openSettings();
    extensions.openSettings = () => openSettings("extensions");
    spaceEditing.open = (spaceId) => openSettings("appearance", spaceId);
    // Close Tab closes a Peek shown over the tab first, and Esc, which the
    // window holds while one shows, closes it too.
    const peekShown = () => !!peekNow.current && peekNow.current.sourceTabId === shown.current.tab?.id;
    const closeTab = handlers.closeTabOrWindow;
    handlers.closeTabOrWindow = () => (peekShown() ? closePeek(true) : closeTab?.());
    handlers.closePeek = () => peekShown() && closePeek(true);
    // Most Recent Tab holds the switcher open while its keys are held, as
    // the Mac's does where the person shows recent tabs while switching and
    // the keys hold a modifier; otherwise it goes straight to the tab.
    const recentTab = (direction: 1 | -1) => () => {
      if (switcherControls.current) return switcherControls.current.step(direction);
      if (switcherStart.current) {
        switcherStart.current.steps += direction;
        return;
      }
      const name = direction > 0 ? "mostRecentTab" : "mostRecentTabBackward";
      const keys = offered.current.bindings?.find((binding) => binding.command.name === name)?.keys;
      const hold: SwitcherHold | null = keys ? {
        control: (keys.modifiers & ShortcutModifiers.Command) !== 0,
        shift: (keys.modifiers & ShortcutModifiers.Shift) !== 0,
        alt: (keys.modifiers & ShortcutModifiers.Option) !== 0,
      } : null;
      const showsRecentTabs = session.core.state.workspaces.get(session.workspaceId)?.appPreferences.showsRecentTabs ?? true;
      if (!showsRecentTabs || !hold || !(hold.control || hold.shift || hold.alt)) return base[name]?.();
      dismissPalette();
      const start: SwitcherStart = { direction, hold, steps: 0, released: false, lost: false };
      switcherStart.current = start;
      switcherKeys.current?.focus();
      setSwitcher({ start, key: Date.now() });
    };
    handlers.mostRecentTab = recentTab(1);
    handlers.mostRecentTabBackward = recentTab(-1);
    return handlers;
  }, [session, browsing, dismissPalette, copyAnswer, closePeek]);

  // A Start Page's palette starts over for New Tab on the page (SpaceCard).
  const [startPageFocus, setStartPageFocus] = useState<StartPageFocus>({ tabId: null, count: 0 });
  // Find Next and Find Previous wait for a query to find again on the shown
  // page, as the Mac's commands do; until then their keys are the page's.
  const tools = usePageTools();
  const canFindAgain = page !== null && !showsStartPage && tools.canFindAgain(page.id);
  const holdsEscape = showsPeek && palette === null;
  // While the recent-tab switcher is held, the window binds no keys at all:
  // the switcher has the keyboard and answers every key itself, and a key the
  // window took would cost it the release of the keys it holds, which
  // Chromium drops after a key-down the browser handles.
  // A field recording keys, such as a shortcut being set in Settings, hears every key.
  const capturing = useSyncExternalStore((listener) => keyCapture.subscribe(listener), () => keyCapture.active);
  const switching = switcher !== null || capturing;
  // Most Recent Tab's keys reach the interface, or a page, before the shell
  // takes them: Chromium drops the key-ups that follow a key-down the browser
  // takes from a document, and the switcher needs the release. The window
  // hears them itself where the interface has the keyboard, and the shell
  // runs the command once a page lets them go.
  useEffect(() => {
    const blocked = new Set((unavailable ?? []).map((command) => command.name));
    if (!canFindAgain) for (const name of ["findNext", "findPrevious"]) blocked.add(name);
    if (switching) keys.update([], blocked, commands);
    else keys.update(bindings ?? [], blocked, commands, [...(holdsEscape ? [peekEscape] : []), settingsKeys], recentTabCommands);
  }, [keys, bindings, unavailable, commands, canFindAgain, holdsEscape, switching]);
  useEffect(() => {
    if (!session.shell) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (switcherStart.current || event.repeat) return;
      const name = commandForKey(event, offered.current.bindings ?? [], [...recentTabCommands]);
      if (!name) return;
      event.preventDefault();
      event.stopPropagation();
      commands[name]?.();
    };
    // A release reaches the switcher wherever the interface has the keyboard.
    const onKeyUp = (event: KeyboardEvent) => {
      const start = switcherStart.current;
      if (!start) return;
      if (switcherControls.current) switcherControls.current.keyUp(event);
      else if (releasesHold(event, start.hold)) start.released = true;
    };
    globalThis.addEventListener("keydown", onKeyDown, true);
    globalThis.addEventListener("keyup", onKeyUp, true);
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown, true);
      globalThis.removeEventListener("keyup", onKeyUp, true);
    };
  }, [session, commands]);
  // What a page's engine reports reaches the page's find bar, and the
  // pop-ups it blocked and the pop-up choice it enforces follow its documents.
  useEffect(() => {
    const shell = session.shell;
    if (!shell) return;
    shell.onPresentation = (bytes) => {
      const presentation = readEnginePresentation(new WireReader(bytes));
      if (presentation.$kind === "FindFinished") pageTools.finished(presentation);
      if (presentation.$kind === "PeekRequested") void openPeek(presentation);
      if (presentation.$kind === "PageCaptured") {
        pictures.received(presentation);
        pageStills.received(presentation);
      }
      extensions.presented(session, presentation);
      blockedPopups.presented(session.core, presentation, (pageId) => {
        const known = session.core.state.pages.get(pageId);
        return known && known.workspaceId === session.workspaceId
          ? { pageId, spaceId: known.spaceId, url: known.live.url }
          : null;
      });
    };
    return () => {
      shell.onPresentation = undefined;
    };
  }, [session, openPeek, pictures]);
  // A change to the Space's choices reaches every page's engine at once, as
  // the Mac's pages take a changed pop-up choice.
  const sitePermissionRevision = state.sitePermissionRevision;
  useEffect(() => {
    if (!session.shell) return;
    const pages = [...session.core.state.pages.values()]
      .filter((candidate) => candidate.workspaceId === session.workspaceId && candidate.phase.holdsEnginePage)
      .map((candidate) => ({ pageId: candidate.id, spaceId: candidate.spaceId, url: candidate.live.url }));
    blockedPopups.permissionsChanged(session.core, pages);
  }, [session, sitePermissionRevision]);
  useEffect(() => {
    const open = (event: Event) => commands[(event as CustomEvent).detail === "newTab" ? "openPalette" : "editLocation"]?.();
    globalThis.addEventListener(openPaletteEvent, open);
    return () => globalThis.removeEventListener(openPaletteEvent, open);
  }, [commands]);
  // A palette speaks for the Space and tab the window showed when it opened.
  // Another Space or tab puts it away.
  useEffect(() => {
    if (current.current && (current.current.host.spaceId !== space?.id || current.current.host.tabId !== shownTabId)) {
      dismissPalette();
    }
  }, [space?.id, shownTabId, dismissPalette]);

  // The page card's corner follows the window's, which a maximized or full-screen window has none of.
  const cornerless = useWindowIsCornerless(session.shell);
  if (!space) return <div className="window-loading" />;
  const branding = space.settings.look;
  const isPrivate = workspace?.kind.isPrivate ?? false;
  // Inside Crest's own window the title bar is the interface's; in a
  // development browser the browser's window has one.
  const shell = session.shell;
  const cards = spaceCards(window, space.id, shownTabId);
  const livePageIds = new Set(cards.tabIds.flatMap((tabId) => {
    const shownPage = pagesByTab.get(tabId);
    return shownPage ? [shownPage] : [];
  }));
  shownPages.current = livePageIds;
  const host: CardHost = {
    session, opening: opening.current, loading: loading.current, entering: enteringSpace, adopting, entries,
    commands, offered, copyAnswer, bindings: bindings ?? [], obscured: palette !== null, isPrivate,
    startPageFocus, livePageIds, spaces,
  };
  // A press or the keyboard in a card makes it the one the chrome speaks
  // for, and so does the pointer arriving on it where the person asks focus
  // to follow it, unless a field of the window's holds the keys or a drag
  // holds the pointer.
  const focusCard = (tabId: string, byPointer: boolean) => {
    if (tabId === shownTabId) return;
    if (byPointer) {
      const active = document.activeElement;
      const editing = (active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement) && !active.closest(".page-column");
      if (!workspace?.appPreferences.splitFocusFollowsMouse || palette || editing) return;
    }
    void session.core.send(ShowTab({ windowId: session.windowId, spaceId: space.id, tabId }))
      .then(() => byPointer && requestAnimationFrame(focusShownPage));
  };
  return (
    <div className={`browser-window ${shell ? "with-title-bar" : ""} ${readsLight(branding) ? "reads-light" : "reads-dark"} sidebar-${sidebar}${cornerless ? " cornerless" : ""}`}
      style={{ "--sidebar-width": `${sidebarWidth}px` } as CSSProperties}>
      <SpaceBanner spaces={spaces} spaceId={space.id} />
      <SidebarSlot presentation={sidebar} onPresentation={setSidebar} morph={sidebarMorph} width={sidebarWidth} onResize={setSidebarWidth}
        onResizeEnded={commitSidebarWidth} spaceId={space.id} spaces={spaces}>
        <Sidebar
          session={session}
          browsing={browsing}
          space={space}
          spaces={spaces}
          shownTabId={shownTabId}
          shownTabs={shownTabs}
          page={page}
          pagesByTab={pagesByTab}
          showsNavigation={!shell}
          permission={permissionPrompt(state, page?.id ?? null)}
          downloads={shell ? downloads : null}
          onDialog={setDialog}
          docked={sidebar === "docked"}
          onToggleDock={() => sidebarMorph.current?.toggle()}
        />
      </SidebarSlot>
      <SpaceContentStrip spaces={spaces} liveId={space.id} shownPins={shownPins(spaces, space.id, shownTabs, pages)} embedsPages={!!shell}
        onRest={focusShownPage} render={(candidate, live) => {
          // Another Space's cards are its preview in passing, still, as the Mac's.
          const rowCards = live ? cards : spaceCards(window, candidate.id, shownTabs.get(candidate.id) ?? null);
          const overlay = live && (
            <div className="page-row-overlay">
              {shell && (
                <DownloadApproval shell={shell} downloads={downloads} asked={downloadApproval(state)}
                  spaceName={(spaceId) => (spaceId ? workspace?.spaces.get(spaceId)?.settings.name ?? null : null)} />
              )}
              <AnimatePresence>
                {dialog && <SidebarDialogLayer key="sidebar-dialog" session={session} dialog={dialog} onDone={() => setDialog(null)} />}
              </AnimatePresence>
              <Notices shell={shell} />
            </div>
          );
          // A locked Space's card holds its lock screen, and none of its pages, until it's unlocked.
          if (isLocked(session.core, candidate)) {
            return <SpaceAccessView session={session} space={candidate} spaces={spaces} passive={!live}>{overlay}</SpaceAccessView>;
          }
          return (
            <PageColumns
              windowId={session.windowId}
              cards={rowCards}
              focusedTabId={live ? shownTabId : shownTabs.get(candidate.id) ?? null}
              accent={primaryColor(candidate.settings.look)}
              interactive={live}
              onFocus={focusCard}
              onResize={(shares) => (rowCards.groupId
                ? session.core.send(ResizeSplitColumns({ windowId: session.windowId, groupId: rowCards.groupId, shares }))
                : Promise.resolve())}
              renderCard={(tabId, card) => (
                <SpaceCard host={host} space={candidate} tabId={tabId} pages={pages} passive={!live} card={card} />
              )}
            >
              {overlay}
            </PageColumns>
          );
        }}>
        <AnimatePresence custom={peekAnimates.current} onExitComplete={letPeeksGo}>
          {peek && (
            <PeekLayer key={peek.pageId} session={session} peek={peek} spaces={spaces} hidden={!showsPeek}
              onClose={() => closePeek(true)} onOpenIn={openPeekIn} />
          )}
        </AnimatePresence>
      </SpaceContentStrip>
      <AnimatePresence>
        {palette && <CommandPalette key="palette" model={palette} bindings={bindings ?? []} tabs={space.tabs} />}
      </AnimatePresence>
      <DownloadFlights downloads={state.downloads} profileId={space.profileId} shows={palette === null && !!shell} />
      <TabPreviewLayer session={session} tabs={new Map(space.tabs.map((candidate) => [candidate.id, candidate]))}
        pagesByTab={pagesByTab} pictures={pictures}
        enabled={sidebar !== "collapsed" && palette === null && switcher === null && showsTabPreviews()} />
      {switcher && (
        <RecentTabSwitcher key={switcher.key} session={session} spaces={spaces} pagesByTab={pagesByTab} pictures={pictures}
          start={switcher.start} register={registerSwitcher} onEnd={endSwitcher} />
      )}
      {/* Where the keyboard goes while the recent-tab switcher is held, from the first press on. */}
      <div ref={switcherKeys} className="recent-tabs-keys" tabIndex={-1} aria-hidden
        onKeyDown={(event) => {
          const start = switcherStart.current;
          if (!start) return;
          event.preventDefault();
          event.stopPropagation();
          if (switcherControls.current) switcherControls.current.keyDown(event.nativeEvent);
          else if (event.key === "Tab") start.steps += event.shiftKey ? -1 : 1;
        }}
        onBlur={() => {
          const start = switcherStart.current;
          if (!start) return;
          if (switcherControls.current) switcherControls.current.lostKeys();
          else start.lost = true;
        }} />
      <ExtensionReviewLayer session={session} spaces={spaces} />
      {/* The title bar comes last: Chromium lays each box's drag area over
          those before it and doesn't clip them to scrolling, so a page or
          list scrolled up beneath the title bar would otherwise take back
          the stretch that moves the window. */}
      {shell && (
        <TitleBar shell={shell}>
          <NavigationButtons browsing={browsing} page={page} />
        </TitleBar>
      )}
    </div>
  );
}

/** Ctrl+, opens Settings, as Windows' apps open theirs; a page that uses the keys keeps them. */
const settingsKeys: ShellShortcut = {
  command: "openSettings", key: 0xbc, control: true, shift: false, alt: false,
  beforePage: false, secondPress: false, yieldsToText: false,
};

/** The commands whose keys the recent-tab switcher holds. */
const recentTabCommands: ReadonlySet<string> = new Set(["mostRecentTab", "mostRecentTabBackward"]);

/** Esc, which the window holds while a Peek shows, before the Peek's page or any other has it. */
const peekEscape: ShellShortcut = {
  command: "closePeek", key: 0x1b, control: false, shift: false, alt: false,
  beforePage: true, secondPress: false, yieldsToText: false,
};

/** A request for a Start Page's palette to start over, for the tab it names. */
interface StartPageFocus {
  readonly tabId: string | null;
  readonly count: number;
}

/** What the window lends each card it shows. */
interface CardHost {
  readonly session: Session;
  /** The tabs whose pages are being opened, and the pages whose first load has been asked for. */
  readonly opening: Set<string>;
  readonly loading: Set<string>;
  /** The Space the window is entering, which opens no remembered page until it shows a Start Page. */
  readonly entering: RefObject<string | null>;
  /** Whether a tab is taking a Peek's page, which no card opens another page for meanwhile. */
  readonly adopting: RefObject<boolean>;
  readonly entries: number;
  readonly commands: Readonly<Record<string, () => void>>;
  readonly offered: RefObject<{ bindings?: readonly ShortcutBinding[]; unavailable?: readonly ShortcutCommand[] }>;
  readonly copyAnswer: (text: string) => void;
  readonly bindings: readonly ShortcutBinding[];
  /** Whether the overlay palette covers the cards. */
  readonly obscured: boolean;
  readonly isPrivate: boolean;
  readonly startPageFocus: StartPageFocus;
  /** The pages the window's own cards show, which another Space's preview leaves to them. */
  readonly livePageIds: ReadonlySet<string>;
  /** The workspace's Spaces, which Settings lists. */
  readonly spaces: readonly SpaceState[];
}

/**
 * One card of the cards a window shows, as the Mac's BrowserSplitCardView:
 * what the core presents for its own tab, focused or not, with the page's
 * find bar and the questions it asks. A card opens its tab's page when the
 * core says the tab restores one, and gives a page its first load. A card
 * of another Space, which the pager shows in passing, is its still preview:
 * the page its tab holds, or the Start Page the window shows on entering
 * it, and a page the window's own cards show, as a group's shared pin can
 * be, stays with them. Live and passing cards are the same element, so a
 * card the window leaves keeps its page attached as it slides away.
 */
function SpaceCard({ host, space, tabId, pages, passive, card }: {
  host: CardHost;
  space: SpaceState;
  tabId: string;
  pages: readonly PageState[];
  passive: boolean;
  card: ColumnCard;
}) {
  const { session, opening, loading, entering, adopting, entries, commands, offered, copyAnswer } = host;
  const tab = space.tabs.find((candidate) => candidate.id === tabId);
  const page = pages.find((candidate) => candidate.tabId === tabId) ?? null;
  const presentation = usePagePresentation(session.core, {
    surface: tab?.surface ?? null,
    hasPage: page !== null,
    hasNavigationFailure: !!page?.live.failure,
    hasProcessFailure: false,
    restoresUnloaded: true,
  });
  const showsStartPage = passive
    ? !tab || tab.surface === TabSurface.startPage || (tab.surface === TabSurface.webPage && !page)
    : presentation === PagePresentation.startPage;
  const restoresPage = !passive && presentation === PagePresentation.automaticRestore;

  // A tab whose surface is a page and that has none restores itself, as the
  // Mac's window restores the tabs it shows.
  const spaceId = space.id;
  useEffect(() => {
    if (!restoresPage || page || opening.has(tabId) || session.closing.current || entering.current === spaceId
      || adopting.current) return;
    opening.add(tabId);
    void session.core.send(OpenPage({
      pageId: crypto.randomUUID(), workspaceId: session.workspaceId, spaceId, tabId, windowId: session.windowId,
      transient: null, openerPageId: null,
    })).finally(() => opening.delete(tabId));
  }, [session, opening, entering, adopting, spaceId, tabId, page, restoresPage, entries]);

  // A page's first load goes through the core's Navigate, which resolves the
  // tab's address by the Space's rules and asks the engine to load it.
  const firstAddress = tab?.url ?? tab?.savedUrl ?? null;
  useEffect(() => {
    if (passive || !page || page.phase.name !== "live" || page.live.url || page.live.pendingUrl || !firstAddress) return;
    if (loading.has(page.id)) return;
    loading.add(page.id);
    void session.core.send(Navigate({ pageId: page.id, input: firstAddress }));
  }, [session, loading, passive, page, firstAddress]);

  // The Start Page's palette, which speaks for the tab it shows and starts
  // over for another tab, another Space, or New Tab on the page. A card the
  // pager shows still keeps its palette, results and all, as the Mac's does,
  // so a slide carries it whole rather than it appearing once the slide ends;
  // the strip keeps such a card inert, and only the live one takes the keys.
  const focusRequest = useRef(0);
  if (host.startPageFocus.tabId === tabId) focusRequest.current = host.startPageFocus.count;
  const palette = useMemo(() => {
    if (!showsStartPage) return null;
    return new PaletteModel({
      core: session.core,
      // Crest's Chromium fetches the search engine's suggestions, as the Mac app does.
      fetchSuggestions: suggestionFetcher(session.shell),
      windowId: session.windowId,
      workspaceId: session.workspaceId,
      spaceId,
      tabId,
      pageId: null,
      get commands() {
        return paletteCommands(offered.current.bindings ?? [], offered.current.unavailable ?? [], commands);
      },
      runCommand: (name) => commands[name]?.(),
      copy: copyAnswer,
      // The page's palette stays where it is.
      dismiss: () => {},
    }, { kind: "startPage" });
    // A palette starts over only for another tab, Space or focus request.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [showsStartPage, spaceId, tabId, focusRequest.current, commands]);
  useEffect(() => () => palette?.close(), [palette]);
  // A Start Page card that becomes the focused one takes the keyboard from the page that had it.
  useEffect(() => {
    if (!passive && card.focused && showsStartPage && document.activeElement instanceof HTMLEmbedElement) {
      requestAnimationFrame(focusShownPage);
    }
  }, [passive, card.focused, showsStartPage]);

  // A card is inert while the pager moves it, so its palette takes the keys once it settles.
  const moving = useSpacePager().phase !== "idle";
  const pageId = showsStartPage ? null
    : passive ? (tab?.surface === TabSurface.webPage && page && !host.livePageIds.has(page.id) ? page.id : null)
      : page?.id ?? null;
  // A tab can show one of Crest's own views in place of a page: Settings, or the Getting Started guide.
  // Another Space's card in passing shows the guide's canvas alone, since its practice is the live card's.
  const native = tab?.surface === TabSurface.nativeView ? tab.nativeView : null;
  const nativeContent = !tab || native === null ? null
    : native === NativeView.settings ? <SettingsView session={session} tabId={tab.id} spaces={host.spaces} shownSpace={space} />
      : native === NativeView.gettingStarted
        ? (passive ? <div className="getting-started" aria-hidden /> : <GettingStartedView session={session} tabId={tab.id} />)
        : <UnknownNativeView />;
  return (
    <PageCard session={session} pageId={nativeContent ? null : pageId} passive={passive} focused={card.focused} transition={card.transition}
      startPage={nativeContent ?? (showsStartPage ? (
        <StartPage palette={palette} isPrivate={host.isPrivate} bindings={palette ? host.bindings : []}
          tabs={palette ? space.tabs : []} obscured={host.obscured} takesFocus={card.focused && !passive && !moving} />
      ) : null)}>
      {!passive && page && !showsStartPage && <FindBar core={session.core} pageId={page.id} />}
      {!passive && <PromptSheet session={session} prompt={sheetPrompt(session.core.state, page?.id ?? null)} spaceName={space.settings.name} />}
    </PageCard>
  );
}

/** BrowserNativeTabHost's answer for a view this build doesn't draw. */
function UnknownNativeView() {
  return (
    <div className="native-unknown">
      <h2>This tab needs a newer Crest</h2>
      <p>Its content is still saved. Update Crest to open it.</p>
    </div>
  );
}

/**
 * The pinned tab each Space shows in this window, for the Spaces that show
 * one rather than another tab or a Start Page on entry, as the Mac's page
 * area counts them: neighbours in a group that show the same one share a place.
 */
function shownPins(spaces: readonly SpaceState[], shownSpaceId: string, shownTabs: ReadonlyMap<string, string>,
  pages: readonly PageState[]): Map<string, string> {
  const pins = new Map<string, string>();
  for (const space of spaces) {
    const tabId = shownTabs.get(space.id);
    const tab = tabId ? space.tabs.find((candidate) => candidate.id === tabId) : undefined;
    if (!tabId || tab?.placement !== TabPlacement.pinned) continue;
    const opensStartPage = tab.surface === TabSurface.webPage && !pages.some((page) => page.tabId === tabId);
    if (space.id === shownSpaceId || !opensStartPage) pins.set(space.id, tabId);
  }
  return pins;
}

/**
 * The commands the palette may offer, as the Mac's registry offers them: each
 * the core offers on this device that the palette lists, that this window
 * runs and can run now, under its title and section.
 */
function paletteCommands(bindings: readonly ShortcutBinding[], unavailable: readonly ShortcutCommand[],
  handlers: Readonly<Record<string, () => void>>): PaletteCommand[] {
  const blocked = new Set(unavailable.map((command) => command.name));
  return bindings.map((binding) => binding.command)
    .filter((command) => command.offersInPalette && handlers[command.name] && !blocked.has(command.name))
    .map((command) => ({ command, title: command.title, sectionTitle: command.section.title }));
}
