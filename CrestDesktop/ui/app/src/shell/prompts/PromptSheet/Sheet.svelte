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
    const lines = (line: Element) => {
      const height = parseFloat(getComputedStyle(line).lineHeight) || 16;
      return Math.round(line.getBoundingClientRect().height / height);
    };
    // Measured again whenever what it holds changes size, as its title or message does.
    const observer = new ResizeObserver(() => {
      wraps = [...element.querySelectorAll(".sheet-title, .sheet-message")].some((line) => lines(line) > 1);
    });
    observer.observe(element);
    return () => observer.disconnect();
  });
  $effect(() => {
    return untrack(() => {
      // The page held the keyboard; the question takes it, its answer's
      // default text selected, as the Mac's field has it, and gives it back
      // once answered unless something else has taken it since.
      const previous = document.activeElement;
      const target = form.querySelector<HTMLElement>("[data-autofocus]")
        ?? form.querySelector<HTMLElement>("button[type=submit]");
      target?.focus();
      if (target instanceof HTMLInputElement) target.select();
      return () => {
        const active = document.activeElement;
        if (active && active !== document.body && !form.contains(active)) return;
        if (previous instanceof HTMLElement && previous.isConnected) previous.focus();
      };
    });
  });
  const second = () => (onSecondary ?? onEscape)();
  const submit = (event: SubmitEvent) => {
    event.preventDefault();
    onPrimary();
  };
  // Escape answers as `onEscape` says, and Tab goes round the sheet's own
  // controls, as a modal sheet keeps the keyboard until it is answered.
  const keys = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      onEscape();
      return;
    }
    if (event.key !== "Tab") return;
    const controls = [...form.querySelectorAll<HTMLElement>("input, textarea, select, button, [tabindex]:not([tabindex='-1'])")]
      .filter((control) => !control.matches(":disabled") && control.getClientRects().length > 0);
    if (controls.length === 0) return;
    const first = controls[0];
    const last = controls[controls.length - 1];
    const at = document.activeElement;
    if (event.shiftKey ? at === first || !form.contains(at) : at === last || !form.contains(at)) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    }
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
  <form bind:this={form} onsubmit={submit} onkeydown={keys}>
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
