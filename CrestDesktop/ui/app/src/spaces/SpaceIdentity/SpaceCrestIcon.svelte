<script lang="ts">
  import type { SpaceBranding } from "@crest/contracts";

  import SymbolIcon from "../../SymbolIcon.svelte";
  import FillDefinition from "../FillDefinition.svelte";
  import { crestDrawing, type PathShape } from "./crest-drawing";

  /**
   * BrowserSpaceCrestIcon: plate, field, band, edge, trim and charge, composed
   * from paths and colored from the crest's own tinctures or the Space's.
   */
  let { branding, size }: { branding: SpaceBranding; size: number } = $props();

  const id = $props.id();
  const drawing = $derived(crestDrawing(branding, size, id));
  const crest = $derived(branding.crest);
</script>

<svg class="space-crest" width={size} height={size} viewBox={`0 0 ${size} ${size}`} style:filter={drawing.depth} style:overflow="visible"
  aria-hidden="true">
  {#snippet shape(path: PathShape)}
    <path d={path.d} fill={path.fill} stroke={path.stroke} stroke-width={path.strokeWidth} stroke-linecap={path.strokeLinecap}
      stroke-linejoin={path.strokeLinejoin} stroke-miterlimit={path.strokeMiterlimit?.toString()} />
  {/snippet}
  {#if drawing.definitions.length > 0}
    <defs>
      {#each drawing.definitions as definition (definition.id)}
        <FillDefinition {definition} />
      {/each}
    </defs>
  {/if}
  {#if drawing.hasPlate}
    {@const plate = drawing.plate}
    <defs>
      <clipPath id={drawing.clip}><path d={drawing.plateD} /></clipPath>
    </defs>
    <g clip-path={`url(#${drawing.clip})`}>
      <rect x={plate.x} y={plate.y} width={plate.width} height={plate.height} fill={drawing.layers.backplate} />
      <path d={drawing.division} fill={drawing.layers.secondary} />
      {#if drawing.finish}
        {@const finish = drawing.finish}
        <defs>
          <linearGradient id={finish.id} gradientUnits="userSpaceOnUse" x1={finish.start.x} y1={finish.start.y} x2={finish.end.x}
            y2={finish.end.y}>
            {#each finish.stops as [color, opacity, offset] (offset)}
              <stop {offset} stop-color={color} stop-opacity={opacity} />
            {/each}
          </linearGradient>
        </defs>
        <rect x={plate.x} y={plate.y} width={plate.width} height={plate.height} fill={`url(#${finish.id})`} />
      {/if}
      {#if drawing.ordinary}
        {@render shape(drawing.ordinary)}
      {/if}
      {#if crest.edgeWidth > 0}
        <path d={drawing.plateD} fill="none" stroke={drawing.layers.edge} stroke-linejoin="round"
          stroke-width={Math.max(0.75, drawing.plateSide * 0.06 * crest.edgeWidth)} />
      {/if}
    </g>
    {#if crest.showsOutline}
      <path d={drawing.plateD} fill="none" stroke={drawing.layers.edge} stroke-width={Math.max(0.6, size * 0.012)} />
    {/if}
  {/if}
  {#each drawing.trim as piece, index (index)}
    {#if piece.kind === "path"}
      {@render shape(piece.path)}
    {:else if piece.kind === "laurel"}
      <g fill={piece.branch.fill}>
        {@render shape(piece.branch.stem)}
        {#each piece.branch.leaves as leaf, leafIndex (leafIndex)}
          <ellipse cx={leaf.cx} cy={leaf.cy} rx={leaf.rx} ry={leaf.ry} transform={leaf.transform} />
        {/each}
      </g>
    {:else}
      <g fill={piece.fill}>
        {#each piece.beads as bead, beadIndex (beadIndex)}
          <circle cx={bead.cx} cy={bead.cy} r={bead.r} />
        {/each}
      </g>
    {/if}
  {/each}
  <!-- A raised figure casts the kit's paper shadow on its flat field, as BrowserSpaceCrestFigureDepth: 1.6 down, blurred 2.2, on the 64 grid. -->
  <g style:filter={drawing.figureDepth}>
    {#each drawing.figures as figure, index (index)}
      {#if figure.kind === "drawing"}
        <g>
          <defs>
            <mask id={figure.mask} maskUnits="userSpaceOnUse" x={figure.x} y={figure.y} width={figure.side} height={figure.side}>
              <image href={figure.url} x={figure.x} y={figure.y} width={figure.side} height={figure.side} preserveAspectRatio="xMidYMid meet" />
            </mask>
          </defs>
          <rect x={figure.x} y={figure.y} width={figure.side} height={figure.side} fill={figure.tint} mask={`url(#${figure.mask})`} />
        </g>
      {:else if figure.kind === "symbol"}
        <svg x={figure.x} y={figure.y} width={figure.size} height={figure.size} overflow="visible" style:color={figure.tint}>
          <SymbolIcon name={figure.name} size={figure.size} strokeWidth={figure.stroke} />
        </svg>
      {:else}
        <text x={figure.x} y={figure.y} text-anchor="middle" dominant-baseline="central" font-size={figure.fontSize}
          font-weight={figure.fontWeight} fill={figure.fill} font-family={figure.fontFamily}>{figure.text}</text>
      {/if}
    {/each}
  </g>
</svg>
