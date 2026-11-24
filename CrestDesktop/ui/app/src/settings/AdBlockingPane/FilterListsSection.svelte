<script lang="ts" module>
  /** When something happened, as the Mac's relative dates name it: "2 hours ago", "yesterday". */
  function relative(date: Date): string {
    const seconds = (date.getTime() - Date.now()) / 1000;
    const format = new Intl.RelativeTimeFormat(navigator.language, { numeric: "auto" });
    const units: readonly [Intl.RelativeTimeFormatUnit, number][] = [["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400], ["hour", 3600], ["minute", 60]];
    for (const [unit, length] of units) {
      if (Math.abs(seconds) >= length) return format.format(Math.round(seconds / length), unit);
    }
    return format.format(Math.round(seconds), "second");
  }
</script>

<script lang="ts">
  import { type FilterList, FilterListGroup, type FilterLists, RefreshFilterLists, SetFilterList } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { filterListUpdater } from "../../filter-lists";
  import { Button, Group, Row, Toggle } from "../controls";
  import { send } from "./ad-blocking";

  /**
   * BrowserFilterListsSettingsSection: the catalog's lists by group, each on
   * or off as the level set it unless the person turned it themselves, and
   * when they were last updated, with a way to update them now. Lists
   * download and update on their own.
   */
  let { session, lists }: { session: Session; lists: FilterLists } = $props();

  let updating = $state(false);
  // When the most recently updated list that is on was brought up to date.
  const lastUpdate = $derived.by(() => {
    const dates = [
      ...lists.lists.filter((state) => state.isOn).map((state) => state.updatedAt),
      ...lists.customLists.filter((state) => state.list.isOn).map((state) => state.updatedAt),
    ].filter((date): date is Date => date !== null);
    return dates.length > 0 ? new Date(Math.max(...dates.map((date) => date.getTime()))) : null;
  });
  // A minute's tick keeps "2 minutes ago" true while the pane stays open.
  let minutes = $state(0);
  $effect(() => {
    const timer = setInterval(() => minutes++, 60_000);
    return () => clearInterval(timer);
  });
  const updated = $derived.by(() => {
    void minutes;
    return updating ? "Updating…" : lastUpdate ? relative(lastUpdate) : "Not yet";
  });
  const updateNow = async () => {
    if (!(await send(session, RefreshFilterLists()))) return;
    updating = true;
    await filterListUpdater?.check();
    updating = false;
  };
  const turn = (list: FilterList, isOn: boolean) => void send(session, SetFilterList({ list, isOn }));
</script>

{#each FilterListGroup.all as group (group.name)}
  {@const rows = lists.lists.filter((state) => state.list.group === group)}
  {#if rows.length > 0}
    <Group title={group.title}>
      {#each rows as state (state.list.name)}
        <Toggle title={state.list.title} checked={state.isOn} onChange={(isOn) => turn(state.list, isOn)}
          subtitle={state.isOn && state.isFailing ? "Couldn’t update" : undefined} />
      {/each}
    </Group>
  {/if}
{/each}
<Group>
  <Row title="Updated">
    <span class="settings-secondary-text">{updated}</span>
    <Button disabled={updating} onClick={() => void updateNow()}>Update Now</Button>
  </Row>
</Group>
