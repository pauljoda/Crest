import {
  CleanUpCurrentTabs,
  CurrentTabCleanup,
  type Intent,
  SetBrowsingPreferences,
  SetSeparatePinnedTabs,
  SetSpaceIdentity,
  SetSpaceSearch,
  type SpaceState,
} from "@crest/contracts";
import { useState } from "react";

import type { Session } from "../boot";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { Button, Group, keptScroll, Picker, Row, Segmented, Toggle } from "./controls";
import { ExtensionsTab } from "./ExtensionsTab";
import { groupOf, SpacePrivacySections } from "./privacy";

/** The tabs of a Space's page, which a Settings tab keeps as its selection moves between Spaces. */
export type SpacePageTab = "browsing" | "privacy" | "extensions";

/**
 * The Mac's BrowserSettingsSpacePage, as far as Windows has built it: the
 * Space's icon and name, which edits in place, over its tabs: Browsing, how
 * it searches, archives and shares pinned tabs; and Privacy, what it keeps
 * and clearing what it holds.
 */
export function SpacePage({ session, space, spaces, tab, onTab, scrolls }: {
  session: Session;
  space: SpaceState;
  spaces: readonly SpaceState[];
  tab: SpacePageTab;
  onTab: (tab: SpacePageTab) => void;
  /** Where each of the Settings tab's pages was scrolled. */
  scrolls: Map<string, number>;
}) {
  const [name, setName] = useState<{ spaceId: string; draft: string } | null>(null);
  const draft = name?.spaceId === space.id ? name.draft : space.settings.name;
  const commitName = () => {
    if (!name || name.spaceId !== space.id) return;
    const next = name.draft.trim();
    setName(null);
    if (next === space.settings.name) return;
    void session.core.send(SetSpaceIdentity({
      workspaceId: session.workspaceId, spaceId: space.id, name: next, symbol: space.settings.symbol, accent: space.settings.accent,
    })).catch(() => {});
  };
  return (
    <>
      <header className="settings-page-header space">
        <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={26} />
        <input className="settings-space-name" value={draft} aria-label="Space name" placeholder="Untitled Space"
          onChange={(event) => setName({ spaceId: space.id, draft: event.target.value })}
          onBlur={commitName}
          onKeyDown={(event) => {
            if (event.key === "Enter") event.currentTarget.blur();
            if (event.key === "Escape") setName(null);
          }} />
      </header>
      <div className="settings-space-tabs">
        <Segmented label="Space settings" value={tab} onChange={onTab}
          choices={[{ value: "browsing", label: "Browsing" }, { value: "privacy", label: "Privacy" }, { value: "extensions", label: "Extensions" }]} />
      </div>
      <div key={`${space.id}:${tab}`} className="settings-scroll" {...keptScroll(scrolls, `${space.id}:${tab}`)}>
        <div className="settings-column">
          {tab === "browsing" ? <BrowsingTab session={session} space={space} spaces={spaces} />
            : tab === "privacy" ? <SpacePrivacySections session={session} space={space} spaces={spaces} />
              : <ExtensionsTab session={session} space={space} spaces={spaces} />}
        </div>
      </div>
    </>
  );
}

function send(session: Session, intent: Intent) {
  return session.core.send(intent).then(() => true, () => false);
}

/** BrowserSpaceBrowsingSection, with the group's shared pins and Archive Now. */
function BrowsingTab({ session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] }) {
  const preferences = space.settings.browsingPreferences;
  const catalog = session.core.state.search;
  const providers = catalog?.providers ?? [];
  const chosen = preferences.followsDefaultSearch ? "default"
    : providers.find((provider) => (preferences.selectedCustomEngineId
      ? provider.customId === preferences.selectedCustomEngineId : provider.builtIn === preferences.selectedBuiltInEngine))?.name ?? "default";
  const suggestions = preferences.followsDefaultSuggestions ? "default" : preferences.searchSuggestionsEnabled ? "on" : "off";
  const defaultSuggestions = catalog?.catalog.suggestionsEnabled ? "On" : "Off";
  const setSearch = (provider: string, suggestion: string) => void send(session, SetSpaceSearch({
    workspaceId: session.workspaceId, spaceId: space.id,
    provider: provider === "default" ? null : providers.find((candidate) => candidate.name === provider) ?? null,
    suggestionsEnabled: suggestion === "default" ? null : suggestion === "on",
  }));
  const setBrowsing = (change: Partial<{ currentTabCleanup: typeof preferences.currentTabCleanup }>) =>
    void send(session, SetBrowsingPreferences({
      workspaceId: session.workspaceId, spaceId: space.id, currentTabCleanup: change.currentTabCleanup ?? preferences.currentTabCleanup,
      contentBlocking: preferences.contentBlocking, dataRetention: preferences.dataRetention,
    }));
  const group = groupOf(space, spaces);
  return (
    <>
      <Group title="Browsing" footer="Search suggestions send what you type to the search engine.">
        <Picker title="Search with" value={chosen}
          choices={[{ value: "default", label: `Default (${catalog?.default.title ?? "Search"})` }, ...providers.map((provider) => ({ value: provider.name, label: provider.title }))]}
          onChange={(provider) => setSearch(provider, suggestions)} />
        <Picker title="Search suggestions" value={suggestions}
          choices={[{ value: "default", label: `Default (${defaultSuggestions})` }, { value: "on", label: "On" }, { value: "off", label: "Off" }]}
          onChange={(suggestion) => setSearch(chosen, suggestion)} />
        <Picker title="Archive current tabs" value={preferences.currentTabCleanup} defaultValue={CurrentTabCleanup.after12Hours}
          choices={CurrentTabCleanup.all.map((value) => ({ value, label: value.title }))}
          onChange={(currentTabCleanup) => setBrowsing({ currentTabCleanup })} />
        <Row title="Archive current tabs now">
          <Button onClick={() => void send(session, CleanUpCurrentTabs({ workspaceId: session.workspaceId, spaceId: space.id }))}>Archive Now</Button>
        </Row>
      </Group>
      {group.members.length > 1 && (
        <Group footer={space.settings.separatesPinnedTabs
          ? `Each Space of ${group.primary.settings.name}’s group shows its own pinned tabs.`
          : `Every Space of ${group.primary.settings.name}’s group shows ${group.primary.settings.name}’s pinned tabs.`}>
          <Toggle title="Separate Pinned Tabs" checked={space.settings.separatesPinnedTabs}
            onChange={(separates) => void send(session, SetSeparatePinnedTabs({ workspaceId: session.workspaceId, spaceId: space.id, separates }))} />
        </Group>
      )}
    </>
  );
}
