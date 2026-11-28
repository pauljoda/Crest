<script lang="ts" module>
  /** The Mac's particles, as unit positions and point diameters (SplitMix64, seed 0xC2E57A11). */
  export const grainSamples: readonly (readonly [number, number, number])[] = (() => {
    const mask = (1n << 64n) - 1n;
    let state = 0xC2E5_7A11n;
    const next = () => {
      state = (state + 0x9E37_79B9_7F4A_7C15n) & mask;
      let value = state;
      value = ((value ^ (value >> 30n)) * 0xBF58_476D_1CE4_E5B9n) & mask;
      value = ((value ^ (value >> 27n)) * 0x94D0_49BB_1331_11EBn) & mask;
      value ^= value >> 31n;
      return Number(value) / Number(mask);
    };
    const samples: (readonly [number, number, number])[] = [];
    for (let index = 0; index < 20_000; index++) {
      const x = next();
      const y = next();
      samples.push([x, y, 0.85 + next() * 1.5]);
    }
    return samples;
  })();
</script>

<script lang="ts">
  import { untrack } from "svelte";

  /**
   * BrowserSpaceThemeTexture: the same grain the Mac lays over the banner, one
   * particle per 24 square points, light and dark in turn, from the same seed.
   */
  let { width, height, opacity }: { width: number; height: number; opacity: number } = $props();

  let canvas: HTMLCanvasElement;
  $effect(() => {
    const drawnWidth = width;
    const drawnHeight = height;
    untrack(() => {
      const element = canvas;
      const context = element?.getContext("2d");
      if (!element || !context) return;
      const scale = window.devicePixelRatio || 1;
      element.width = Math.round(drawnWidth * scale);
      element.height = Math.round(drawnHeight * scale);
      context.setTransform(scale, 0, 0, scale, 0, 0);
      context.clearRect(0, 0, drawnWidth, drawnHeight);
      const count = Math.min(grainSamples.length, Math.max(800, Math.floor((drawnWidth * drawnHeight) / 24)));
      for (const [light, fill] of [[true, "rgb(255 255 255 / 0.46)"], [false, "rgb(0 0 0 / 0.38)"]] as const) {
        context.fillStyle = fill;
        context.beginPath();
        for (let index = light ? 0 : 1; index < count; index += 2) {
          const [x, y, diameter] = grainSamples[index];
          const radius = diameter / 2;
          context.moveTo(x * drawnWidth + diameter, y * drawnHeight + radius);
          context.arc(x * drawnWidth + radius, y * drawnHeight + radius, radius, 0, Math.PI * 2);
        }
        context.fill();
      }
    });
  });
</script>

<canvas bind:this={canvas} class="space-banner-grain" style:width="{width}px" style:height="{height}px"
  style:opacity={opacity}></canvas>
