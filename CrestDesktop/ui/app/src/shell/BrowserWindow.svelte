<script lang="ts" module>
  import { type PageState, type SpaceState, TabPlacement, TabSurface } from "@crest/contracts";
  import type { ShellShortcut } from "@crest/core-client";

  import { reader } from "../reactive";
  import { keyCapture } from "../shortcuts";
  import type { SpaceCards } from "./shown-cards";

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

  /** The cards of a window that shows no Space yet. */
  const noCards: SpaceCards = { tabIds: [], groupId: null, shares: [] };

  /** Whether a field records keys, such as a shortcut being set in Settings, which then hears every key. */
  const readKeyCapture = reader((listener) => keyCapture.subscribe(listener), () => keyCapture.active);

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
</script>

<script lang="ts">
  import {
    DiscardStagedLink,
    MovePage,
    NativeView,
    LoadAddress,
    OpenTab,
    OpenPage,
    PagePresentation,
    type PeekRequested,
    PromoteTransientPage,
    readEnginePresentation,
    ReleasePage,
    ResizeSplitColumns,
    ShortcutModifiers,
    ShowSpace,
    ShowStartPage,
    ShowTab,
    StageLink,
    TransientPresentation,
    WireReader,
  } from "@crest/contracts";
  import { CoreRejection } from "@crest/core-client";
  import { tick, untrack } from "svelte";

  import type { Session } from "../boot";
  import { css, primaryColor, readsLight } from "../branding";
  import { Browsing } from "../browsing";
  import { openPalette, openPaletteEvent, spaceEditing, windowCommands } from "../commands";
  import { useDownloads } from "../downloads.svelte";
  import { opensExternal } from "../external-opening";
  import { copiedNotice, notices } from "../notices";
  import { CommandPalette } from "../palette/CommandPalette";
  import { PaletteModel, type PaletteMode } from "../palette/palette-model";
  import { commandForKey, keyCode, WindowShortcuts } from "../shortcuts";
  import { setSpaceStepper, spacePager } from "../spaces/space-pager";
  import { useChromeLook } from "../spaces/look-blend.svelte";
  import { SpaceContentStrip } from "../spaces/SpaceContentStrip";
  import RecentTabSwitcher, { releasesHold, type SwitcherControls, type SwitcherHold, type SwitcherStart } from "../switcher/RecentTabSwitcher.svelte";
  import { pageStills } from "../spaces/page-stills";
  import { showAdjacentSpace } from "../spaces/show-space";
  import { TabPictures } from "../switcher/tab-pictures";
  import type { SettingsPageName } from "../settings/catalog";
  import { extensions } from "../extensions";
  import { suggestionFetcher } from "../palette/suggestions";
  import { resumeSpaceDeletions } from "../spaces/space-deletion";
  import { isLocked, lockWhenCrestInactive } from "../spaces/space-access";
  import SpaceAccessView from "../spaces/SpaceAccessView.svelte";
  import { requestSettings } from "../settings/SettingsView.svelte";
  import { coreState, useCoreVersion } from "../use-core";
  import ChromeButton from "./ChromeButton.svelte";
  import PageAddress from "./Sidebar/PageAddress.svelte";
  import NavigationButtons from "./NavigationButtons.svelte";
  import Notices from "./Notices.svelte";
  import { blockedPopups } from "./blocked-popups";
  import { focusShownPage } from "./PageCard.svelte";
  import PageColumns, { type ColumnCard } from "./PageColumns.svelte";
  import { usePagePresentation } from "./page-presentation.svelte";
  import { pageTools, usePageTools } from "./page-tools";
  import { sampleAddress, setSamplePeek } from "./peek-sample";
  import PeekLayer, { type Peek, type PeekExit } from "./PeekLayer.svelte";
  import DownloadFlights from "./DownloadFlights.svelte";
  import DownloadApproval from "./prompts/DownloadApproval.svelte";
  import ExtensionReviewLayer from "./prompts/ExtensionReview.svelte";
  import { downloadApproval, permissionPrompt } from "./prompts/prompt-text";
  import { Sidebar } from "./Sidebar";
  import {
    addressPlacement, customChromeAccent, dimUnloaded, paperOpacity, paperSelection, pinGap, sidebarMotionFactor, sidebarOnRight,
    sidebarSpacing, tabContentScale, tabScale, tintSelectedPins, windowBorder,
  } from "../appearance.svelte";
  import { captureSidebar, initialSidebarIsPresented, initialSidebarWidth } from "./sidebar-layout";
  import { type SelectionKey, selectionTakes } from "./sidebar-selection";
  import SidebarDialogLayer, { type SidebarDialog } from "./SidebarDialogs.svelte";
  import SidebarSlot, { type SidebarMorph, type SidebarPresentation } from "./SidebarSlot.svelte";
  import SpaceCard, { type CardHost, paletteCommands, type StartPageFocus } from "./SpaceCard.svelte";
  import { spaceCards } from "./shown-cards";
  import { SpaceBanner } from "./SpaceBanner";
  import TitleBar from "./TitleBar.svelte";
  import { useWindowIsCornerless } from "./WindowControls.svelte";

  /**
   * One Crest window: the Space's banner behind everything, the sidebar over it
   * and the page card beside it. What the window shows is the core's window
   * state; the window opens a page for the tab it shows when none is open.
   */
  let { session }: { session: Session } = $props();

  const browsing = $derived(new Browsing(session));
  const downloads = useDownloads(untrack(() => session));
  const window = $derived(coreState(session).windows.get(session.windowId));
  const workspace = $derived(coreState(session).workspaces.get(session.workspaceId));
  const spaces = $derived((workspace?.order ?? []).map((id) => workspace!.spaces.get(id))
    .filter((space): space is SpaceState => !!space));
  const space = $derived(window ? workspace?.spaces.get(window.shownSpaceId) : undefined);
  const shownSpaceId = $derived(space?.id ?? null);
  const shownTabId = $derived(window?.shownTabs.find((shown) => shown.spaceId === window.shownSpaceId)?.tabId ?? null);
  const shownTabs = $derived(new Map((window?.shownTabs ?? []).flatMap((shown) => (shown.tabId ? [[shown.spaceId, shown.tabId] as const] : []))));
  // Links and documents other apps hand Crest open where the core places
  // them, once the window shows the browser rather than first-run Setup.
  $effect(() => untrack(() => opensExternal(session)));

  // The Space pager follows the Space the window shows, and asks for the one a swipe settles on.
  const spaceIds = $derived(spaces.map((candidate) => candidate.id).join());
  $effect(() => {
    const ids = spaceIds;
    const shownId = shownSpaceId;
    if (shownId === null) return;
    untrack(() => spacePager.update(ids.split(","), shownId, (spaceId) => {
      pageStills.leaving(session.core);
      void session.core.send(ShowSpace({ windowId: session.windowId, spaceId })).catch(() => spacePager.abandon(spaceId));
    }));
  });
  $effect(() => untrack(() => setSpaceStepper((direction) => void showAdjacentSpace(session.core, session.windowId, direction)
    .catch(() => undefined))));
  // A Space whose deletion the last launch began goes now, as the Mac's window carries it on.
  $effect(() => untrack(() => void resumeSpaceDeletions(session)));
  // Spaces that ask for authentication lock once Crest is no longer in front, as the Mac's do.
  $effect(() => untrack(() => lockWhenCrestInactive(session)));
  const pages = $derived([...coreState(session).pages.values()].filter((candidate) => candidate.phase.holdsEnginePage));
  const pagesByTab = $derived(new Map(pages.flatMap((candidate) => (candidate.tabId ? [[candidate.tabId, candidate.id] as const] : []))));
  const page = $derived(pages.find((candidate) => candidate.tabId === shownTabId) ?? null);
  const opening = new Set<string>();
  const tab = $derived(space?.tabs.find((candidate) => candidate.id === shownTabId));

  // What the page card shows is the core's answer for the shown tab. A tab
  // whose surface is a page and that has none restores itself, as the Mac's
  // window restores the tab it shows.
  const presentation = usePagePresentation(untrack(() => session.core), () => ({
    surface: tab?.surface ?? null,
    hasPage: page !== null,
    hasNavigationFailure: !!page?.live.failure,
    hasProcessFailure: false,
    restoresUnloaded: true,
  }));
  const showsStartPage = $derived(presentation.current === PagePresentation.startPage);

  // Entering a Space shows the pages it holds, but does not open its
  // remembered unloaded tab on the person's behalf: the window shows a Start
  // Page there instead, as the Mac's does. The tab the session remembers
  // stays as it was.
  let enteredSpace: string | null = null;
  const enteringSpace: { current: string | null } = { current: null };
  let entries = $state(0);
  // Only entering another Space asks this.
  $effect(() => {
    const entered = shownSpaceId;
    untrack(() => {
      const previous = enteredSpace;
      enteredSpace = entered;
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
        entries += 1;
      });
    });
  });

  // Each card the window shows opens its own tab's page (SpaceCard); a page's
  // first load goes through the core's Navigate.
  const loading = new Set<string>();

  // The Peek a link opened over the page that followed it, which shows while
  // that page's tab is the one the window shows. A Peek that goes back into
  // its link lets its page go once it has, and one kept as a tab, or closed
  // by its page, leaves at once.
  let peek = $state.raw<Peek | null>(null);
  let peekAnimates = $state(true);
  const releasing = new Set<string>();
  const closePeek = (animated: boolean, releases = true) => {
    const current = peek;
    if (!current) return;
    peekAnimates = animated;
    if (releases) {
      if (animated) releasing.add(current.pageId);
      else void session.core.send(ReleasePage({ pageId: current.pageId, keepsState: false })).catch(() => {});
    }
    peek = null;
    // The keyboard goes back to the page beneath.
    requestAnimationFrame(focusShownPage);
  };
  const releaseAfterExit = (pageId: string) => {
    if (releasing.delete(pageId)) void session.core.send(ReleasePage({ pageId, keepsState: false })).catch(() => {});
  };
  /** How a Peek that goes leaves, which the window says as it closes it. */
  const peekExit: PeekExit = {
    get animates() {
      return peekAnimates;
    },
    onComplete: releaseAfterExit,
  };
  let openingPeek = 0;
  const sourceAvailable = (spaceId: string, tabId: string) => spaces.some(candidate =>
    candidate.id === spaceId && !isLocked(session.core, candidate) && candidate.tabs.some(tab => tab.id === tabId));
  const presentPeek = async (spaceId: string, sourceTabId: string, sourcePageId: string | null, url: string, stagedLinkId: string | null) => {
    const attempt = ++openingPeek;
    const discard = () => sourcePageId && stagedLinkId
      && void session.core.send(DiscardStagedLink({ sourcePageId, stagedLinkId })).catch(() => {});
    // A link followed while a Peek is open takes its place.
    closePeek(false);
    const pageId = crypto.randomUUID();
    try {
      await session.core.send(OpenPage({
        pageId, workspaceId: session.workspaceId, spaceId, tabId: null, windowId: session.windowId,
        transient: TransientPresentation.peek, openerPageId: sourcePageId,
      }));
    } catch {
      discard();
      return;
    }
    // The page's first load runs the link the source page staged, keeping its referrer and security.
    if (sourcePageId && stagedLinkId) {
      try {
        await session.core.send(StageLink({ pageId, sourcePageId, stagedLinkId, url }));
      } catch {
        discard();
        void session.core.send(ReleasePage({ pageId, keepsState: false })).catch(() => {});
        return;
      }
    }
    if (attempt !== openingPeek || !sourceAvailable(spaceId, sourceTabId)) {
      void session.core.send(ReleasePage({ pageId, keepsState: false })).catch(() => {});
      return;
    }
    peekAnimates = true;
    peek = { pageId, sourcePageId, sourceTabId, spaceId, url };
    void session.core.send(LoadAddress({ pageId, url })).catch(() => {});
  };
  const openPeek = (request: PeekRequested) => {
    const source = session.core.state.pages.get(request.pageId);
    if (source?.tabId && livePageIds.has(source.id)) {
      void presentPeek(source.spaceId, source.tabId, source.id, request.url, request.stagedLinkId);
    }
  };
  setSamplePeek(() => {
    if (space && tab?.nativeView === NativeView.settings && !isLocked(session.core, space)) {
      void presentPeek(space.id, tab.id, null, sampleAddress, null);
    }
  });
  // Open In keeps the Peek's page as a tab of a Space, which the window then
  // shows: the tab takes the live page where it can, or loads it afresh.
  // The new tab opens no page of its own until it has taken the Peek's.
  const adopting = { current: false };
  const openPeekIn = async (spaceId: string) => {
    const current = peek;
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
      entries += 1;
    }
  };
  // A Peek whose page closed itself, or whose link's tab left, goes at once.
  const peekOutcome = $derived(peek ? coreState(session).transientOutcomes.get(peek.pageId) : undefined);
  const peekPageGone = $derived(peek ? !coreState(session).pages.has(peek.pageId) : false);
  const peekSourceGone = $derived((useCoreVersion(session), peek ? !sourceAvailable(peek.spaceId, peek.sourceTabId) : false));
  $effect(() => {
    const outcome = peekOutcome;
    const pageGone = peekPageGone;
    const sourceGone = peekSourceGone;
    untrack(() => {
      if (outcome?.$kind === "TransientPageClosed" || pageGone) closePeek(false, false);
      else if (sourceGone) closePeek(false);
    });
  });
  const showsPeek = $derived(peek !== null && peek.sourceTabId === shownTabId);

  // The window's commands act on what it shows now, from the keys the core
  // binds them to on this device, for the commands the window can run now.
  const cards = $derived(space ? spaceCards(window, space.id, shownTabId) : noCards);
  const shownCards = $derived(cards.tabIds);
  const shown = () => ({ space, tab, page, cards: shownCards });

  // Pictures of the pages the window shows, for the recent-tab switcher:
  // taken once a page has shown for a second and a half, and again after it
  // finishes loading or goes somewhere else.
  const pictures = new TabPictures();
  $effect(() => () => {
    pictures.clear();
    pageStills.clear();
  });
  const pictured = $derived(shownCards.flatMap((tabId) => {
    const shownPage = pages.find((candidate) => candidate.tabId === tabId);
    return shownPage?.phase.name === "live" && shownPage.live.url && !shownPage.live.isLoading
      ? [{ pageId: shownPage.id, tabId, address: shownPage.live.url }] : [];
  }));
  const picturedKey = $derived(pictured.map((entry) => `${entry.pageId} ${entry.address}`).join());
  $effect(() => {
    if (!session.shell || !picturedKey) return;
    const timer = setTimeout(() => {
      for (const entry of pictured) pictures.capture(session.core, entry);
    }, 1500);
    return () => clearTimeout(timer);
  });

  // The recent-tab switcher, while the keys of Most Recent Tab are held. The
  // window gives it the keyboard on the first press, before it draws.
  let switcher = $state.raw<{ readonly start: SwitcherStart; readonly key: number } | null>(null);
  let switcherStart: SwitcherStart | null = null;
  let switcherControls: SwitcherControls | null = null;
  let switcherKeys = $state<HTMLDivElement>();
  const registerSwitcher = (controls: SwitcherControls | null) => {
    switcherControls = controls;
  };
  const endSwitcher = () => {
    switcherStart = null;
    switcherControls = null;
    switcher = null;
    requestAnimationFrame(focusShownPage);
  };
  const keys = $derived(new WindowShortcuts(session.shell));
  $effect(() => {
    const shortcuts = keys;
    return untrack(() => shortcuts.install());
  });
  const bindings = $derived(coreState(session).shortcuts?.bindings);
  const unavailable = $derived(window?.unavailableCommands);
  const offered = {
    get current() {
      return { bindings, unavailable };
    },
  };

  // The command palette, as the Mac's: New Tab opens it with nothing typed,
  // Open Location with the shown tab's address, and the same keys put it
  // away again. Any other command puts it away before it runs.
  let palette = $state.raw<PaletteModel | null>(null);
  // A question the sidebar asks over the page, such as confirming a folder's deletion.
  let dialog = $state.raw<SidebarDialog | null>(null);
  // Where the sidebar is: Ctrl+S hides it or docks it again, and its own
  // button floats it over the page or docks it, as on the Mac. The window
  // keeps whether it is shown, and its width, on this device.
  const sidebarMorph: { current: SidebarMorph | null } = { current: null };
  let edgeHost = $state<HTMLDivElement | null>(null);
  let windowRoot = $state<HTMLDivElement | null>(null);
  // The window's chrome takes the look the Space pager stands at, as it moves;
  // and, as the window draws again with each batch, any part of it drawn anew.
  useChromeLook(() => windowRoot, () => (useCoreVersion(session), spaces));
  const opened = untrack(() => ({ presented: initialSidebarIsPresented(session.windowId), width: initialSidebarWidth(session.windowId) }));
  let sidebar = $state<SidebarPresentation>(opened.presented ? "docked" : "collapsed");
  let sidebarWidth = $state(opened.width);
  let committedWidth = opened.width;
  const commitSidebarWidth = (width: number) => {
    if (width === committedWidth) return;
    committedWidth = width;
    captureSidebar(session.windowId, { width });
  };
  let presentedBefore = opened.presented;
  $effect(() => {
    const presented = sidebar === "docked";
    untrack(() => {
      if (presented === presentedBefore) return;
      presentedBefore = presented;
      captureSidebar(session.windowId, { isPresented: presented });
    });
  });
  const dismissPalette = () => {
    if (!palette) return;
    palette.close();
    palette = null;
    // The page takes the keyboard back once the palette's field is gone.
    requestAnimationFrame(focusShownPage);
  };
  /** Copies an answer a palette gives, such as the calculator's. */
  const copyAnswer = (text: string) => {
    if (!session.shell) return;
    void session.shell.copy(text);
    notices.post(copiedNotice);
  };
  const windowHandlers = (browsing: Browsing) => {
    const base = windowCommands(session, browsing, shown);
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
      const { space: shownSpace, tab: shownTab, page: shownPage } = shown();
      if (!shownSpace) return;
      palette?.close();
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
      palette = model;
    };
    const toggle = (kind: "newTab" | "editLocation") => () => {
      if (palette?.mode.kind === kind) dismissPalette();
      else open(kind);
    };
    // On a Start Page, New Tab puts the overlay away and gives the page's own
    // palette the keyboard, starting over, as the Mac's does.
    const startPageTakesNewTab = () => {
      const shownTab = shown().tab;
      if (shownTab?.surface !== TabSurface.startPage) return false;
      dismissPalette();
      const tabId = shownTab.id;
      startPageFocus = { tabId, count: startPageFocus.count + 1 };
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
      const { space: shownSpace, tab: shownTab } = shown();
      const target = spaceId ? session.core.state.workspaces.get(session.workspaceId)?.spaces.get(spaceId) : shownSpace;
      if (!target) return;
      const existing = target.tabs.find((candidate) => candidate.nativeView === NativeView.settings);
      const tabId = existing?.id ?? crypto.randomUUID();
      if (page) {
        // A Space's own pages are its Space's.
        requestSettings(tabId, ["spaces", "extensions", "appearance"].includes(page)
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
    const peekShown = () => !!peek && peek.sourceTabId === shown().tab?.id;
    const closeTab = handlers.closeTabOrWindow;
    handlers.closeTabOrWindow = () => (peekShown() ? closePeek(true) : closeTab?.());
    handlers.closePeek = () => peekShown() && closePeek(true);
    // Most Recent Tab holds the switcher open while its keys are held, as
    // the Mac's does where the person shows recent tabs while switching and
    // the keys hold a modifier; otherwise it goes straight to the tab.
    const recentTab = (direction: 1 | -1) => () => {
      if (switcherControls) return switcherControls.step(direction);
      if (switcherStart) {
        switcherStart.steps += direction;
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
      switcherStart = start;
      switcherKeys?.focus();
      switcher = { start, key: Date.now() };
    };
    handlers.mostRecentTab = recentTab(1);
    handlers.mostRecentTabBackward = recentTab(-1);
    // A slide a click started asks for its Space as it lands; a command run
    // before then asks at once, and acts once the window shows that Space.
    for (const [name, handle] of Object.entries(handlers)) {
      handlers[name] = () => {
        const shows = spacePager.commitNow();
        if (shows) void shows.then(handle);
        else handle();
      };
    }
    return handlers;
  };
  const commands = $derived.by(() => {
    const current = browsing;
    return untrack(() => windowHandlers(current));
  });

  // A Start Page's palette starts over for New Tab on the page (SpaceCard).
  let startPageFocus = $state.raw<StartPageFocus>({ tabId: null, count: 0 });
  // Find Next and Find Previous wait for a query to find again on the shown
  // page, as the Mac's commands do; until then their keys are the page's.
  const canFindAgain = $derived(page !== null && !showsStartPage && usePageTools().canFindAgain(page.id));
  const holdsEscape = $derived(showsPeek && palette === null);
  // While the recent-tab switcher is held, the window binds no keys at all:
  // the switcher has the keyboard and answers every key itself, and a key the
  // window took would cost it the release of the keys it holds, which
  // Chromium drops after a key-down the browser handles.
  // A field recording keys, such as a shortcut being set in Settings, hears every key.
  const capturing = $derived(readKeyCapture());
  const switching = $derived(switcher !== null || capturing);
  // Most Recent Tab's keys reach the interface, or a page, before the shell
  // takes them: Chromium drops the key-ups that follow a key-down the browser
  // takes from a document, and the switcher needs the release. The window
  // hears them itself where the interface has the keyboard, and the shell
  // runs the command once a page lets them go.
  $effect(() => {
    const blocked = new Set((unavailable ?? []).map((command) => command.name));
    if (!canFindAgain) for (const name of ["findNext", "findPrevious"]) blocked.add(name);
    const shortcuts = keys;
    const handlers = commands;
    const bound = bindings ?? [];
    const escapes = holdsEscape;
    const held = switching;
    untrack(() => {
      if (held) shortcuts.update([], blocked, handlers);
      else shortcuts.update(bound, blocked, handlers, [...(escapes ? [peekEscape] : []), settingsKeys], recentTabCommands);
    });
  });
  $effect(() => {
    const handlers = commands;
    if (!session.shell) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (switcherStart || event.repeat) return;
      const name = commandForKey(event, offered.current.bindings ?? [], [...recentTabCommands]);
      if (!name) return;
      event.preventDefault();
      event.stopPropagation();
      handlers[name]?.();
    };
    // A release reaches the switcher wherever the interface has the keyboard.
    const onKeyUp = (event: KeyboardEvent) => {
      const start = switcherStart;
      if (!start) return;
      if (switcherControls) switcherControls.keyUp(event);
      else if (releasesHold(event, start.hold)) start.released = true;
    };
    globalThis.addEventListener("keydown", onKeyDown, true);
    globalThis.addEventListener("keyup", onKeyUp, true);
    return () => {
      globalThis.removeEventListener("keydown", onKeyDown, true);
      globalThis.removeEventListener("keyup", onKeyUp, true);
    };
  });
  // What a page's engine reports reaches the page's find bar, and the
  // pop-ups it blocked and the pop-up choice it enforces follow its documents.
  $effect(() => {
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
  });
  // A change to the Space's choices reaches every page's engine at once, as
  // the Mac's pages take a changed pop-up choice.
  const sitePermissionRevision = $derived(coreState(session).sitePermissionRevision);
  $effect(() => {
    void sitePermissionRevision;
    untrack(() => {
      if (!session.shell) return;
      const pages = [...session.core.state.pages.values()]
        .filter((candidate) => candidate.workspaceId === session.workspaceId && candidate.phase.holdsEnginePage)
        .map((candidate) => ({ pageId: candidate.id, spaceId: candidate.spaceId, url: candidate.live.url }));
      blockedPopups.permissionsChanged(session.core, pages);
    });
  });
  $effect(() => {
    const handlers = commands;
    const open = (event: Event) => handlers[(event as CustomEvent).detail === "newTab" ? "openPalette" : "editLocation"]?.();
    globalThis.addEventListener(openPaletteEvent, open);
    return () => globalThis.removeEventListener(openPaletteEvent, open);
  });
  // A palette speaks for the Space and tab the window showed when it opened.
  // Another Space or tab puts it away.
  $effect(() => {
    const spaceId = shownSpaceId;
    const tabId = shownTabId;
    untrack(() => {
      if (palette && (palette.host.spaceId !== spaceId || palette.host.tabId !== tabId)) dismissPalette();
    });
  });

  // The page card's corner follows the window's, which a maximized or full-screen window has none of.
  const cornerless = $derived(useWindowIsCornerless(session.shell));
  const pageSeam = $derived(windowBorder.current * 1.5 / windowBorder.fallback);
  const pageCorner = $derived(windowBorder.current === 0 ? 0 : Math.max(0, (cornerless ? 13 : 16 - windowBorder.current) - pageSeam));
  const shownSpaceLocked = $derived((useCoreVersion(session), !!space && isLocked(session.core, space)));
  const topAddress = $derived(addressPlacement.current === "top");

  const isPrivate = $derived(workspace?.kind.isPrivate ?? false);
  const livePageIds = $derived(new Set(cards.tabIds.flatMap((tabId) => {
    const shownPage = pagesByTab.get(tabId);
    return shownPage ? [shownPage] : [];
  })));
  const host: CardHost = {
    get session() {
      return session;
    },
    opening, loading, entering: enteringSpace, adopting,
    get entries() {
      return entries;
    },
    get commands() {
      return commands;
    },
    offered, copyAnswer,
    get bindings() {
      return bindings ?? [];
    },
    get obscured() {
      return palette !== null;
    },
    get isPrivate() {
      return isPrivate;
    },
    get startPageFocus() {
      return startPageFocus;
    },
    get livePageIds() {
      return livePageIds;
    },
    get spaces() {
      return spaces;
    },
  };
  // A press or the keyboard in a card makes it the one the chrome speaks
  // for, and so does the pointer arriving on it where the person asks focus
  // to follow it, unless a field of the window's holds the keys or a drag
  // holds the pointer.
  const focusCard = (tabId: string, byPointer: boolean) => {
    if (tabId === shownTabId || !space) return;
    if (byPointer) {
      const active = document.activeElement;
      const editing = (active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement) && !active.closest(".page-column");
      if (!workspace?.appPreferences.splitFocusFollowsMouse || palette || editing) return;
    }
    return session.core.send(ShowTab({ windowId: session.windowId, spaceId: space.id, tabId }))
      .then(() => { if (byPointer) requestAnimationFrame(focusShownPage); });
  };
  const editCardLocation = async (tabId: string) => {
    await focusCard(tabId, false);
    await tick();
    if (shownTabId === tabId) openPalette("editLocation");
  };
</script>

{#snippet pageBar(barSpace: SpaceState, barTab: string | null, barPage: PageState | null, focused: boolean, leading: boolean)}
  {#if leading && sidebar !== "docked"}
    <ChromeButton symbol={sidebarOnRight.current ? "sidebar.right" : "sidebar.left"} label="Dock Sidebar"
      className="page-bar-dock" onClick={() => sidebarMorph.current?.toggle()} />
  {/if}
  <NavigationButtons {browsing} page={barPage} />
  <div class="page-address-host address-area">
    <PageAddress {session} {browsing} space={barSpace} page={barPage} {focused}
      tabUrl={barSpace.tabs.find(candidate => candidate.id === barTab)?.url ?? ""}
      permission={focused ? permissionPrompt(coreState(session), barPage?.id ?? null) : null}
      activate={barTab ? () => void editCardLocation(barTab) : undefined} />
  </div>
{/snippet}

{#if !space}
  <div class="window-loading"></div>
{:else}
  <!-- Inside Crest's own window the title bar is the interface's; in a
       development browser the browser's window has one. -->
  {@const shell = session.shell}
  <div bind:this={windowRoot}
    class={`browser-window ${shell ? "with-title-bar" : ""} ${readsLight(space.settings.look) ? "reads-light" : "reads-dark"} sidebar-${sidebar}${cornerless ? " cornerless" : ""}`}
    class:paper-selection={paperSelection.current} class:tint-selected-pins={tintSelectedPins.current} class:dim-unloaded={dimUnloaded.current}
    class:top-address={topAddress} class:sidebar-right={sidebarOnRight.current}
    style:--window-inset="{windowBorder.current + pageSeam}px" style:--sidebar-gap="{pageSeam}px"
    style:--page-seam="{pageSeam}px" style:--page-corner="{pageCorner}px"
    style:--chrome-accent={customChromeAccent.current || css(primaryColor(space.settings.look))}
    style:--custom-chrome-accent={customChromeAccent.current || undefined}
    style:--selected-tab-fill={customChromeAccent.current ? "color-mix(in srgb, var(--chrome-accent) 18%, var(--surface-selected))" : undefined}
    style:--selected-paper-opacity={paperOpacity.current / 100}
    style:--tab-scale={tabScale()} style:--tab-content-scale={tabContentScale()} style:--pin-spacing="{pinGap()}px"
    style:--sidebar-spacing={sidebarSpacing.current} style:--sidebar-width="{sidebarWidth}px" style:--sidebar-motion-factor={sidebarMotionFactor()}>
    <SpaceBanner {spaces} spaceId={space.id} />
    <SidebarSlot presentation={sidebar} onPresentation={(next) => (sidebar = next)} morph={sidebarMorph} width={sidebarWidth}
      onResize={(width) => (sidebarWidth = width)} onResizeEnded={commitSidebarWidth} spaceId={space.id} {spaces} {shell} {edgeHost}>
      <Sidebar
        {session}
        {browsing}
        {space}
        {spaces}
        {shownTabId}
        {shownTabs}
        {page}
        {pagesByTab}
        previews={{ pictures, enabled: sidebar !== "collapsed" && !palette && !switcher && !dialog }}
        addressInSidebar={!topAddress} showsNavigation={!shell && !topAddress}
        permission={permissionPrompt(coreState(session), page?.id ?? null)}
        downloads={shell ? downloads : null}
        onDialog={(next) => (dialog = next)}
        docked={sidebar === "docked"}
        onToggleDock={() => sidebarMorph.current?.toggle()}
      />
    </SidebarSlot>
    <SpaceContentStrip {spaces} liveId={space.id} shownPins={shownPins(spaces, space.id, shownTabs, pages)} embedsPages={!!shell}
      onRest={focusShownPage}>
      {#snippet toolbar()}
        {#if topAddress && cards.tabIds.length < 2 && !showsPeek}
          <div class="page-address-toolbar" role="group" aria-label="Address bar" inert={shownSpaceLocked}>
            {@render pageBar(space, shownTabId, page, true, true)}
          </div>
        {/if}
      {/snippet}
      {#snippet render(candidate: SpaceState, live: boolean)}
        <!-- Another Space's cards are its preview in passing, still, as the Mac's. -->
        {@const rowCards = live ? cards : spaceCards(window, candidate.id, shownTabs.get(candidate.id) ?? null)}
        {#snippet overlay()}
          {#if live}
            <div class="page-row-overlay">
              {#if shell}
                <DownloadApproval {shell} {downloads} asked={downloadApproval(coreState(session))}
                  spaceName={(spaceId) => (spaceId ? workspace?.spaces.get(spaceId)?.settings.name ?? null : null)} />
              {/if}
              {#if dialog}
                <SidebarDialogLayer {session} {dialog} onDone={() => (dialog = null)} />
              {/if}
              <Notices {shell} />
            </div>
          {/if}
        {/snippet}
        <!-- A locked Space's card holds its lock screen, and none of its pages, until it's unlocked. -->
        {#if (useCoreVersion(session), isLocked(session.core, candidate))}
          <SpaceAccessView {session} space={candidate} {spaces} passive={!live}>{@render overlay()}</SpaceAccessView>
        {:else}
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
          >
            {#snippet renderCard(tabId: string, card: ColumnCard)}
              {#if topAddress && rowCards.tabIds.length > 1}
                {@const cardPage = pages.find(candidate => candidate.tabId === tabId) ?? null}
                <div class="page-address-toolbar split-address-toolbar" role="group"
                  aria-label={`Page bar for ${candidate.tabs.find(tab => tab.id === tabId)?.displayTitle ?? "page"}`}>
                  {@render pageBar(candidate, tabId, cardPage, live && card.focused, tabId === rowCards.tabIds[0])}
                </div>
              {/if}
              <SpaceCard {host} space={candidate} {tabId} {pages} passive={!live} {card} />
            {/snippet}
            {@render overlay()}
          </PageColumns>
        {/if}
      {/snippet}
      {#each peek ? [peek] : [] as shownPeek (shownPeek.pageId)}
        <PeekLayer {session} peek={shownPeek} {spaces} hidden={!showsPeek}
          onClose={() => closePeek(true)} onOpenIn={openPeekIn} exit={peekExit} />
      {/each}
    </SpaceContentStrip>
    <!-- The sidebar's edge comes after the page area, whose margin moves the
         window: Chromium lays each box's drag area over those before it. -->
    <div bind:this={edgeHost} class="sidebar-edge-host"></div>
    {#if palette}
      <CommandPalette model={palette} bindings={bindings ?? []} tabs={space.tabs} />
    {/if}
    <DownloadFlights downloads={coreState(session).downloads} profileId={space.profileId} shows={palette === null && !!shell} />
    {#if switcher}
      {#key switcher.key}
        <RecentTabSwitcher {session} {spaces} {pagesByTab} {pictures}
          start={switcher.start} register={registerSwitcher} onEnd={endSwitcher} />
      {/key}
    {/if}
    <!-- Where the keyboard goes while the recent-tab switcher is held, from the first press on. -->
    <!-- svelte-ignore a11y_no_static_element_interactions, a11y_no_noninteractive_tabindex -->
    <div bind:this={switcherKeys} class="recent-tabs-keys" tabindex="-1" aria-hidden="true"
      onkeydown={(event) => {
        const start = switcherStart;
        if (!start) return;
        event.preventDefault();
        event.stopPropagation();
        if (switcherControls) switcherControls.keyDown(event);
        else if (event.key === "Tab") start.steps += event.shiftKey ? -1 : 1;
      }}
      onfocusout={() => {
        const start = switcherStart;
        if (!start) return;
        if (switcherControls) switcherControls.lostKeys();
        else start.lost = true;
      }}></div>
    <ExtensionReviewLayer {session} {spaces} />
    <!-- The title bar comes last: Chromium lays each box's drag area over
         those before it and doesn't clip them to scrolling, so a page or
         list scrolled up beneath the title bar would otherwise take back
         the stretch that moves the window. -->
    {#if shell}
      <TitleBar {shell}>
        {#if !topAddress}<NavigationButtons {browsing} {page} />{/if}
      </TitleBar>
    {/if}
  </div>
{/if}
