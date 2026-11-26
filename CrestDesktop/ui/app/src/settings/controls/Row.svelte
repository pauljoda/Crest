<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import type { Snippet } from "svelte";

  import { presence } from "../../motion";
  import SymbolIcon from "../../SymbolIcon.svelte";

  /**
   * CrestSettingRow: the title, and the subtitle under it, on the left, and
   * the control on the right; a row that changed from how it ships offers to
   * go back, beside its title and in its menu.
   */
  let { title, subtitle, onReset, children, htmlFor }: {
    title: string | Snippet;
    subtitle?: string | Snippet;
    onReset?: (() => void) | null;
    children?: Snippet;
    /** The control the title labels. */
    htmlFor?: string;
  } = $props();
</script>

{#snippet text(content: string | Snippet)}
  {#if typeof content === "string"}{content}{:else}{@render content()}{/if}
{/snippet}

<div class="settings-row">
  <div class="settings-row-text">
    <span class="settings-row-title">
      {#if htmlFor}<label for={htmlFor}>{@render text(title)}</label>{:else}{@render text(title)}{/if}
      {#if onReset}
        <button type="button" class="settings-row-reset" aria-label="Reset to Default" title="Reset to Default" onclick={onReset}
          in:presence|global={{ pose: { opacity: 0 }, timing: tokens.surface }}
          out:presence={{ pose: { opacity: 0 }, timing: tokens.surface }}>
          <SymbolIcon name="arrow.counterclockwise" size={10} strokeWidth={2.75} />
        </button>
      {/if}
    </span>
    {#if subtitle}<span class="settings-row-subtitle">{@render text(subtitle)}</span>{/if}
  </div>
  {#if children}<div class="settings-row-control">{@render children()}</div>{/if}
</div>
