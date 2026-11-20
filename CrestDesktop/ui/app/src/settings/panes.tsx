import {
  AdoptLinkPreferences,
  type AppPreferences,
  AppPreferencesStatics,
  ChoosePeekModifier,
  ClearPaletteChoices,
  type Intent,
  LinkBehavior,
  LinkPeekModifier,
  NewTabPosition,
  OpenTab,
  PaletteLayout,
  SavedTabClosePolicy,
  SearchProviderSpaceTrigger,
  SetAppPreferences,
  SetDefaultSearch,
  SetDefaultSpace,
  SetLinkBehavior,
  SetPrivateSearch,
  SetSearchSuggestions,
  type SpaceState,
  StartupBehavior,
  TabPlacement,
} from "@crest/contracts";
import { useEffect, useState } from "react";

import crestIcon from "../../../../../CrestShared/Resources/AppIconPreviews.xcassets/CrestPreview.imageset/icon.png";
import type { Session } from "../boot";
import { Symbol } from "../symbols";
import type { SettingsPageName } from "./catalog";
import { Button, Group, Picker, Row, Segmented, Toggle } from "./controls";
import { AdBlockingPane } from "./AdBlockingPane";
import { SpacePrivacySections } from "./privacy";
import { ShortcutsPane } from "./ShortcutsPane";

interface PaneProps {
  readonly session: Session;
  readonly spaces: readonly SpaceState[];
  readonly shownSpace: SpaceState;
}

/** The page Settings shows for `name`. */
export function SettingsPane({ name, ...props }: PaneProps & { name: SettingsPageName }) {
  switch (name) {
    case "general": return <GeneralPane {...props} />;
    case "tabs": return <TabsPane {...props} />;
    case "search": return <SearchPane {...props} />;
    case "lookAndFeel": return <AppearancePane {...props} />;
    case "links": return <LinksPane {...props} />;
    case "shortcuts": return <ShortcutsPane session={props.session} />;
    case "privacy": return <PrivacyPane {...props} />;
    case "adBlocking": return <AdBlockingPane session={props.session} />;
    case "about": return <AboutPane {...props} />;
    default: return null;
  }
}

/** Sends `intent`; a refusal leaves the setting as it was. */
function send(session: Session, intent: Intent) {
  void session.core.send(intent).catch(() => {});
}

/** The app's preferences and how to change one, which sends the whole record, as the Mac's store does. */
function useAppPreferences(session: Session): [AppPreferences, (change: Partial<AppPreferences>) => void] {
  const preferences = session.core.state.workspaces.get(session.workspaceId)?.appPreferences ?? AppPreferencesStatics.default;
  const set = (change: Partial<AppPreferences>) =>
    send(session, SetAppPreferences({ workspaceId: session.workspaceId, preferences: { ...preferences, ...change } }));
  return [preferences, set];
}

/** The device's link preferences, which the core publishes once asked. */
function useLinkPreferences(session: Session) {
  const links = session.core.state.links;
  useEffect(() => {
    if (!links) send(session, AdoptLinkPreferences({ preferences: null }));
  }, [session, links]);
  const setBehavior = (behavior: LinkBehavior, isOn: boolean) => send(session, SetLinkBehavior({ behavior, isOn }));
  return { links, setBehavior };
}

const defaults = AppPreferencesStatics.default;

/** BrowserGeneralSettingsPane, as Windows offers it: how Crest opens, and the Space it opens in. */
function GeneralPane({ session, spaces }: PaneProps) {
  const [preferences, set] = useAppPreferences(session);
  const workspace = session.core.state.workspaces.get(session.workspaceId);
  const defaultSpaceId = workspace?.defaultSpaceId ?? spaces[0]?.id ?? "";
  return (
    <Group title="Startup">
      <Picker title="When Crest opens" value={preferences.startup} defaultValue={defaults.startup}
        choices={[StartupBehavior.lastActiveTab, StartupBehavior.showStartPage].map((value) => ({ value, label: value.title }))}
        onChange={(startup) => set({ startup })} />
      <Picker title="Default Space" value={defaultSpaceId}
        choices={spaces.map((space) => ({ value: space.id, label: space.settings.name || "Untitled Space" }))}
        onChange={(spaceId) => send(session, SetDefaultSpace({ workspaceId: session.workspaceId, spaceId }))} />
    </Group>
  );
}

/** BrowserTabsSettingsPane: new tabs, pinned and saved tabs, Split View and switching. */
function TabsPane({ session }: PaneProps) {
  const [preferences, set] = useAppPreferences(session);
  const { links, setBehavior } = useLinkPreferences(session);
  return (
    <>
      <Group title="New tabs" footer="Hold Shift as you open a link to do the opposite.">
        <Toggle title="Switch to tabs opened from links" checked={links?.focusesNewTabs ?? false} defaultValue={false}
          disabled={!links} onChange={(on) => setBehavior(LinkBehavior.focusesNewTabs, on)} />
        <Toggle title="Follow tabs moved to another Space" checked={links?.followsMovedTabs ?? true} defaultValue
          disabled={!links} onChange={(on) => setBehavior(LinkBehavior.followsMovedTabs, on)} />
        <Picker title="Open new tabs at" value={preferences.newTabPosition} defaultValue={defaults.newTabPosition}
          choices={NewTabPosition.all.map((value) => ({ value, label: value.title }))}
          onChange={(newTabPosition) => set({ newTabPosition })} />
        <Toggle title="Open new tabs in the current folder" checked={preferences.newTabsJoinFolder} defaultValue={defaults.newTabsJoinFolder}
          onChange={(newTabsJoinFolder) => set({ newTabsJoinFolder })} />
      </Group>
      <Group title="Pinned and saved tabs">
        <Picker title="After closing" value={preferences.savedTabClose} defaultValue={defaults.savedTabClose}
          choices={SavedTabClosePolicy.all.map((value) => ({ value, label: value.title }))}
          onChange={(savedTabClose) => set({ savedTabClose })} />
        <Toggle title="Keep saved tabs after unloading" checked={preferences.unloadedSavedTabsStay} defaultValue={defaults.unloadedSavedTabsStay}
          onChange={(unloadedSavedTabsStay) => set({ unloadedSavedTabsStay })} />
        <Toggle title="Click the favicon to return to the saved URL" checked={preferences.savedTabFaviconReturnsToSavedUrl}
          defaultValue={defaults.savedTabFaviconReturnsToSavedUrl}
          onChange={(savedTabFaviconReturnsToSavedUrl) => set({ savedTabFaviconReturnsToSavedUrl })} />
      </Group>
      <Group title="Split View">
        <Toggle title="Focus follows pointer" checked={preferences.splitFocusFollowsMouse} defaultValue={defaults.splitFocusFollowsMouse}
          onChange={(splitFocusFollowsMouse) => set({ splitFocusFollowsMouse })} />
      </Group>
      <Group title="Switching">
        <Toggle title="Show recent tabs while switching" checked={preferences.showsRecentTabs} defaultValue={defaults.showsRecentTabs}
          onChange={(showsRecentTabs) => set({ showsRecentTabs })} />
      </Group>
    </>
  );
}

/** BrowserSearchSettingsPane: the default search, the palette's results and sections, and its typing. */
function SearchPane({ session }: PaneProps) {
  const [preferences, set] = useAppPreferences(session);
  const catalog = session.core.state.search;
  const palette = preferences.palette;
  const setPalette = (change: Partial<typeof palette>) => set({ palette: { ...palette, ...change } });
  const [confirmingClear, setConfirmingClear] = useState(false);
  const providers = catalog?.providers ?? [];
  const providerChoice = providers.map((provider) => ({ value: provider.name, label: provider.title }));
  const byName = (name: string) => providers.find((provider) => provider.name === name);
  const sources = palette.sources.filter((choice) => choice.source.isSection);
  const extras = palette.sources.filter((choice) => !choice.source.isSection && ["settingsPages", "scopes", "calculator"].includes(choice.source.name));
  const setSource = (name: string, change: { isEnabled?: boolean; limit?: number | null }) =>
    setPalette({ sources: palette.sources.map((choice) => (choice.source.name === name ? { ...choice, ...change } : choice)) });
  const move = (index: number, by: number) => {
    const order = [...palette.sources];
    const from = order.indexOf(sources[index]);
    const to = order.indexOf(sources[index + by]);
    if (from < 0 || to < 0) return;
    [order[from], order[to]] = [order[to], order[from]];
    setPalette({ sources: order });
  };
  const defaultOrder = defaults.palette.sources.map((choice) => choice.source.name).join();
  const limits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20];
  return (
    <>
      <Group title="Search" footer="Each device keeps its own default search. Search suggestions send what you type to the search engine.">
        {catalog && (
          <>
            <Picker title="Default search" value={catalog.default.name} choices={providerChoice}
              onChange={(name) => {
                const provider = byName(name);
                if (provider) send(session, SetDefaultSearch({ provider }));
              }} />
            <Picker title="Private windows" value={catalog.privateDefault.name} choices={providerChoice}
              onChange={(name) => {
                const provider = byName(name);
                if (provider) send(session, SetPrivateSearch({ provider }));
              }} />
            <Toggle title="Search suggestions" checked={catalog.catalog.suggestionsEnabled} defaultValue={false}
              onChange={(enabled) => send(session, SetSearchSuggestions({ enabled }))} />
          </>
        )}
        <Toggle title="Tab to search providers" subtitle="Type a provider’s name or shortcut and press Tab."
          checked={palette.searchesSitesWithTab} defaultValue={defaults.palette.searchesSitesWithTab}
          onChange={(searchesSitesWithTab) => setPalette({ searchesSitesWithTab })} />
        <Picker title="Space to search providers" subtitle={palette.providerSpaceTrigger.example} value={palette.providerSpaceTrigger}
          defaultValue={defaults.palette.providerSpaceTrigger}
          choices={SearchProviderSpaceTrigger.all.map((value) => ({ value, label: value.title }))}
          onChange={(providerSpaceTrigger) => setPalette({ providerSpaceTrigger })} />
      </Group>
      <Group title="Results">
        <Row title="Layout">
          <Segmented label="Layout" value={palette.layout} choices={PaletteLayout.all.map((value) => ({ value, label: value.title }))}
            onChange={(layout) => setPalette({ layout })} />
        </Row>
        <Toggle title="Top Hit" checked={palette.showsTopHit} defaultValue={defaults.palette.showsTopHit}
          onChange={(showsTopHit) => setPalette({ showsTopHit })} />
        <Toggle title="Prefer open tabs" checked={palette.prefersOpenTabs} defaultValue={defaults.palette.prefersOpenTabs}
          onChange={(prefersOpenTabs) => setPalette({ prefersOpenTabs })} />
        <Toggle title="Show match reasons" subtitle="Notes why each result is there, such as “Often visited” or “Already open”."
          checked={palette.showsReasons} defaultValue={defaults.palette.showsReasons} onChange={(showsReasons) => setPalette({ showsReasons })} />
      </Group>
      <Group title="Sections" footer="Use the arrows to change the order."
        onReset={palette.sources.map((choice) => choice.source.name).join() !== defaultOrder ? () => setPalette({ sources: defaults.palette.sources }) : null}>
        {sources.map((choice, index) => (
          <Row key={choice.source.name} title={choice.source.title}>
            <span className="settings-order">
              <button type="button" aria-label="Move Up" disabled={index === 0} onClick={() => move(index, -1)}><Symbol name="chevron.up" size={11} /></button>
              <button type="button" aria-label="Move Down" disabled={index === sources.length - 1} onClick={() => move(index, 1)}><Symbol name="chevron.down" size={11} /></button>
            </span>
            <span className="settings-select compact">
              <select aria-label={`${choice.source.title} limit`} value={choice.limit ?? choice.source.defaultLimit}
                onChange={(event) => setSource(choice.source.name, { limit: Number(event.target.value) })}>
                {limits.map((limit) => <option key={limit} value={limit}>Up to {limit}</option>)}
              </select>
              <Symbol name="chevron.up.chevron.down" size={11} className="settings-select-glyph" />
            </span>
            <SwitchFor label={choice.source.title} checked={choice.isEnabled} onChange={(isEnabled) => setSource(choice.source.name, { isEnabled })} />
          </Row>
        ))}
      </Group>
      <Group title="Also show">
        {extras.map((choice) => (
          <Toggle key={choice.source.name} title={choice.source.title} subtitle={choice.source.detail ?? undefined}
            checked={choice.isEnabled} defaultValue={choice.source.isEnabledByDefault}
            onChange={(isEnabled) => setSource(choice.source.name, { isEnabled })} />
        ))}
      </Group>
      <Group title="Typing" footer="Learned choices stay on this device.">
        <Toggle title="Complete addresses inline" checked={palette.completesInline} defaultValue={defaults.palette.completesInline}
          onChange={(completesInline) => setPalette({ completesInline })} />
        <Toggle title="Learn from my choices" checked={palette.learnsChoices} defaultValue={defaults.palette.learnsChoices}
          onChange={(learnsChoices) => setPalette({ learnsChoices })} />
        <Row title={confirmingClear ? "The palette forgets which results you chose for what you typed." : "Learned choices"}>
          {confirmingClear ? (
            <>
              <Button onClick={() => setConfirmingClear(false)}>Cancel</Button>
              <Button destructive onClick={() => {
                send(session, ClearPaletteChoices());
                setConfirmingClear(false);
              }}>Clear Learned Choices</Button>
            </>
          ) : <Button destructive onClick={() => setConfirmingClear(true)}>Clear Learned Choices…</Button>}
        </Row>
      </Group>
    </>
  );
}

function SwitchFor({ label, checked, onChange }: { label: string; checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <button type="button" role="switch" aria-checked={checked} aria-label={label} className={`settings-switch${checked ? " on" : ""}`}
      onClick={() => onChange(!checked)}>
      <span className="settings-switch-knob" />
    </button>
  );
}

/** A preference this device keeps for itself, in local storage, as the Mac's appearance store keeps its own. */
function useDeviceToggle(key: string, fallback: boolean): [boolean, (on: boolean) => void] {
  const read = () => {
    try {
      const stored = localStorage.getItem(key);
      return stored === null ? fallback : stored !== "false";
    } catch {
      return fallback;
    }
  };
  const [value, setValue] = useState(read);
  return [value, (on) => {
    try {
      localStorage.setItem(key, String(on));
    } catch {
      // The preference stays for this session only.
    }
    setValue(on);
  }];
}

/** BrowserLookAndFeelSettingsPane, as far as Windows draws it: motion, previews on hover, and Super Copy. */
function AppearancePane({ session }: PaneProps) {
  const [slides, setSlides] = useDeviceToggle("crest.appearance.animate-space-pages", true);
  const [previewsTabs, setPreviewsTabs] = useDeviceToggle("crest.appearance.hover-preview.tabs", true);
  const { links, setBehavior } = useLinkPreferences(session);
  return (
    <>
      <Group title="Window">
        <Toggle title="Animate pages when switching Spaces" checked={slides} defaultValue onChange={setSlides} />
      </Group>
      <Group title="Address field"
        footer="With Super Copy, copying or sharing a link leaves out its trackers, using AdGuard's URL Tracking filter. Copying the selected address keeps everything.">
        <Toggle title="Super Copy" checked={links?.cleansCopiedLinks ?? true} defaultValue disabled={!links}
          onChange={(on) => setBehavior(LinkBehavior.cleansCopiedLinks, on)} />
      </Group>
      <Group title="Preview hover" footer="Applies to every Space on this device. Doesn’t sync.">
        <Toggle title="Tabs" checked={previewsTabs} defaultValue onChange={setPreviewsTabs} />
      </Group>
    </>
  );
}

/** Windows names the modifier keys Ctrl, Alt and Shift, where the Mac has ⌘, ⌥ and ⇧. */
const modifierTitles: Readonly<Record<string, string>> = { option: "Alt", command: "Ctrl", shift: "Shift" };

/** BrowserLinkSettingsPane's Peek section, as Windows opens Peeks. */
function LinksPane({ session }: PaneProps) {
  const { links, setBehavior } = useLinkPreferences(session);
  if (!links) return null;
  const modifier = links.peekModifier;
  const newTabKey = modifierTitles[modifier.name === "command" ? "option" : "command"];
  return (
    <Group title="Peek" footer={`${newTabKey}-click opens a new tab${modifier.name === "command" ? ", while Ctrl-click opens Peek" : ""}.`}>
      <Toggle title="Open cross-site links from pinned and saved tabs in Peek" checked={links.opensPeekAutomatically} defaultValue
        onChange={(on) => setBehavior(LinkBehavior.opensPeekAutomatically, on)} />
      <Picker title="Open Peek with" value={modifier.name} defaultValue="option"
        choices={LinkPeekModifier.all.map((value) => ({ value: value.name, label: modifierTitles[value.name] ?? value.title }))}
        onChange={(name) => {
          const chosen = LinkPeekModifier.named(name);
          if (chosen) send(session, ChoosePeekModifier({ modifier: chosen }));
        }} />
      <Toggle title="Dim the page behind Peek" checked={links.dimsPageBehindPeek} defaultValue
        onChange={(on) => setBehavior(LinkBehavior.dimsPageBehindPeek, on)} />
    </Group>
  );
}

/** BrowserSystemPrivacySettingsPane's Spaces: each Space's own privacy page. */
/**
 * BrowserPrivacySettingsPane: a Space to look at, then what it keeps, the
 * choices it saved for sites, the sites that keep data in it, and clearing
 * what it browsed. Ad blocking holds for every Space, so it has a pane of
 * its own.
 */
function PrivacyPane({ session, spaces, shownSpace }: PaneProps) {
  const [picked, setPicked] = useState<string | null>(null);
  // A Space that left gives way to the one the window shows.
  const space = spaces.find((candidate) => candidate.id === picked) ?? shownSpace;
  return (
    <>
      <Group>
        <Picker title="Space" value={space.id} choices={spaces.map((candidate) => ({ value: candidate.id, label: candidate.settings.name || "Untitled Space" }))}
          onChange={setPicked} />
      </Group>
      <SpacePrivacySections key={space.id} session={session} space={space} spaces={spaces} />
    </>
  );
}

/** BrowserAboutSettingsPane: who Crest is, and where to talk about it. */
function AboutPane({ session, shownSpace }: PaneProps) {
  const open = (address: string) => send(session, OpenTab({
    workspaceId: session.workspaceId, windowId: session.windowId, spaceId: shownSpace.id, tabId: crypto.randomUUID(),
    content: { address, view: null, title: null }, placement: TabPlacement.current, afterTabId: null, shows: true,
    placesAsNewTab: true, savesInSavedFolder: false,
  }));
  const links = [
    // BrowserAboutLinks.
    { title: "Share Feedback on r/CrestBrowser", address: "https://www.reddit.com/r/CrestBrowser" },
    { title: "Report an Issue", address: "https://github.com/pauljoda/Crest/issues/new/choose" },
    { title: "View the Roadmap", address: "https://github.com/users/pauljoda/projects/3" },
  ];
  return (
    <>
      <div className="settings-about">
        <img src={crestIcon} alt="" width={56} height={56} />
        <div>
          <div className="settings-about-name">Crest Browser</div>
          <div className="settings-about-version">Version {__CREST_VERSION__}</div>
        </div>
      </div>
      <Group title="Community and support" footer="Reddit is public. Leave out private details.">
        {links.map((link) => (
          <button key={link.title} type="button" className="settings-row settings-link-row" onClick={() => open(link.address)}>
            <span className="settings-row-title">{link.title}</span>
            <Symbol name="arrow.up.right" size={12} className="settings-row-chevron" />
          </button>
        ))}
      </Group>
    </>
  );
}
