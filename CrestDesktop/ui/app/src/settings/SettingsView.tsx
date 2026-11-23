import type { SpaceState } from "@crest/contracts";
import { useEffect, useState, useSyncExternalStore } from "react";

import crestIcon from "../../../../../CrestShared/Resources/AppIconPreviews.xcassets/CrestPreview.imageset/icon.png";
import type { Session } from "../boot";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { Symbol } from "../symbols";
import { residentNativeTabs } from "../native-tabs";
import { useCoreVersion } from "../use-core";
import { destinations, leadingRows, matches, type SettingsPageName, sidebarTint, trailingRows } from "./catalog";
import { keptScroll } from "./controls";
import { SettingsPane } from "./panes";
import { SpacePage, type SpacePageTab } from "./SpacePage";
import "./settings.css";

/** What Settings shows: one of its pages, or a Space's page. */
export type SettingsSelection = { readonly kind: "page"; readonly name: SettingsPageName } | { readonly kind: "space"; readonly spaceId: string; readonly tab?: SpacePageTab };

/**
 * Where a Settings tab is asked to go, from the palette's Settings Pages or
 * a menu's Edit Space…: each request names its tab and carries a revision,
 * and the tab takes only a newer one, as the Mac's do.
 */
let request: { readonly tabId: string; readonly selection: SettingsSelection; readonly revision: number } | null = null;
const listeners = new Set<() => void>();

export function requestSettings(tabId: string, selection: SettingsSelection) {
  request = { tabId, selection, revision: (request?.revision ?? 0) + 1 };
  for (const listener of listeners) listener();
}

function useSettingsRequest() {
  return useSyncExternalStore((listener) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  }, () => request);
}

/**
 * What one Settings tab keeps while it stays open, as the Mac's
 * BrowserSettingsTabState: the page it shows, the tab a Space's page shows
 * as the selection moves between Spaces, the last request it took, and
 * where each page was scrolled.
 */
interface SettingsTabState {
  selection: SettingsSelection;
  spaceTab: SpacePageTab;
  taken: number;
  readonly scrolls: Map<string, number>;
}

const tabStates = new Map<string, SettingsTabState>();

function tabState(tabId: string): SettingsTabState {
  let state = tabStates.get(tabId);
  if (!state) {
    state = { selection: { kind: "page", name: "general" }, spaceTab: "appearance", taken: 0, scrolls: new Map() };
    tabStates.set(tabId, state);
  }
  return state;
}

/**
 * The Chromium build the window runs, as its engine credits name it: the
 * full version where the browser tells it, which the user agent string
 * shortens.
 */
function useEngineCredit(): string | null {
  const short = /Chrome\/([\d.]+)/.exec(navigator.userAgent)?.[1] ?? null;
  const [full, setFull] = useState<string | null>(null);
  useEffect(() => {
    const data = (navigator as Navigator & {
      userAgentData?: { getHighEntropyValues(hints: string[]): Promise<{ fullVersionList?: { brand: string; version: string }[] }> };
    }).userAgentData;
    void data?.getHighEntropyValues(["fullVersionList"]).then((values) => {
      const chromium = values.fullVersionList?.find((entry) => entry.brand === "Chromium" || entry.brand === "Google Chrome");
      if (chromium) setFull(chromium.version);
    }).catch(() => {});
  }, []);
  const version = full ?? short;
  return version ? `Chromium ${version}` : null;
}

/**
 * The Mac's BrowserSettingsView, the Settings tab's content: a 224-wide
 * sidebar with the build, a search field, Settings' pages and the Spaces,
 * then the chosen page, its title over one centred column of grouped
 * settings. Pages change at once.
 */
export function SettingsView({ session, tabId, spaces, shownSpace }: {
  session: Session;
  /** The Settings tab, whose page and scroll positions stay while it does. */
  tabId: string;
  spaces: readonly SpaceState[];
  /** The Space the window shows, whose Settings tab this is. */
  shownSpace: SpaceState;
}) {
  useCoreVersion(session);
  const kept = tabState(tabId);
  const [selection, choose] = useState<SettingsSelection>(kept.selection);
  const setSelection = (next: SettingsSelection) => {
    kept.selection = next;
    choose(next);
  };
  const [spaceTab, chooseSpaceTab] = useState<SpacePageTab>(kept.spaceTab);
  const [search, setSearch] = useState("");
  const asked = useSettingsRequest();
  useEffect(() => {
    if (!asked || asked.tabId !== tabId || asked.revision <= kept.taken) return;
    kept.taken = asked.revision;
    setSelection(asked.selection);
    // A request for a Space's page may name its tab, as Extensions does.
    if (asked.selection.kind === "space" && asked.selection.tab) {
      kept.spaceTab = asked.selection.tab;
      chooseSpaceTab(asked.selection.tab);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [asked, tabId]);
  // The tab holds Settings while its state lives, so its row reads loaded;
  // a closed Settings tab's state goes with it.
  useEffect(() => void residentNativeTabs.add(tabId), [tabId]);
  useEffect(() => {
    const open = new Set(spaces.flatMap((space) => space.tabs.map((tab) => tab.id)));
    for (const id of tabStates.keys()) {
      if (open.has(id)) continue;
      tabStates.delete(id);
      residentNativeTabs.delete(id);
    }
  }, [spaces]);
  // A Space that left goes back to General.
  const selectedSpace = selection.kind === "space" ? spaces.find((space) => space.id === selection.spaceId) : undefined;
  useEffect(() => {
    if (selection.kind === "space" && !selectedSpace) setSelection({ kind: "page", name: "general" });
  }, [selection, selectedSpace]);
  const dark = matchMedia("(prefers-color-scheme: dark)").matches;
  const rowsFor = (names: readonly SettingsPageName[]) => names.filter((name) => matches(destinations[name], search));
  const leading = rowsFor(leadingRows);
  const trailing = rowsFor(trailingRows);
  const spaceMatches = (space: SpaceState) => !search.trim() || matches(destinations.spaces, search)
    || space.settings.name.toLowerCase().includes(search.trim().toLowerCase());
  const listedSpaces = spaces.filter(spaceMatches);
  const credit = useEngineCredit();

  const pageRow = (name: SettingsPageName) => {
    const destination = destinations[name];
    const selected = selection.kind === "page" && selection.name === name;
    return (
      <button key={name} type="button" className={`settings-nav-row${selected ? " selected" : ""}`} aria-current={selected || undefined}
        onClick={() => setSelection({ kind: "page", name })}>
        <span className="settings-nav-symbol" style={{ color: sidebarTint(destination.color, dark) }}>
          <Symbol name={destination.symbol} size={15} />
        </span>
        <span className="settings-nav-title">{destination.navigationTitle}</span>
      </button>
    );
  };

  return (
    <div className="settings" data-testid="settings">
      <aside className="settings-sidebar" aria-label="Settings">
        <div className="settings-build">
          <img src={crestIcon} alt="" width={40} height={40} />
          <div>
            <div className="settings-build-name">Crest Browser</div>
            <div className="settings-build-detail">Version {__CREST_VERSION__}</div>
            {credit && <div className="settings-build-detail">{credit}</div>}
          </div>
        </div>
        <div className="settings-search">
          <Symbol name="magnifyingglass" size={13} />
          <input value={search} placeholder="Search settings" aria-label="Search settings" onChange={(event) => setSearch(event.target.value)} />
          {search && (
            <button type="button" aria-label="Clear" onClick={() => setSearch("")}>
              <Symbol name="xmark.circle.fill" size={13} />
            </button>
          )}
        </div>
        <nav className="settings-nav">
          {leading.map(pageRow)}
          {listedSpaces.length > 0 && (
            <>
              <div className="settings-nav-heading">Spaces</div>
              {listedSpaces.map((space) => {
                const selected = selection.kind === "space" && selection.spaceId === space.id;
                const sub = space.membership?.primaryId && space.membership.primaryId !== space.id;
                return (
                  <button key={space.id} type="button" className={`settings-nav-row space${selected ? " selected" : ""}${sub ? " sub" : ""}`}
                    aria-current={selected || undefined} onClick={() => setSelection({ kind: "space", spaceId: space.id })}>
                    <span className="settings-nav-symbol">
                      <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={18} />
                    </span>
                    <span className="settings-nav-title">{space.settings.name || "Untitled Space"}</span>
                    {space.settings.requiresAuthentication && <Symbol name="lock.fill" size={10} className="settings-nav-lock" />}
                  </button>
                );
              })}
            </>
          )}
          {trailing.length > 0 && <div className="settings-nav-gap" />}
          {trailing.map(pageRow)}
        </nav>
      </aside>
      <div className="settings-divider" />
      <main className="settings-page">
        {selection.kind === "page" ? (
          <>
            <header className="settings-page-header"><h2>{destinations[selection.name].title}</h2></header>
            <div key={selection.name} className="settings-scroll" {...keptScroll(kept.scrolls, selection.name)}>
              <div className="settings-column">
                <SettingsPane name={selection.name} session={session} spaces={spaces} shownSpace={shownSpace} />
              </div>
            </div>
          </>
        ) : selectedSpace ? (
          <SpacePage session={session} space={selectedSpace} spaces={spaces} scrolls={kept.scrolls} tab={spaceTab}
            onOpenSpace={(spaceId) => setSelection({ kind: "space", spaceId })}
            onTab={(next) => {
              kept.spaceTab = next;
              chooseSpaceTab(next);
            }} />
        ) : null}
      </main>
    </div>
  );
}
