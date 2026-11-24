<script lang="ts">
  import { AnswerPermission, type PermissionAsked } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import type { Session } from "../../boot";
  import { presence } from "../../motion";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { originName } from "./prompt-text";

  /**
   * A site's request for a permission its Space's choices don't answer, below
   * the address field, as the Mac shows it from its site control. Allow and
   * Deny take the Space's "Remember" choice; dismissing it answers this once
   * and never saves a denial.
   */
  let { session, asked, spaceName }: {
    session: Session;
    asked: PermissionAsked | null;
    spaceName: string;
  } = $props();

  let answered = $state<string | null>(null);
  let remembers = $state(true);
  const promptId = $derived(asked?.promptId);
  $effect(() => {
    void promptId;
    remembers = true;
  });
  const shown = $derived(asked && asked.promptId !== answered ? asked : null);
  const answer = (grants: boolean, remembered: boolean) => {
    if (!shown) return;
    answered = shown.promptId;
    void session.core.send(AnswerPermission({ promptId: shown.promptId, grants, remembers: remembered })).catch(() => undefined);
  };
</script>

{#each shown ? [shown] : [] as prompt (prompt.promptId)}
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    class="permission-prompt"
    role="dialog"
    aria-label="{originName(prompt.question.origin)} {prompt.question.permission.requestTitle}"
    in:presence|global={{ pose: { opacity: 0, y: -6, scale: 0.97 }, timing: tokens.floatingPane }}
    out:presence={{ pose: { opacity: 0, y: -4, scale: 0.98 }, timing: tokens.floatingPane }}
    onkeydown={(event) => event.key === "Escape" && answer(false, false)}
  >
    <div class="permission-heading">
      <SymbolIcon name={prompt.question.permission.symbol} size={20} class="permission-symbol" />
      <div class="permission-text">
        <span class="permission-origin">{originName(prompt.question.origin)}</span>
        <span class="permission-request">{prompt.question.permission.requestTitle}</span>
        {#if originName(prompt.question.origin) !== originName(prompt.question.topLevelOrigin)}
          <span class="permission-inside">Inside {originName(prompt.question.topLevelOrigin)}</span>
        {/if}
      </div>
      <button class="permission-dismiss" aria-label="Dismiss Permission Request" title="Dismiss"
        onclick={() => answer(false, false)}>
        <SymbolIcon name="xmark" size={13} />
      </button>
    </div>
    <label class="permission-remember">
      <input type="checkbox" bind:checked={remembers} />
      Remember in {spaceName}
    </label>
    <div class="permission-actions">
      <!-- Nothing is focused, so a key meant for the page never grants. -->
      <button class="permission-button primary" onclick={() => answer(true, remembers)}>Allow</button>
      <button class="permission-button" onclick={() => answer(false, remembers)}>Deny</button>
    </div>
  </div>
{/each}
