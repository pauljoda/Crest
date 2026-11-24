<script lang="ts">
  import SymbolIcon from "../SymbolIcon.svelte";

  /**
   * CrestAngleKnob at 32: a dial of eight ticks with an arrow along the
   * gradient's direction and a handle on its ring. Turning it settles on a
   * multiple of 45° within 4°, and on whole degrees otherwise.
   */
  let { degrees, onChange }: { degrees: number; onChange: (degrees: number) => void } = $props();

  const diameter = 32;
  const radius = diameter / 2;
  const ticks = Array.from({ length: 8 }, (_, index) => index);
  let turning: number | null = null;
  let lifted = $state(false);
  const normalized = (value: number) => ((value % 360) + 360) % 360;
  const settled = (value: number) => {
    const eighth = Math.round(value / 45) * 45;
    return normalized(Math.abs(value - eighth) <= 4 ? eighth : Math.round(value));
  };
  const turnTo = (event: PointerEvent & { currentTarget: HTMLDivElement }) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - bounds.left - radius;
    const y = event.clientY - bounds.top - radius;
    if (Math.hypot(x, y) <= 4) return;
    onChange(settled(normalized((Math.atan2(y, x) * 180) / Math.PI)));
  };
  const ring = radius - 6 - 2;
  const radians = $derived((degrees * Math.PI) / 180);
</script>

<div class="angle-knob" role="slider" tabindex={0} aria-label="Direction" title="Direction"
  aria-valuemin={0} aria-valuemax={359} aria-valuenow={Math.round(degrees)} aria-valuetext={`${Math.round(degrees)} degrees`}
  onkeydown={(event) => {
    const by = event.key === "ArrowRight" || event.key === "ArrowUp" ? 15 : event.key === "ArrowLeft" || event.key === "ArrowDown" ? -15 : 0;
    if (by === 0) return;
    event.preventDefault();
    onChange(normalized(degrees + by));
  }}
  onpointerdown={(event) => {
    if (event.button !== 0) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    turning = event.pointerId;
    lifted = true;
    turnTo(event);
  }}
  onpointermove={(event) => {
    if (turning === event.pointerId) turnTo(event);
  }}
  onpointerup={(event) => {
    if (turning !== event.pointerId) return;
    turning = null;
    lifted = false;
  }}
  onpointercancel={() => {
    turning = null;
    lifted = false;
  }}>
  {#each ticks as index (index)}
    <span class="angle-knob-tick" style:transform="rotate({index * 45}deg) translateY({-radius + 4}px)"></span>
  {/each}
  <span class="angle-knob-arrow" style:transform="rotate({degrees}deg)">
    <SymbolIcon name="arrow.right" size={11} strokeWidth={2.5} />
  </span>
  <span class={`angle-knob-handle${lifted ? " turning" : ""}`}
    style:left="{radius + ring * Math.cos(radians)}px" style:top="{radius + ring * Math.sin(radians)}px"></span>
</div>
