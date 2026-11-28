<script lang="ts">
  import { BrowsingDataCategory, BrowsingDataRange, ClearHistory, DeleteBrowsingData, type SpaceState } from "@crest/contracts";

  import type { Session } from "../boot";
  import { Sheet } from "../shell/prompts/PromptSheet";
  import { deletion } from "../shell/site-control.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";
  import Confirmation from "./Confirmation.svelte";
  import { Button, Group, Picker, Row, Switch } from "./controls";
  import { ephemeral, listed, send } from "./space-privacy.svelte";

  /**
   * BrowserClearBrowsingDataSection: clearing what the Space browsed within a
   * time range, by category; the core clears its history, and every engine
   * what it keeps for the Space's profile. Other Spaces, passwords,
   * extensions, downloads and permissions stay.
   */
  let { session, space, didClear }: { session: Session; space: SpaceState; didClear: () => void } = $props();

  let range = $state.raw(BrowsingDataRange.lastHour);
  let categories = $state.raw<ReadonlySet<BrowsingDataCategory>>(new Set(BrowsingDataCategory.all));
  let confirming = $state(false);
  let clearing = $state(false);
  let outcome = $state<"cleared" | "failed" | null>(null);
  const chosen = $derived(BrowsingDataCategory.all.filter((category) => categories.has(category)));
  const clear = async () => {
    // It clears what was asked about, however the choices move meanwhile.
    const asked = { space, range, chosen };
    confirming = false;
    if (asked.chosen.length === 0 || clearing) return;
    clearing = true;
    let cleared = true;
    if (asked.chosen.some((category) => category.clearsHistory)) {
      cleared = await send(session, ClearHistory({ workspaceId: session.workspaceId, spaceId: asked.space.id, range: asked.range }));
    }
    const requestId = crypto.randomUUID();
    const erased = await session.core.send(DeleteBrowsingData({
      requestId, profileId: asked.space.profileId, ephemeral: ephemeral(session), range: asked.range, categories: asked.chosen,
    })).then(() => deletion(session.core, requestId), () => false);
    outcome = cleared && erased ? "cleared" : "failed";
    clearing = false;
    didClear();
  };
</script>

<Group title="Clear browsing data">
  <Picker title="Time range" value={range} choices={BrowsingDataRange.all.map((value) => ({ value, label: value.title }))}
    onChange={(value) => {
      range = value;
      outcome = null;
    }} />
  {#each BrowsingDataCategory.all as category (category.name)}
    <Row title={category.title} subtitle={category.detail ?? undefined}>
      <Switch label={category.title} checked={categories.has(category)} onChange={(on) => {
        const next = new Set(categories);
        if (on) next.add(category);
        else next.delete(category);
        categories = next;
        outcome = null;
      }} />
    </Row>
  {/each}
  <div class="settings-row settings-actions-row">
    <span class="settings-actions-status" style:opacity={outcome ? 1 : 0} aria-hidden={!outcome}>
      <SymbolIcon name={outcome === "failed" ? "exclamationmark.triangle" : "checkmark"} size={11} />{outcome === "failed" ? " Couldn’t clear everything" : " Cleared"}
    </span>
    <Button destructive disabled={chosen.length === 0 || clearing} onClick={() => (confirming = true)}>Clear…</Button>
  </div>
</Group>
<Confirmation question={confirming}>
  {#snippet children()}
    <Sheet title={`Clear browsing data in “${space.settings.name}”?`} primary="Clear" secondary="Cancel" warning destructive
      onPrimary={() => void clear()} onEscape={() => (confirming = false)}>
      <p class="sheet-message">{range.title}: {listed(chosen.map((category) => category.title))}. Other Spaces aren’t affected.</p>
    </Sheet>
  {/snippet}
</Confirmation>
