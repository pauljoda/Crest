<script lang="ts" module>
  import type { Intent } from "@crest/contracts";

  import type { Session } from "../boot";

  function send(session: Session, intent: Intent) {
    return session.core.send(intent).then(() => true, () => false);
  }
</script>

<script lang="ts">
  import {
    CleanUpCurrentTabs,
    CurrentTabCleanup,
    SetBrowsingPreferences,
    SetSeparatePinnedTabs,
    SetSpaceSearch,
    type SpaceState,
  } from "@crest/contracts";

  import { useCoreVersion } from "../use-core";
  import { Button, Group, Picker, Row, Toggle } from "./controls";
  import { groupOf } from "./privacy.svelte";

  /** BrowserSpaceBrowsingSection, with the group's shared pins and Archive Now. */
  let { session, space, spaces }: { session: Session; space: SpaceState; spaces: readonly SpaceState[] } = $props();

  const preferences = $derived(space.settings.browsingPreferences);
  const catalog = $derived.by(() => (useCoreVersion(session), session.core.state.search));
  const providers = $derived(catalog?.providers ?? []);
  const chosen = $derived(preferences.followsDefaultSearch ? "default"
    : providers.find((provider) => (preferences.selectedCustomEngineId
      ? provider.customId === preferences.selectedCustomEngineId : provider.builtIn === preferences.selectedBuiltInEngine))?.name ?? "default");
  const suggestions = $derived(preferences.followsDefaultSuggestions ? "default" : preferences.searchSuggestionsEnabled ? "on" : "off");
  const defaultSuggestions = $derived(catalog?.catalog.suggestionsEnabled ? "On" : "Off");
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
  const group = $derived(groupOf(space, spaces));
</script>

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
{#if group.members.length > 1}
  <Group footer={space.settings.separatesPinnedTabs
    ? `Each Space of ${group.primary.settings.name}’s group shows its own pinned tabs.`
    : `Every Space of ${group.primary.settings.name}’s group shows ${group.primary.settings.name}’s pinned tabs.`}>
    <Toggle title="Separate Pinned Tabs" checked={space.settings.separatesPinnedTabs}
      onChange={(separates) => void send(session, SetSeparatePinnedTabs({ workspaceId: session.workspaceId, spaceId: space.id, separates }))} />
  </Group>
{/if}
