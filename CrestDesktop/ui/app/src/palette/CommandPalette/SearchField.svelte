<script lang="ts">
  import type { PaletteScope, SearchProvider } from "@crest/contracts";
  import { untrack } from "svelte";

  import SymbolIcon from "../../SymbolIcon.svelte";
  import { type PaletteModel, providerActionTitle } from "../palette-model";
  import { brandColor, usePaletteVersion } from "./palette-view";
  import ProviderIcon from "./ProviderIcon.svelte";

  let { model, embedded, takesFocus = true }: { model: PaletteModel; embedded: boolean; takesFocus?: boolean } = $props();

  let input = $state<HTMLInputElement>();
  let composing = false;
  const report = () => {
    const field = input;
    if (!field) return;
    model.updateEditing(field.value, field.selectionStart ?? 0, field.selectionEnd ?? 0, composing);
  };

  $effect(() => {
    const field = input;
    const bound = model;
    if (!field) return;
    untrack(() => {
      bound.field = {
        applyCompletion(text, start, end) {
          field.setRangeText(text, start, end, "end");
          report();
        },
        replaceText(text) {
          field.value = text;
          field.setSelectionRange(text.length, text.length);
          report();
        },
      };
      field.value = bound.query;
      // The palette opens with what it holds selected, as the Mac's field does.
      if (takesFocus) {
        field.focus();
        field.select();
      }
      report();
    });
    // The field binds once for the palette it opened with.
    return () => {
      bound.field = null;
    };
  });

  // A palette kept while its card was only shown still takes the keyboard
  // once its card becomes the one in use.
  let tookFocus = untrack(() => takesFocus);
  $effect(() => {
    const takes = takesFocus;
    untrack(() => {
      if (takes && !tookFocus) input?.focus();
      tookFocus = takes;
    });
  });

  // React's onSelect: the field's caret or selection moved, by the keyboard,
  // the pointer or the field's own selecting.
  let lastSelection: readonly [number, number] | null = null;
  const selectionMoved = () => {
    const field = input;
    if (!field || document.activeElement !== field) return;
    const start = field.selectionStart ?? 0;
    const end = field.selectionEnd ?? 0;
    if (lastSelection && lastSelection[0] === start && lastSelection[1] === end) return;
    lastSelection = [start, end];
    report();
  };
  $effect(() => {
    document.addEventListener("selectionchange", selectionMoved);
    return () => document.removeEventListener("selectionchange", selectionMoved);
  });

  const held = (event: KeyboardEvent) => model.setHeld({ control: event.ctrlKey, shift: event.shiftKey, alt: event.altKey });

  const onKeyDown = (event: KeyboardEvent & { currentTarget: HTMLInputElement }) => {
    held(event);
    if (composing || event.isComposing) return;
    const field = event.currentTarget;
    const handled = (() => {
      switch (event.key) {
        case "Tab":
          if (event.shiftKey) model.moveSelection(-1);
          else model.pressTab();
          return true;
        case "ArrowRight":
        case "End":
          return model.acceptCompletion();
        case "ArrowDown":
          if (event.altKey) model.moveSection(1);
          else model.pressDown();
          return true;
        case "ArrowUp":
          if (event.altKey) model.moveSection(-1);
          else model.moveSelection(-1);
          return true;
        case "Enter":
          model.pressReturn();
          return true;
        case "Delete":
        case "Backspace":
          if (event.shiftKey && model.forgetSelectedRow()) return true;
          return event.key === "Backspace" && field.value === "" && field.selectionStart === 0 && model.leaveScope();
        case "Escape":
          if (model.leaveScope()) return true;
          if (model.urlCompletion) {
            model.rejectCompletion();
            return true;
          }
          // The Start Page's palette stays where it is.
          if (embedded) return false;
          model.host.dismiss();
          return true;
        default:
          return false;
      }
    })();
    if (handled) event.preventDefault();
  };

  const completion = $derived.by(() => (usePaletteVersion(model), model.urlCompletion));
  const provider = $derived.by(() => (usePaletteVersion(model), model.activeProvider));
  const scope = $derived.by(() => (usePaletteVersion(model), model.activeScope));
  const placeholder = $derived(provider ? `${providerActionTitle(provider)}…` : scope ? `Search ${scope.title}…` : "Search or Enter URL…");
  const providerOffer = $derived.by(() => (usePaletteVersion(model), model.providerOffer));
  const scopeOffer = $derived.by(() => (usePaletteVersion(model), model.scopeOffer));

  /**
   * The rest of the address the core completes, after the caret, in the
   * field's own font: never part of what is typed until Tab or Right Arrow
   * accepts it. It shimmers now and then, as the Mac's does.
   */
  let mirror = $state<HTMLSpanElement>();
  let left = $state(0);
  $effect(() => {
    usePaletteVersion(model);
    const field = input;
    const shadow = mirror;
    if (!field || !shadow) return;
    untrack(() => {
      shadow.textContent = field.value;
      left = shadow.offsetWidth - field.scrollLeft;
    });
  });
</script>

{#snippet tabHint()}
  <span class="palette-tab-hint">
    <SymbolIcon name="arrow.right.to.line" size={11} />Tab
  </span>
{/snippet}

{#snippet providerPill(provider: SearchProvider, onClose?: () => void)}
  <span class="palette-chip" style:--chip-tint={brandColor(provider.color)}>
    <ProviderIcon {provider} />
    <span class="palette-chip-title">{provider.title}</span>
    {#if onClose}
      <button type="button" class="palette-chip-close" onclick={onClose}
        title="Stop searching {provider.title}" aria-label="Stop searching {provider.title}">
        <SymbolIcon name="xmark" size={10} />
      </button>
    {/if}
  </span>
{/snippet}

{#snippet scopeChip(scope: PaletteScope, onClose?: () => void)}
  <span class="palette-chip accent">
    <SymbolIcon name={scope.symbol} size={11} />
    <span class="palette-chip-title">{scope.title}</span>
    {#if onClose}
      <button type="button" class="palette-chip-close" onclick={onClose} title="Show all results"
        aria-label="Stop searching {scope.title}">
        <SymbolIcon name="xmark" size={10} />
      </button>
    {/if}
  </span>
{/snippet}

<!-- What Tab does next: enter the offered provider, accept the completion, or enter the offered scope. -->
{#snippet offer()}
  {#if providerOffer}
    <span class="palette-offer" title="Press Tab to {providerActionTitle(providerOffer)}">
      {@render providerPill(providerOffer)}
      {@render tabHint()}
    </span>
  {:else if completion}
    <button type="button" class="palette-offer" title="Accept URL completion (Tab or Right Arrow)"
      aria-label="Accept URL completion" onmousedown={(event) => event.preventDefault()}
      onclick={() => model.acceptCompletion()}>
      {@render tabHint()}
    </button>
  {:else if scopeOffer}
    <span class="palette-offer" aria-label="Search {scopeOffer.title}">
      {@render scopeChip(scopeOffer)}
      {@render tabHint()}
    </span>
  {/if}
{/snippet}

<div class="palette-field">
  <SymbolIcon name="magnifyingglass" size={19} class="palette-glyph" />
  {#if provider}
    {@render providerPill(provider, () => model.leaveScope())}
  {/if}
  {#if scope}
    {@render scopeChip(scope, () => model.leaveScope())}
  {/if}
  <div class="palette-input">
    <input
      bind:this={input}
      aria-label="Command Palette"
      {placeholder}
      spellcheck={false}
      autocomplete="off"
      oninput={report}
      onselect={selectionMoved}
      onkeydown={(event) => {
        onKeyDown(event);
        selectionMoved();
      }}
      onkeyup={(event) => {
        held(event);
        selectionMoved();
      }}
      onmouseup={selectionMoved}
      onfocusin={() => {
        lastSelection = null;
      }}
      onfocusout={() => {
        // The field loses focus as the palette closes too, when the model may already be gone.
        (model as PaletteModel | null)?.setHeld({ control: false, shift: false, alt: false });
      }}
      oncompositionstart={() => {
        composing = true;
        report();
      }}
      oncompositionend={() => {
        composing = false;
        report();
      }}
    />
    {#if completion}
      <span bind:this={mirror} class="palette-mirror" aria-hidden="true"></span>
      {#key completion.suffix}
        <span class="palette-suffix" style:left="{left}px" aria-hidden="true">{completion.suffix}</span>
      {/key}
    {/if}
  </div>
  {@render offer()}
  {#if !embedded}
    <button type="button" class="palette-close" title="Close" aria-label="Close" onclick={() => model.host.dismiss()}>
      <SymbolIcon name="xmark" size={14} />
    </button>
  {/if}
</div>
