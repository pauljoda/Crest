<script lang="ts">
  import type { Snippet } from "svelte";

  /** A bordered push button in a row or beneath a group. */
  let { children, onClick, destructive, disabled }: {
    children?: Snippet;
    onClick: () => void;
    destructive?: boolean;
    disabled?: boolean;
  } = $props();
</script>

<button type="button" class={["settings-button", destructive && "destructive"]} {disabled} onclick={onClick}>
  {@render children?.()}
</button>
