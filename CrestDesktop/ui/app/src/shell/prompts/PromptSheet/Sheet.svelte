<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import { type Snippet, untrack } from "svelte";

  import { presence } from "../../../motion";

  /**
   * A dialog as the Mac's alert sheet draws one: its question above, its
   * buttons below, the second before the primary one, as Cancel stands
   * before OK. Enter answers with the primary button, and Escape as
   * `onEscape` says, which is the second button unless that would go ahead
   * with something the person should choose.
   *
   * It comes in as it is drawn and goes with the block that holds it, so a
   * view puts it straight in the block that shows it, as a backdrop's.
   */
  let { title, primary, secondary, warning = false, destructive = false, onPrimary, onSecondary, onEscape, children }: {
    title: string;
    primary: string;
    secondary?: string;
    warning?: boolean;
    /** The primary button deletes or clears, which the Mac's alert draws in red on a tint of it. */
    destructive?: boolean;
    onPrimary: () => void;
    onSecondary?: () => void;
    onEscape: () => void;
    children?: Snippet;
  } = $props();

  let form: HTMLFormElement;
  // A question whose title or message wraps reads from the leading edge, as
  // the Mac's alert lays out a longer one (I05, I06); a short one is centred (I02).
  let body: HTMLDivElement;
  let wraps = $state(false);
  $effect(() => {
    const element = body;
    const lines = (line: Element | null | undefined) => {
      if (!line) return 0;
      const height = parseFloat(getComputedStyle(line).lineHeight) || 16;
      return Math.round(line.getBoundingClientRect().height / height);
    };
    // Measured again whenever what it holds changes size, as its title or message does.
    const observer = new ResizeObserver(() => {
      wraps = lines(element.querySelector(".sheet-title")) > 1 || lines(element.querySelector(".sheet-message")) > 1;
    });
    observer.observe(element);
    return () => observer.disconnect();
  });
  $effect(() => {
    untrack(() => {
      // The page held the keyboard; the question takes it, its answer's
      // default text selected, as the Mac's field has it.
      const target = form.querySelector<HTMLElement>("[data-autofocus]")
        ?? form.querySelector<HTMLElement>("button[type=submit]");
      target?.focus();
      if (target instanceof HTMLInputElement) target.select();
    });
  });
  const second = () => (onSecondary ?? onEscape)();
  const submit = (event: SubmitEvent) => {
    event.preventDefault();
    onPrimary();
  };
  const escape = (event: KeyboardEvent) => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    onEscape();
  };
</script>

<div
  class={["sheet", warning && "warning", wraps && "wraps"]}
  role="alertdialog"
  aria-modal="true"
  aria-label={title}
  in:presence|global={{ pose: { opacity: 0, scale: 1.04 }, timing: tokens.floatingPane }}
  out:presence={{ pose: { opacity: 0, scale: 0.98 }, timing: tokens.floatingPane }}
>
  <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
  <form bind:this={form} onsubmit={submit} onkeydown={escape}>
    <div bind:this={body} class="sheet-body">
      <h2 class="sheet-title">{title}</h2>
      {@render children?.()}
    </div>
    <div class="sheet-actions">
      {#if secondary}<button type="button" class="sheet-button" onclick={second}>{secondary}</button>{/if}
      <button type="submit" class={["sheet-button primary", destructive && "destructive"]}>{primary}</button>
    </div>
  </form>
</div>
