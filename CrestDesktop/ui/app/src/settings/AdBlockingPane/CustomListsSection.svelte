<script lang="ts">
  import { AddCustomFilterList, type FilterLists } from "@crest/contracts";
  import { CoreRejection } from "@crest/core-client";

  import type { Session } from "../../boot";
  import { Button, Group } from "../controls";
  import CustomListRow from "./CustomListRow.svelte";

  /**
   * BrowserCustomFilterListsSettingsSection: the lists the person subscribes
   * to by address, each with its own switch, which update on their own like
   * the catalog's, and the field that adds another.
   */
  let { session, lists }: { session: Session; lists: FilterLists } = $props();

  let address = $state("");
  let addError = $state<string | null>(null);
  const add = () => {
    const url = address.trim();
    if (!url) return;
    session.core.send(AddCustomFilterList({ id: crypto.randomUUID(), url })).then(() => {
      address = "";
      addError = null;
    }, (error: unknown) => {
      const rejection = error instanceof CoreRejection ? error.rejection : null;
      addError = rejection?.$kind === "CustomFilterListLimitReached"
        ? `You can add up to ${rejection.limit} lists.` : "Enter an https address.";
    });
  };
</script>

<Group title="Your Lists" footer="Subscribe to any list by its address. It updates with the built-in lists.">
  {#each lists.customLists as state (state.list.id)}
    <CustomListRow {session} {state} />
  {/each}
  <div class="settings-row">
    <span class="settings-text-field">
      <input bind:value={address} placeholder="https://example.com/list.txt" aria-label="Filter list address" spellcheck={false}
        autocapitalize="off" autocorrect="off" inputmode="url"
        onkeydown={(event) => {
          if (event.key === "Enter") add();
        }} />
    </span>
    <Button disabled={!address.trim()} onClick={add}>Add List</Button>
  </div>
  {#if addError}<div class="settings-row"><span class="settings-actions-status">{addError}</span></div>{/if}
</Group>
