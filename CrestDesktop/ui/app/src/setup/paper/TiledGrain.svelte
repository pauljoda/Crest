<script lang="ts" module>
  import { grainSamples } from "../../shell/SpaceBanner";

  /** CrestGrainTile's side: the grain repeats every 512 points, however large what it covers. */
  const tileSide = 512;
  const tiles = new Map<string, string>();

  /**
   * CrestGrainTile: the Mac's paper grain as one 512-point tile at `density`
   * specks a square point, drawn once for each density and scale and then
   * repeated, light and dark specks in turn from the same seed as the banner's,
   * wrapped at the tile's edges so the repeat shows no seam.
   */
  function grainTile(density: number): string {
    const scale = window.devicePixelRatio || 1;
    const key = `${density}@${scale}`;
    const cached = tiles.get(key);
    if (cached) return cached;
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(tileSide * scale);
    canvas.height = Math.round(tileSide * scale);
    const context = canvas.getContext("2d")!;
    context.setTransform(scale, 0, 0, scale, 0, 0);
    const count = Math.min(grainSamples.length, Math.round(tileSide * tileSide * density));
    for (const [light, fill] of [[true, "rgb(255 255 255 / 0.46)"], [false, "rgb(0 0 0 / 0.38)"]] as const) {
      context.fillStyle = fill;
      context.beginPath();
      for (let index = light ? 0 : 1; index < count; index += 2) {
        const [x, y, diameter] = grainSamples[index];
        const radius = diameter / 2;
        for (const dx of [0, -tileSide, tileSide]) {
          for (const dy of [0, -tileSide, tileSide]) {
            const cx = x * tileSide + dx;
            const cy = y * tileSide + dy;
            if (cx < -radius || cx > tileSide + radius || cy < -radius || cy > tileSide + radius) continue;
            context.moveTo(cx + radius, cy);
            context.arc(cx, cy, radius, 0, Math.PI * 2);
          }
        }
      }
      context.fill();
    }
    const url = canvas.toDataURL("image/png");
    tiles.set(key, url);
    return url;
  }
</script>

<script lang="ts">
  /** Grain laid over what is behind it in soft light, as CrestGrain draws it. */
  let { density, opacity }: { density: number; opacity: number } = $props();
</script>

<span class="setup-grain" aria-hidden="true"
  style:background-image="url({grainTile(density)})" style:background-size="{tileSide}px {tileSide}px" style:opacity={opacity}
></span>
