<script lang="ts">
  import { JavaScriptDialogKind, type ScriptDialogAsked } from "@crest/contracts";
  import { untrack } from "svelte";

  import { sourceLabel } from "../prompt-text";
  import Sheet from "./Sheet.svelte";

  let { asked, answer }: { asked: ScriptDialogAsked; answer: (accepted: boolean, text: string | null) => void } = $props();

  const kind = $derived(asked.question.kind);
  const message = $derived(asked.question.message);
  let text = $state(untrack(() => asked.question.defaultText));
  const source = $derived(sourceLabel(asked.question.sourceUrl));
  // One sheet for each kind of question, drawn as one so it comes and goes with its backdrop.
  const sheet = $derived.by(() => {
    switch (kind) {
      case JavaScriptDialogKind.Alert:
        return {
          title: `${source} says`, primary: "OK", secondary: undefined,
          accept: () => answer(true, null), escape: () => answer(true, null),
        };
      case JavaScriptDialogKind.Confirm:
        return {
          title: `${source} says`, primary: "OK", secondary: "Cancel",
          accept: () => answer(true, null), escape: () => answer(false, null),
        };
      case JavaScriptDialogKind.Prompt:
        return {
          title: `${source} says`, primary: "OK", secondary: "Cancel",
          accept: () => answer(true, text), escape: () => answer(false, null),
        };
      case JavaScriptDialogKind.BeforeUnload:
        // Pages no longer choose this question's wording, so it names the site
        // rather than repeating the page's text.
        return {
          title: "Leave this page?", primary: "Leave Page", secondary: "Stay on Page",
          accept: () => answer(true, null), escape: () => answer(false, null),
        };
    }
  });
</script>

<Sheet title={sheet.title} primary={sheet.primary} secondary={sheet.secondary} onPrimary={sheet.accept} onEscape={sheet.escape}>
  {#if kind === JavaScriptDialogKind.BeforeUnload}
    <p class="sheet-message">Changes you made on {source} may not be saved.</p>
  {:else}
    <p class="sheet-message">{message}</p>
    {#if kind === JavaScriptDialogKind.Prompt}
      <input class="sheet-field" bind:value={text} aria-label={message || "Answer"} data-autofocus />
    {/if}
  {/if}
</Sheet>
