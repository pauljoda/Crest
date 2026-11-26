<script lang="ts" module>
  /** CrestStartPageMarkMetrics, on the mark's grid. */
  const metrics = {
    grid: 64,
    cornerRadius: 15,
    borderOpacity: 0.12,
    /** The side at and below which the mark is drawn flat, keylined rather than shadowed. */
    flatSide: 32,
    /** The keyline's width; drawn under the fill, only its outer half shows. */
    keylineWidth: 2.6,
    /** The near-black the paper layers' shadows fall in. */
    shadow: "rgb(6 10 20)",
  } as const;

  /** One paper layer of the mark, back to front: its color, how far down the tile it sits, and the shadow it casts. */
  const layers = [
    { color: "sky", drop: 18, shadowOffset: 1.6, shadowRadius: 3.2, shadowOpacity: 0.3, keyline: false },
    { color: "coral", drop: 9, shadowOffset: 2.2, shadowRadius: 2.6, shadowOpacity: 0.42, keyline: true },
    { color: "butter", drop: 0, shadowOffset: 2.2, shadowRadius: 2.6, shadowOpacity: 0.42, keyline: true },
  ] as const;

  /** CrestMarkBannerShape: a rounded rectangle cut at its foot into a soft swallowtail. */
  const bannerPath = "M17 13.8Q17 11 19.8 11L44.2 11Q47 11 47 13.8L47 32.2Q47 35 44.78 33.3L34.22 25.2"
    + "Q32 23.5 29.78 25.2L19.22 33.3Q17 35 17 32.2Z";

  function rgb(color: readonly number[]): string {
    return `rgb(${color.join(" ")})`;
  }
</script>

<script lang="ts">
  import { brand } from "@crest/design";

  /**
   * Crest's mark, as the Mac's CrestStartPageMark draws it: the Crest banner
   * cut from paper three times and stacked on an ink tile, butter in front,
   * coral behind it and sky at the back, under a rim one device pixel wide.
   * Large, each banner casts a soft shadow on the one behind; small, the mark
   * is flat and the front two banners carry an ink keyline instead. Depth
   * comes from the layers, never from gloss. Drawn on the mark's 64-point grid.
   */
  let { size, className }: { size: number; className?: string } = $props();

  const id = $props.id();
  const flat = $derived(size <= metrics.flatSide);
  const rim = $derived(1 / (globalThis.devicePixelRatio || 1) * (metrics.grid / size));
</script>

<svg class={className} width={size} height={size} viewBox={`0 0 ${metrics.grid} ${metrics.grid}`} aria-hidden="true">
  {#if !flat}
    <defs>
      {#each layers as layer (layer.color)}
        <filter id={`${id}-${layer.color}`} x="-30%" y="-30%" width="160%" height="170%">
          <feDropShadow dx="0" dy={layer.shadowOffset} stdDeviation={layer.shadowRadius / 2}
            flood-color={metrics.shadow} flood-opacity={layer.shadowOpacity} />
        </filter>
      {/each}
    </defs>
  {/if}
  <rect width={metrics.grid} height={metrics.grid} rx={metrics.cornerRadius} fill={rgb(brand.ink)} />
  {#each layers as layer (layer.color)}
    <g transform={`translate(0 ${layer.drop})`}>
      {#if flat && layer.keyline}
        <path d={bannerPath} fill="none" stroke={rgb(brand.ink)} stroke-width={metrics.keylineWidth} stroke-linejoin="round" />
      {/if}
      <path d={bannerPath} fill={rgb(brand[layer.color])} filter={flat ? undefined : `url(#${id}-${layer.color})`} />
    </g>
  {/each}
  <rect x={rim / 2} y={rim / 2} width={metrics.grid - rim} height={metrics.grid - rim} rx={metrics.cornerRadius - rim / 2}
    fill="none" stroke="white" stroke-opacity={metrics.borderOpacity} stroke-width={rim} />
</svg>
