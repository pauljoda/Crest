<script lang="ts">
  import { Circle } from "@lucide/svelte";

  import { symbols } from "./symbols";

  /**
   * An SF Symbol by name, as the core's data names them: the icon mapped to
   * it, a glyph drawn to the symbol's own shape where an outline would read
   * as another symbol (the solid locks, and Site Controls' sliders with their
   * hollow knobs, each filling a square of the symbol's point size), or the
   * fallback for a name with no counterpart yet.
   */
  let {
    name,
    size = 16,
    class: className = undefined,
    strokeWidth = 1.75,
  }: {
    name: string | null | undefined;
    size?: number;
    class?: string;
    strokeWidth?: number;
  } = $props();

  const Icon = $derived((name && symbols[name]) || Circle);
</script>

{#if name === "lock.fill"}
  <svg width={size} height={size} viewBox="0 0 12 12" class={className} aria-hidden="true">
    <path d="M3.72 5V3.15a2.28 2.28 0 0 1 4.56 0V5" fill="none" stroke="currentColor" stroke-width="1.25" />
    <rect x="1.75" y="4.95" width="8.5" height="6.8" rx="1.25" fill="currentColor" />
  </svg>
{:else if name === "lock.open.fill"}
  <svg width={size} height={size} viewBox="0 0 12 12" class={className} aria-hidden="true">
    <path d="M6.95 5V3.15a2.28 2.28 0 0 1 4.56 0v1.1" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" />
    <rect x="0.5" y="4.95" width="8.5" height="6.8" rx="1.25" fill="currentColor" />
  </svg>
{:else if name === "slider.horizontal.3"}
  <svg width={size} height={size} viewBox="0 0 12 12" class={className} aria-hidden="true"
    fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round">
    <path d="M0.5 2.25H6M9.5 2.25H11.5M0.5 5.75H1.5M5 5.75H11.5M0.5 9.5H6M9.5 9.5H11.5" />
    <circle cx="7.75" cy="2.25" r="1.25" />
    <circle cx="3.25" cy="5.75" r="1.25" />
    <circle cx="7.75" cy="9.5" r="1.25" />
  </svg>
{:else}
  <Icon {size} {strokeWidth} class={className} aria-hidden="true" />
{/if}
