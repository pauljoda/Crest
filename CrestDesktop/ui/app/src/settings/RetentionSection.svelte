<script lang="ts" module>
  import { DataRetention as Retention, type DataRetentionPreferences } from "@crest/contracts";

  const retentionChoices = Retention.all.map((value) => ({ value, label: value.title }));

  /** BrowserDataRetentionCategory: each record a Space keeps for a while, and what its cleanup deletes. */
  const retentionCategories: readonly { readonly field: keyof DataRetentionPreferences; readonly title: string; readonly records: string }[] = [
    { field: "history", title: "History", records: "history entries" },
    { field: "archive", title: "Archived Tabs", records: "archived tabs" },
    { field: "downloads", title: "Download Records", records: "download records" },
  ];
</script>

<script lang="ts">
  import { type DataRetention, SetBrowsingPreferences, type SpaceState, SweepExpiredRecords } from "@crest/contracts";

  import type { Session } from "../boot";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import Confirmation from "./Confirmation.svelte";
  import { Group, Picker } from "./controls";
  import { send } from "./space-privacy.svelte";

  /** BrowserDataRetentionSettingsSection: how long the Space keeps each record, asking before a shorter time deletes some. */
  let { session, space }: { session: Session; space: SpaceState } = $props();

  const preferences = $derived(space.settings.browsingPreferences);
  const retention = $derived(preferences.dataRetention);
  let pending = $state.raw<{ readonly category: (typeof retentionCategories)[number]; readonly proposed: DataRetention } | null>(null);
  const apply = (field: keyof DataRetentionPreferences, proposed: DataRetention) => {
    pending = null;
    void send(session, SetBrowsingPreferences({
      workspaceId: session.workspaceId, spaceId: space.id, currentTabCleanup: preferences.currentTabCleanup,
      contentBlocking: preferences.contentBlocking, dataRetention: { ...retention, [field]: proposed },
    })).then((kept) => kept && send(session, SweepExpiredRecords({ workspaceId: session.workspaceId })));
  };
  // A shorter time deletes what is older at once, so it asks first.
  const shortens = (previous: DataRetention, proposed: DataRetention) => (proposed.lifetime ?? Infinity) < (previous.lifetime ?? Infinity);
</script>

<Group title="Keep" footer="Removing download records doesn’t delete the files.">
  {#each retentionCategories as category (category.field)}
    <Picker title={category.title} value={retention[category.field]} choices={retentionChoices}
      onChange={(proposed) => {
        if (proposed === retention[category.field]) return;
        if (shortens(retention[category.field], proposed)) pending = { category, proposed };
        else apply(category.field, proposed);
      }} />
  {/each}
</Group>
<Confirmation question={pending}>
  {#snippet children(asked)}
    <Sheet title="Permanently delete older records?" primary={`Use ${asked.proposed.title}`} secondary="Cancel" warning
      onPrimary={() => apply(asked.category.field, asked.proposed)} onEscape={() => (pending = null)}>
      <p class="sheet-message">
        This immediately and permanently deletes {asked.category.records} older than {asked.proposed.title.toLowerCase()} in this Space, including synced copies. Downloaded files stay on disk.
      </p>
    </Sheet>
  {/snippet}
</Confirmation>
