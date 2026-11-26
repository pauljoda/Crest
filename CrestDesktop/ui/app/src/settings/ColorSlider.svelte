<script lang="ts">
  import type { BrandColor } from "@crest/contracts";

  import { css } from "../branding";
  import { Grain } from "../shell/SpaceBanner";
  import { metrics } from "./color-popover";

  /**
   * CrestColorSlider: a track of the colors it runs through, set into the
   * popover, under a thumb wearing the color it stands at. Pressing anywhere
   * on the track moves the thumb there and drags it on.
   */
  let { title, value, track, thumb, showsGrain = false, onChange }: {
    title: string;
    value: number;
    track: readonly BrandColor[];
    thumb: BrandColor;
    showsGrain?: boolean;
    onChange: (value: number) => void;
  } = $props();

  let box: HTMLDivElement | undefined = $state();
  let width = $state(296);
  let dragging: number | null = null;
  let lifted = $state(false);
  $effect(() => {
    const element = box;
    if (!element) return;
    const observer = new ResizeObserver(() => (width = element.offsetWidth));
    observer.observe(element);
    width = element.offsetWidth;
    return () => observer.disconnect();
  });
  const inset = metrics.sliderThumb / 2;
  const span = $derived(Math.max(width - 2 * inset, 1));
  const valueAt = (event: PointerEvent) => {
    const bounds = box!.getBoundingClientRect();
    return Math.min(Math.max((event.clientX - bounds.left - inset) / span, 0), 1);
  };
  const key = (event: KeyboardEvent) => {
    const by = event.key === "ArrowRight" || event.key === "ArrowUp" ? 0.05 : event.key === "ArrowLeft" || event.key === "ArrowDown" ? -0.05 : 0;
    if (by === 0) return;
    event.preventDefault();
    onChange(Math.min(Math.max(value + by, 0), 1));
  };
  const gradient = $derived(`linear-gradient(to right, ${track.map((color) => css(color)).join(", ")})`);
</script>

<div bind:this={box} class="color-slider" role="slider" tabindex={0} aria-label={title} {title}
  aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value * 100)} aria-valuetext={`${Math.round(value * 100)}%`}
  onkeydown={key}
  onpointerdown={(event) => {
    if (event.button !== 0) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    dragging = event.pointerId;
    lifted = true;
    onChange(valueAt(event));
  }}
  onpointermove={(event) => {
    if (dragging === event.pointerId) onChange(valueAt(event));
  }}
  onpointerup={(event) => {
    if (dragging !== event.pointerId) return;
    dragging = null;
    lifted = false;
  }}
  onpointercancel={() => {
    dragging = null;
    lifted = false;
  }}>
  <span class="color-slider-track color-inset slim" style:background={gradient}>
    {#if showsGrain}
      <span class="color-slider-grain">
        <Grain {width} height={14} opacity={0.38} />
      </span>
    {/if}
  </span>
  <span class={`color-slider-thumb${lifted ? " lifted" : ""}`}
    style:left="{inset + Math.min(Math.max(value, 0), 1) * span}px" style:background={css(thumb)}></span>
</div>
