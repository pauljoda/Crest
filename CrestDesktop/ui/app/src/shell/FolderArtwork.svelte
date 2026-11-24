<script lang="ts" module>
  /** The folder's footprint, a folder symbol's at the sidebar's row size. */
  const width = 18;
  const height = 14;
  /** BrowserFolderGeometry. */
  const geometry = { translation: 3, yAngle: 32, frontAngle: -30, backAngle: 28, perspective: 350, tabHeight: 0.25, tabStart: 0.42, tabEnd: 0.58, cornerDivisor: 7 };

  const inset = 0.5;
  const w = width - inset * 2;
  const h = height - inset * 2;
  const top = height * geometry.tabHeight;
  const shoulder = top / 1.5;
  const radius = width / geometry.cornerDivisor;
  const back = [
    `M ${radius} 0`, `L ${w * geometry.tabStart} 0`, `L ${w * geometry.tabEnd} ${shoulder}`, `L ${w - radius} ${shoulder}`,
    `A ${radius} ${radius} 0 0 1 ${w} ${shoulder + radius}`, `L ${w} ${h - radius}`,
    `A ${radius} ${radius} 0 0 1 ${w - radius} ${h}`, `L ${radius} ${h}`, `A ${radius} ${radius} 0 0 1 0 ${h - radius}`,
    `L 0 ${radius}`, `A ${radius} ${radius} 0 0 1 ${radius} 0`, "Z",
  ].join(" ");
  const frontHeight = Math.max(1, height - top);

  /** BrowserFolderFaceProjection at `openness`: tilted about the foot, turned, nudged along, in perspective. */
  function faceTransform(openness: number, tilt: number): string {
    return `perspective(${geometry.perspective}px) translateX(${geometry.translation * openness}px) rotateY(${geometry.yAngle * openness}deg) rotateX(${tilt * openness}deg)`;
  }
</script>

<script lang="ts">
  import type { BrandColor } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";
  import { untrack } from "svelte";
  import { Tween } from "svelte/motion";

  import { css, emojiOf, toneOver } from "../branding";
  import { reducesMotion, timed } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";

  /**
   * The Mac's BrowserFolderFaces: a folder drawn as two flat faces in its own
   * colour, the back a shade darker with its tab, the front lit a little and
   * wearing the folder's emoji or symbol; opening the folder swings the faces
   * apart about their foot, as a folder opens.
   */
  let { symbol, color, expanded }: { symbol: string; color: BrandColor; expanded: boolean } = $props();

  const fill = $derived(css(color));
  const ink = $derived(toneOver(color) === "light" ? "white" : "black");
  const emoji = $derived(emojiOf(symbol));
  const glyph = $derived(emoji ?? (symbol !== "folder" && symbol !== "folder.fill" ? symbol : null));
  // One openness drives both faces, the transform written out in the Mac's
  // order: tilted about the foot, turned, nudged along, in perspective.
  const { duration, easing } = timed(tokens.collection);
  const openness = new Tween(untrack(() => expanded) ? 1 : 0, { duration, easing });
  $effect(() => {
    const target = expanded ? 1 : 0;
    // The transition follows Reduce Motion, read as the folder changes.
    untrack(() => void openness.set(target, reducesMotion() ? { duration: 0 } : undefined));
  });
</script>

<span class="folder-artwork" style:width="{width}px" style:height="{height}px" aria-hidden="true">
  <svg class="folder-face" {width} {height} viewBox={`${-inset} ${-inset} ${width} ${height}`}
    style:transform={faceTransform(openness.current, geometry.backAngle)} style:transform-origin="0 100%">
    <path d={back} {fill} />
    <path d={back} fill="black" fill-opacity={0.22} />
  </svg>
  <span class="folder-face front" style:height="{frontHeight}px" style:transform={faceTransform(openness.current, geometry.frontAngle)}
    style:transform-origin="0 100%" style:color={ink}>
    <svg {width} height={frontHeight} viewBox={`0 0 ${width} ${frontHeight}`}>
      <rect x={inset} y={inset} width={width - inset * 2} height={frontHeight - inset * 2} rx={Math.max(0, radius - inset)} {fill} />
      <rect x={inset} y={inset} width={width - inset * 2} height={frontHeight - inset * 2} rx={Math.max(0, radius - inset)} fill="white"
        fill-opacity={0.12} />
    </svg>
    {#if glyph}
      <span class="folder-glyph" style:font-size="{frontHeight * 0.5}px">
        {#if emoji}{emoji}{:else}<SymbolIcon name={glyph} size={Math.round(frontHeight * 0.55)} strokeWidth={2.5} />{/if}
      </span>
    {/if}
  </span>
</span>
