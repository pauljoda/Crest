<script lang="ts">
  import { Group, Picker } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import SpacePrivacySections from "./privacy.svelte";

  /** BrowserSystemPrivacySettingsPane's Spaces: each Space's own privacy page. */
  /**
   * BrowserPrivacySettingsPane: a Space to look at, then what it keeps, the
   * choices it saved for sites, the sites that keep data in it, and clearing
   * what it browsed. Ad blocking holds for every Space, so it has a pane of
   * its own.
   */
  let { session, spaces, shownSpace }: PaneProps = $props();

  let picked = $state<string | null>(null);
  // A Space that left gives way to the one the window shows.
  const space = $derived(spaces.find((candidate) => candidate.id === picked) ?? shownSpace);
</script>

<Group>
  <Picker title="Space" value={space.id} choices={spaces.map((candidate) => ({ value: candidate.id, label: candidate.settings.name || "Untitled Space" }))}
    onChange={(id) => (picked = id)} />
</Group>
{#key space.id}
  <SpacePrivacySections {session} {space} {spaces} />
{/key}
