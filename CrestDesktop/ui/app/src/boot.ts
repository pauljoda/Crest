import {
  AdoptLegacySession,
  type AppConfiguration,
  CatchUp,
  type Change,
  CloseWindow,
  DevicePlatform,
  EngineCapability,
  EngineKind,
  FilterListsChanged,
  GetFilterLists,
  GetSiteContentBlocking,
  LaunchEnvironmentStatics,
  LaunchPlan,
  LaunchWindows,
  OpenWindow,
  OpenWorkspace,
  ReleasePage,
  RememberWindowsForLaunch,
  RestoreSearchCatalog,
  ShowStartPage,
  SiteContentBlockingChanged,
  StartupBehavior,
  WorkspaceKind,
  type WorkspaceOpened,
} from "@crest/contracts";
import { CoreRejection, CrestCore, DevSocketTransport, ShellTransport } from "@crest/core-client";

import { DevEngine } from "./dev-engine";
import { startFilterListUpdates } from "./filter-lists";
import { touchpadPhases } from "./spaces/space-pager";

/** What a window is opened over. */
export interface Session {
  readonly core: CrestCore;
  readonly workspaceId: string;
  readonly windowId: string;
  /** The development engine's frames, outside Crest's Chromium. */
  readonly engine: DevEngine | null;
  /** Crest's Chromium, which embeds each page's own surface. */
  readonly shell: ShellTransport | null;
  /** Set once the window is closing, when it opens no more pages. */
  readonly closing: { current: boolean };
}

/** The interface runs on Windows, whose keys and rules the core keeps apart from the Mac's. */
const configuration: AppConfiguration = {
  storageDirectory: null,
  platform: DevicePlatform.windows,
  importNames: null,
  languages: [navigator.language],
  filterResourcesUrl: null,
};

/** What Chromium does in Crest, as the Mac registers it, less what Windows cannot back yet. */
const chromiumCapabilities = [
  EngineCapability.pages,
  EngineCapability.navigation,
  EngineCapability.find,
  EngineCapability.zoom,
  EngineCapability.interactionState,
  EngineCapability.pageResidency,
  EngineCapability.workspaceProfiles,
  EngineCapability.workspaceTransfer,
  EngineCapability.profileDeletion,
  EngineCapability.beforeUnload,
  EngineCapability.downloads,
  EngineCapability.permissions,
  EngineCapability.viewportCapture,
  EngineCapability.inspector,
  EngineCapability.internalPages,
  EngineCapability.fullPageCapture,
  EngineCapability.pdf,
  EngineCapability.webArchive,
  EngineCapability.print,
  EngineCapability.localFiles,
  EngineCapability.extensions,
  EngineCapability.popups,
  EngineCapability.featureFlags,
  EngineCapability.audioSpectrum,
  EngineCapability.contentBlocking,
];

/**
 * Starts the core and opens this window onto a workspace. Inside Crest's
 * Chromium the shell hosts the core and Chromium's binding is the engine;
 * in an ordinary browser the development bridge hosts the core and frames
 * stand in for the engine.
 */
export async function boot(bridgeUrl: string): Promise<Session> {
  const shell = ShellTransport.available() ? new ShellTransport() : null;
  let core: CrestCore;
  let engine: DevEngine | null = null;
  let windowId: string;
  let workspaceKind = WorkspaceKind.practice;
  let launches = false;
  if (shell) {
    const hello = await shell.hello();
    windowId = hello.window.toLowerCase();
    launches = hello.launch ?? false;
    // A touchpad's swipes between Spaces follow its own phases where the engine sends them.
    if (hello.wheelPhases) {
      touchpadPhases.available = true;
      shell.onWheel = (wheel) => touchpadPhases.emit(wheel);
    }
    // The core keeps the session in the engine's own profile folder, apart
    // from Chromium's profiles.
    core = await CrestCore.start(shell, { ...configuration, storageDirectory: `${hello.userData}\\Crest` });
    await core.registerNativeEngine({ kind: EngineKind.chromium, capabilities: chromiumCapabilities, isDefault: true });
    workspaceKind = WorkspaceKind.persistent;
  } else {
    windowId = crypto.randomUUID();
    core = await CrestCore.start(new DevSocketTransport(bridgeUrl), configuration);
    engine = new DevEngine();
    await core.registerEngine(
      {
        kind: EngineKind.chromium,
        capabilities: [
          EngineCapability.pages,
          EngineCapability.navigation,
          EngineCapability.workspaceProfiles,
          EngineCapability.profileDeletion,
        ],
        isDefault: true,
      },
      engine,
    );
  }
  const opened = await openWorkspace(core, workspaceKind);
  const workspace = opened.find((change): change is WorkspaceOpened => change.$kind === "WorkspaceOpened");
  if (!workspace) throw new Error("The core opened no workspace.");
  // A launch restores the search catalog for the person's language and
  // region once the session that keeps the device's preferences is open, as
  // the Mac's launch does before any window shows.
  if (!shell || launches) {
    const locale = new Intl.Locale(navigator.language);
    await core.send(RestoreSearchCatalog({ language: locale.language, region: locale.region ?? null }));
  }
  // Each window keeps its own read model, so one that opens after others
  // hears what it missed: the engines and shortcuts, the search catalog, the
  // downloads, and the questions still waiting.
  core.state.apply((await core.query(CatchUp())).changes);
  // Ad blocking's lists and the sites it leaves alone, which the core
  // publishes only as they change, read once as the Mac's core reads them.
  core.state.apply([
    FilterListsChanged({ lists: await core.query(GetFilterLists()) }),
    SiteContentBlockingChanged({ sites: await core.query(GetSiteContentBlocking()) }),
  ]);
  if (shell && launches) windowId = await reopenLaunchWindows(core, shell);
  // Crest's own windows are saved windows, which the next launch reopens as
  // they were; a development window starts afresh.
  await core.send(
    OpenWindow({
      windowId,
      workspaceId: workspace.workspaceId,
      saved: shell !== null,
      copyingWindowId: null,
      showingSpaceId: null,
      showingTabs: [],
      restoresTabs: shell !== null,
    }),
  );
  if (shell && launches) await presentLaunchChoice(core, workspace.workspaceId, windowId);
  const closing = { current: false };
  if (shell) {
    closesThroughCore(core, shell, windowId, closing);
    // Crest's Chromium downloads the filter lists, as the Mac app does.
    startFilterListUpdates(core, shell);
  }
  return { core, engine, shell, workspaceId: workspace.workspaceId, windowId, closing };
}

/**
 * The launch's frontmost window opens as the person chose: on a Start Page,
 * which the core chooses or opens in the Space the window shows without
 * making it the tab the session remembers, or on the tab it left. Every other
 * window opens on the tab it left, as on the Mac.
 */
async function presentLaunchChoice(core: CrestCore, workspaceId: string, windowId: string) {
  const plan = await core.query(LaunchPlan({ workspaceId, platform: DevicePlatform.windows, environment: LaunchEnvironmentStatics.installed }));
  const spaceId = core.state.windows.get(windowId)?.shownSpaceId;
  if (plan.startup !== StartupBehavior.showStartPage || !spaceId) return;
  await core.send(ShowStartPage({
    workspaceId, windowId, spaceId, tabId: crypto.randomUUID(), outsideSplits: false, placesAsNewTab: false,
  })).catch((error: unknown) => {
    if (!(error instanceof CoreRejection)) throw error;
  });
}

/**
 * Brings back the windows the last launch left open, each under the identity
 * the core saved it by: this window becomes the frontmost, and the shell
 * reopens the others behind it. Answers this window's identity.
 */
async function reopenLaunchWindows(core: CrestCore, shell: ShellTransport): Promise<string> {
  const plan = await core.query(LaunchWindows({ environment: LaunchEnvironmentStatics.installed }));
  await shell.adoptWindow(plan.startupWindowId);
  for (const id of plan.windowIds) {
    if (id !== plan.startupWindowId) await shell.reopenWindow(id);
  }
  return plan.startupWindowId;
}

/**
 * However this window is asked to close, the core hears first. The window's
 * pages go for good, as a closing Mac window lets its tabs' pages go, so the
 * engine never closes them by itself, which would close their tabs. Then the
 * last window remembers every saved window for the next launch, as quitting
 * the Mac app does, and any other window closes for good. The window goes
 * either way.
 */
function closesThroughCore(core: CrestCore, shell: ShellTransport, windowId: string, closing: { current: boolean }) {
  shell.onCloseRequested = (last, stack, pages) => {
    closing.current = true;
    const told = (async () => {
      for (const pageId of pages) await core.send(ReleasePage({ pageId: pageId.toLowerCase(), keepsState: false }));
      await core.send(
        last
          ? RememberWindowsForLaunch({ windowIds: stack.map((id) => id.toLowerCase()) })
          : CloseWindow({ windowId }),
      );
    })();
    void told.catch(() => undefined).finally(() => void shell.window("close"));
  };
}

/**
 * Opens the workspace a window shows. The session the core keeps in its file
 * opens as it was saved; a file that holds none yet, on a first launch, first
 * takes the session a first install starts with, as the Mac's first launch
 * does when it has no earlier release to carry over.
 */
async function openWorkspace(core: CrestCore, kind: WorkspaceKind): Promise<readonly Change[]> {
  try {
    return await core.send(OpenWorkspace({ kind, seed: null }));
  } catch (error) {
    if (!(error instanceof CoreRejection) || error.rejection.$kind !== "NoStoredSession") throw error;
    await core.send(
      AdoptLegacySession({ installed: { core: null, wholeGraph: null, history: [], journal: null }, seed: null }),
    );
    return core.send(OpenWorkspace({ kind, seed: null }));
  }
}
