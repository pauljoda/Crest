<script lang="ts">
  import {
    ClearPaletteChoices,
    PaletteLayout,
    SearchProviderSpaceTrigger,
    SetDefaultSearch,
    SetPrivateSearch,
    SetSearchSuggestions,
  } from "@crest/contracts";

  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import { Button, Group, Picker, Row, Segmented, Toggle } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { appPreferences, defaults, send, setAppPreferences } from "./preferences.svelte";

  /** BrowserSearchSettingsPane: the default search, the palette's results and sections, and its typing. */
  let { session }: PaneProps = $props();

  const catalog = $derived((useCoreVersion(session), session.core.state.search));
  const palette = $derived(appPreferences(session).palette);
  // Each change reads the palette it changes, which holds an earlier change the core hasn't answered yet.
  type Palette = typeof palette;
  const setPalette = (change: Partial<Palette> | ((current: Palette) => Partial<Palette>)) =>
    setAppPreferences(session, (current) => ({
      palette: { ...current.palette, ...(typeof change === "function" ? change(current.palette) : change) },
    }));
  let confirmingClear = $state(false);
  const providers = $derived(catalog?.providers ?? []);
  const providerChoice = $derived(providers.map((provider) => ({ value: provider.name, label: provider.title })));
  const byName = (name: string) => providers.find((provider) => provider.name === name);
  const sources = $derived(palette.sources.filter((choice) => choice.source.isSection));
  const extras = $derived(palette.sources.filter((choice) => !choice.source.isSection
    && ["settingsPages", "scopes", "calculator"].includes(choice.source.name)));
  const setSource = (name: string, change: { isEnabled?: boolean; limit?: number | null }) =>
    setPalette((current) => ({
      sources: current.sources.map((choice) => (choice.source.name === name ? { ...choice, ...change } : choice)),
    }));
  const move = (index: number, by: number) => {
    const moving = sources[index]?.source.name;
    const other = sources[index + by]?.source.name;
    if (!moving || !other) return;
    setPalette((current) => {
      const order = [...current.sources];
      const from = order.findIndex((choice) => choice.source.name === moving);
      const to = order.findIndex((choice) => choice.source.name === other);
      if (from < 0 || to < 0) return {};
      [order[from], order[to]] = [order[to], order[from]];
      return { sources: order };
    });
  };
  const defaultOrder = defaults.palette.sources.map((choice) => choice.source.name).join();
  const limits = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20];
</script>

{#snippet switchFor(label: string, checked: boolean, onChange: (checked: boolean) => void)}
  <button type="button" role="switch" aria-checked={checked} aria-label={label} class={["settings-switch", checked && "on"]}
    onclick={() => onChange(!checked)}>
    <span class="settings-switch-knob"></span>
  </button>
{/snippet}

<Group title="Search" footer="Each device keeps its own default search. Search suggestions send what you type to the search engine.">
  {#if catalog}
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
  {/if}
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
  {#each sources as choice, index (choice.source.name)}
    <Row title={choice.source.title}>
      <span class="settings-order">
        <button type="button" aria-label="Move Up" disabled={index === 0} onclick={() => move(index, -1)}><SymbolIcon name="chevron.up" size={11} /></button>
        <button type="button" aria-label="Move Down" disabled={index === sources.length - 1} onclick={() => move(index, 1)}><SymbolIcon name="chevron.down" size={11} /></button>
      </span>
      <span class="settings-select compact">
        <select aria-label={`${choice.source.title} limit`} value={choice.limit ?? choice.source.defaultLimit}
          onchange={(event) => {
            setSource(choice.source.name, { limit: Number(event.currentTarget.value) });
            // The menu shows the limit it is given, until the palette's choices hold another.
            event.currentTarget.value = String(choice.limit ?? choice.source.defaultLimit);
          }}>
          {#each limits as limit (limit)}
            <option value={limit}>Up to {limit}</option>
          {/each}
        </select>
        <SymbolIcon name="chevron.up.chevron.down" size={11} class="settings-select-glyph" />
      </span>
      {@render switchFor(choice.source.title, choice.isEnabled, (isEnabled) => setSource(choice.source.name, { isEnabled }))}
    </Row>
  {/each}
</Group>
<Group title="Also show">
  {#each extras as choice (choice.source.name)}
    <Toggle title={choice.source.title} subtitle={choice.source.detail ?? undefined}
      checked={choice.isEnabled} defaultValue={choice.source.isEnabledByDefault}
      onChange={(isEnabled) => setSource(choice.source.name, { isEnabled })} />
  {/each}
</Group>
<Group title="Typing" footer="Learned choices stay on this device.">
  <Toggle title="Complete addresses inline" checked={palette.completesInline} defaultValue={defaults.palette.completesInline}
    onChange={(completesInline) => setPalette({ completesInline })} />
  <Toggle title="Learn from my choices" checked={palette.learnsChoices} defaultValue={defaults.palette.learnsChoices}
    onChange={(learnsChoices) => setPalette({ learnsChoices })} />
  <Row title={confirmingClear ? "The palette forgets which results you chose for what you typed." : "Learned choices"}>
    {#if confirmingClear}
      <Button onClick={() => (confirmingClear = false)}>Cancel</Button>
      <Button destructive onClick={() => {
        send(session, ClearPaletteChoices());
        confirmingClear = false;
      }}>Clear Learned Choices</Button>
    {:else}
      <Button destructive onClick={() => (confirmingClear = true)}>Clear Learned Choices…</Button>
    {/if}
  </Row>
</Group>
