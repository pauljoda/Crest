<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import type { Snippet } from "svelte";

  import { presence } from "../../motion";

  /**
   * The Mac's CrestSettingsGroup in a grouped form: a section's title, with a
   * quiet Reset that fades in once something in it changed, its rows on one
   * card, and its footnote beneath.
   */
  let { title, footer, onReset, children }: {
    title?: string;
    footer?: string | Snippet;
    /** Puts the group's rows back as they ship, offered while any of them changed. */
    onReset?: (() => void) | null;
    children?: Snippet;
  } = $props();

  const id = $props.id();
</script>

<section class="settings-group" aria-labelledby={title ? id : undefined}>
  {#if title || onReset !== undefined}
    <div class="settings-group-header">
      {#if title}<h3 {id}>{title}</h3>{/if}
      {#if onReset}
        <button type="button" class="settings-group-reset" onclick={onReset}
          in:presence|global={{ pose: { opacity: 0 }, timing: tokens.surface }}
          out:presence={{ pose: { opacity: 0 }, timing: tokens.surface }}>
          Reset
        </button>
      {/if}
    </div>
  {/if}
  <div class="settings-card">{@render children?.()}</div>
  {#if footer}
    <p class="settings-footer">{#if typeof footer === "string"}{footer}{:else}{@render footer()}{/if}</p>
  {/if}
</section>
