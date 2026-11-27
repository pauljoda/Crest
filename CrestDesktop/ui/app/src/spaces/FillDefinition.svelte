<svelte:options namespace="svg" />

<script lang="ts">
  import type { FillDefinition } from "./space-fills";

  /** The SVG definition a gradient fill's paint names (`fillPaint`), drawn inside an SVG's `<defs>`. */
  let { definition }: { definition: FillDefinition } = $props();
</script>

{#if definition.kind === "angular"}
  {@const box = definition.box}
  <pattern id={definition.id} patternUnits="userSpaceOnUse" x={box.x} y={box.y} width={box.width} height={box.height}>
    <g transform={`translate(${-box.x} ${-box.y})`}>
      {#each definition.wedges as wedge, index (index)}
        <polygon points={wedge.points} fill={wedge.fill} />
      {/each}
    </g>
  </pattern>
{:else if definition.kind === "radial"}
  <radialGradient id={definition.id} gradientUnits="userSpaceOnUse" cx={definition.cx} cy={definition.cy} r={definition.r}
    gradientTransform={definition.transform}>
    {#each definition.stops as stop, index (index)}
      <stop offset={stop.offset} stop-color={stop.color} />
    {/each}
  </radialGradient>
{:else}
  <linearGradient id={definition.id} gradientUnits="userSpaceOnUse" x1={definition.x1} y1={definition.y1} x2={definition.x2}
    y2={definition.y2}>
    {#each definition.stops as stop, index (index)}
      <stop offset={stop.offset} stop-color={stop.color} />
    {/each}
  </linearGradient>
{/if}
