<script lang="ts">
  import { SetDefaultSearch } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { ProviderIcon } from "../../palette/CommandPalette";
  import { LevelSection } from "../../settings/AdBlockingPane";
  import { Group, Row } from "../../settings/controls";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { useCoreVersion } from "../../use-core";

  /**
   * BrowserSetupHomePage: what makes Crest home, each choice taking effect at
   * once, as in Settings: the search engine and the level ad blocking blocks
   * at. The Mac's Default browser row waits for Windows to register Crest as a
   * browser, which only an installer does.
   */
  let { session }: { session: Session } = $props();

  const searchId = $props.id();
  const catalog = $derived.by(() => (useCoreVersion(session), session.core.state.search));
  const lists = $derived.by(() => (useCoreVersion(session), session.core.state.filterLists));
  const choices = $derived(catalog?.providers.filter((provider) => provider.kind.canBeDefault) ?? []);
</script>

<div class="setup-page-content">
  <h2 class="setup-page-heading">Make It Home</h2>
  {#if catalog}
    <Group title="Search">
      <Row title="Search with" htmlFor={searchId}>
        <span class="setup-search-choice" data-testid="setup-default-search">
          <ProviderIcon provider={catalog.default} size={20} />
          <span class="settings-select">
            <select id={searchId} value={catalog.default.name}
              onchange={(event) => {
                const provider = choices.find((each) => each.name === event.currentTarget.value);
                if (provider) void session.core.send(SetDefaultSearch({ provider })).catch(() => undefined);
              }}>
              {#each choices as provider (provider.name)}
                <option value={provider.name}>{provider.title}</option>
              {/each}
            </select>
            <SymbolIcon name="chevron.up.chevron.down" size={11} class="settings-select-glyph" />
          </span>
        </span>
      </Row>
    </Group>
  {/if}
  {#if lists}
    <LevelSection {session} {lists} title="Ad Blocking" />
  {/if}
</div>
