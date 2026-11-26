<script lang="ts">
  import { SetDefaultSearch } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { ProviderIcon } from "../../palette/CommandPalette";
  import { LevelSection } from "../../settings/AdBlockingPane";
  import { Group, Row } from "../../settings/controls";
  import DefaultBrowserGroup from "../../settings/DefaultBrowserGroup.svelte";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { useCoreVersion } from "../../use-core";

  /**
   * BrowserSetupHomePage: what makes Crest home, each choice taking effect at
   * once, as in Settings: the default browser, the search engine and the level
   * ad blocking blocks at.
   */
  let { session }: { session: Session } = $props();

  const searchId = $props.id();
  const catalog = $derived.by(() => (useCoreVersion(session), session.core.state.search));
  const lists = $derived.by(() => (useCoreVersion(session), session.core.state.filterLists));
  const choices = $derived(catalog?.providers.filter((provider) => provider.kind.canBeDefault) ?? []);
</script>

<div class="setup-page-content">
  <h2 class="setup-page-heading">Make It Home</h2>
  <DefaultBrowserGroup shell={session.shell} />
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
