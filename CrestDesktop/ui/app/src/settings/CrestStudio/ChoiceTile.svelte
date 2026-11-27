<script lang="ts">
  import type { Snippet } from "svelte";

  /** BrowserCrestStudioChoice: artwork in a 64 by 58 frame over a two-line title. */
  let { title, selected, onChoose, children }: {
    title: string;
    selected: boolean;
    onChoose: () => void;
    children?: Snippet;
  } = $props();
</script>

<button type="button" class={`forge-card forge-choice${selected ? " selected" : ""}`} aria-label={title} aria-pressed={selected}
  {title} onclick={onChoose}>
  <span class="forge-choice-art">{@render children?.()}</span>
  <span class="forge-choice-title">{title}</span>
</button>
