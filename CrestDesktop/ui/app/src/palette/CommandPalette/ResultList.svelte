<script lang="ts">
  import { untrack } from "svelte";

  import type { PaletteGroupView } from "../palette-model";
  import { type PaletteProps, usePaletteVersion } from "./palette-view";
  import Row from "./Row.svelte";

  /** The results: the overlay's keep one height, and the Start Page's grow with them up to the most. */
  let { model, bindings, tabs, size }: PaletteProps & {
    size: { readonly height: number } | { readonly maxHeight: number };
  } = $props();

  let list = $state<HTMLDivElement>();
  const groups = $derived.by(() => (usePaletteVersion(model), model.groups));
  const keyboardRevision = $derived.by(() => (usePaletteVersion(model), model.keyboardRevision));

  // Only the keyboard scrolls the list; hover never does.
  $effect(() => {
    void keyboardRevision;
    const element = list;
    untrack(() => {
      element?.querySelector(`[data-index="${model.selectedIndex}"]`)?.scrollIntoView({ block: "nearest" });
    });
  });
</script>

{#snippet rows(group: PaletteGroupView)}
  {#each group.items as item (item.id)}
    <Row {model} {item} section={group.section.name} {bindings} {tabs} />
  {/each}
{/snippet}

<div class="palette-results" bind:this={list} role="listbox"
  style:height={"height" in size ? `${size.height}px` : undefined}
  style:max-height={"maxHeight" in size ? `${size.maxHeight}px` : undefined}>
  {#each groups as group (group.section.name)}
    {#if group.items.length > 0}
      {#if group.section.title}
        <div class="palette-group">
          <div class="palette-group-title">{group.section.title}</div>
          {@render rows(group)}
        </div>
      {:else}
        {@render rows(group)}
      {/if}
    {/if}
  {/each}
</div>
