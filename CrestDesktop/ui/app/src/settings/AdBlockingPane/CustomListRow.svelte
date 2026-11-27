<script lang="ts">
  import { type CustomFilterListState, RemoveCustomFilterList, SetCustomFilterList } from "@crest/contracts";

  import type { Session } from "../../boot";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { send } from "./ad-blocking";

  let { session, state }: { session: Session; state: CustomFilterListState } = $props();

  const note = $derived(state.list.isOn && state.isTooLarge ? "Too large to use" : state.list.isOn && state.isFailing ? "Couldn’t update" : null);
</script>

<div class="settings-row">
  <div class="settings-row-text">
    <span class="settings-row-title settings-truncates">{state.title}</span>
    <span class="settings-row-subtitle settings-truncates-middle" title={state.list.url}>{state.list.url}</span>
    {#if note}<span class="settings-row-subtitle">{note}</span>{/if}
  </div>
  <div class="settings-row-control">
    <button type="button" role="switch" aria-checked={state.list.isOn} aria-label={state.title}
      class={["settings-switch", state.list.isOn && "on"]}
      onclick={() => void send(session, SetCustomFilterList({ id: state.list.id, isOn: !state.list.isOn }))}>
      <span class="settings-switch-knob"></span>
    </button>
    <button type="button" class="settings-icon-button" aria-label={`Remove ${state.title}`} title={`Remove ${state.title}`}
      onclick={() => void send(session, RemoveCustomFilterList({ id: state.list.id }))}>
      <SymbolIcon name="minus.circle" size={15} />
    </button>
  </div>
</div>
