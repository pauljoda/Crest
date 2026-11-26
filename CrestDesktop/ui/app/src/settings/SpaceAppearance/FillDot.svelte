<script lang="ts">
  import FillDefinition from "../../spaces/FillDefinition.svelte";
  import { fillPaint, type SpaceFill } from "../../spaces/space-fills";

  /** A circle filled with a color or a gradient, as the Mac blends one, with the stage's light inner ring or the brand's line where asked. */
  let { fill, size, ring = false, line = false }: { fill: SpaceFill; size: number; ring?: boolean; line?: boolean } = $props();

  const uid = $props.id();
  const id = `fill-dot-${uid}`;
  const painted = $derived(fillPaint(fill, id, { x: 0, y: 0, width: size, height: size }));
</script>

<svg class="fill-dot" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
  <defs>
    {#if painted.definition}<FillDefinition definition={painted.definition} />{/if}
  </defs>
  <circle cx={size / 2} cy={size / 2} r={size / 2} fill={painted.paint} />
  {#if ring}
    <circle cx={size / 2} cy={size / 2} r={size / 2 - 0.75} fill="none" stroke="rgb(255 255 255 / 0.35)" stroke-width={1.5} />
  {/if}
  {#if line}
    <circle class="fill-dot-line" cx={size / 2} cy={size / 2} r={size / 2 - 0.5} fill="none" stroke-width={1} />
  {/if}
</svg>
