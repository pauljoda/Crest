<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { symbolNames } from "../../symbols";

  /**
   * BrowserSystemSymbolPicker: a search over the symbols this interface
   * draws, every word a part of the name; in a popover with Done, or inline
   * in the Emblem step.
   */
  let { current, onChoose, onDone, inline = false }: {
    current: string;
    onChoose: (name: string) => void;
    onDone?: () => void;
    inline?: boolean;
  } = $props();

  let query = $state("");
  const words = $derived(query.toLowerCase().split(/[\s.]+/).filter(Boolean));
  const shown = $derived(symbolNames.filter((name) => words.every((word) => name.toLowerCase().includes(word))));
</script>

<div class={`symbol-picker${inline ? " inline" : ""}`}>
  {#if !inline}
    <div class="picker-header">
      <span class="picker-title">SF Symbols</span>
      <button type="button" class="symbol-picker-done" onclick={onDone}>Done</button>
    </div>
  {/if}
  <!-- svelte-ignore a11y_autofocus -->
  <input class={inline ? "settings-text-field symbol-picker-search" : "emoji-field"} placeholder="Search symbols" aria-label="Search symbols"
    bind:value={query} autofocus={!inline} />
  <div class="symbol-grid">
    {#each shown as name (name)}
      <button type="button" class={`forge-card symbol-choice${name === current ? " selected" : ""}`} title={name}
        aria-label={name} onclick={() => onChoose(name)}>
        <SymbolIcon {name} size={24} />
        <span>{name.replace(/\./g, " ")}</span>
      </button>
    {/each}
  </div>
  <span class="symbol-count">{shown.length} symbols</span>
</div>
