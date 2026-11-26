<script lang="ts">
  import type { SpaceFill } from "../../spaces/space-fills";
  import FillDot from "./FillDot.svelte";

  /** CrestColorWell: a 30-point circle of the fill in a ring, which opens its color popover below it. */
  let { title, fill, selected, onToggle }: {
    title: string;
    fill: SpaceFill;
    selected: boolean;
    onToggle: (element: HTMLElement) => void;
  } = $props();
</script>

<button type="button" class={`color-well${selected ? " selected" : ""}`} {title} aria-label={title}
  {...{ "aria-description": fill.colors.length > 1 ? "Gradient" : "Color" }} aria-expanded={selected}
  onclick={(event) => onToggle(event.currentTarget)}>
  <FillDot {fill} size={30} line />
</button>
