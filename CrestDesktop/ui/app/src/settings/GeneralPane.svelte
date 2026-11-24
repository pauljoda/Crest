<script lang="ts">
  import { SetDefaultSpace, StartupBehavior } from "@crest/contracts";

  import { useCoreVersion } from "../use-core";
  import { Group, Picker } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { appPreferences, defaults, send, setAppPreferences } from "./preferences.svelte";

  /** BrowserGeneralSettingsPane, as Windows offers it: how Crest opens, and the Space it opens in. */
  let { session, spaces }: PaneProps = $props();

  const preferences = $derived(appPreferences(session));
  const defaultSpaceId = $derived((useCoreVersion(session),
    session.core.state.workspaces.get(session.workspaceId)?.defaultSpaceId ?? spaces[0]?.id ?? ""));
</script>

<Group title="Startup">
  <Picker title="When Crest opens" value={preferences.startup} defaultValue={defaults.startup}
    choices={[StartupBehavior.lastActiveTab, StartupBehavior.showStartPage].map((value) => ({ value, label: value.title }))}
    onChange={(startup) => setAppPreferences(session, { startup })} />
  <Picker title="Default Space" value={defaultSpaceId}
    choices={spaces.map((space) => ({ value: space.id, label: space.settings.name || "Untitled Space" }))}
    onChange={(spaceId) => send(session, SetDefaultSpace({ workspaceId: session.workspaceId, spaceId }))} />
</Group>
