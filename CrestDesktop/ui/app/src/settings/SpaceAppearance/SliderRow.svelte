<script lang="ts">
  import { Row } from "../controls";

  /** CrestSettingSlider: the title, a reset once it differs from the starting look, a slider, and its readout. */
  let { title, value, defaultValue, readout = (v) => `${Math.round(v * 100)}%`, onDrag, onEnd, onReset }: {
    title: string;
    value: number;
    defaultValue: number;
    readout?: (value: number) => string;
    onDrag: (value: number) => void;
    onEnd: () => void;
    onReset: (value: number) => void;
  } = $props();
</script>

<Row {title} onReset={Math.abs(value - defaultValue) > 0.0001 ? () => onReset(defaultValue) : null}>
  <!-- Every step of a drag shows, as `input` reports them; `change` would wait for the drag's end. -->
  <input type="range" class="forge-slider" min={0} max={1} step={0.01} {value} aria-label={title}
    oninput={(event) => onDrag(Number(event.currentTarget.value))} onpointerup={onEnd} onkeyup={onEnd} onfocusout={onEnd} />
  <span class="forge-readout">{readout(value)}</span>
</Row>
