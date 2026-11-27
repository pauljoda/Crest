<script lang="ts">
  import type { AppearanceRange } from "../../appearance.svelte";
  import Row from "./Row.svelte";

  let { title, id, preference, unit, multiplier = 1, zero, labels, disabled = false }: {
    title: string; id: string; preference: AppearanceRange; unit: string; multiplier?: number; disabled?: boolean; zero?: string; labels?: Readonly<Record<number, string>>;
  } = $props();
  const uid = $props.id();
  const inputId = $derived(uid + "-" + id);
  const readout = $derived(labels?.[preference.current] ?? (preference.current === 0 && zero ? zero : String(Math.round(preference.current * multiplier)) + unit));
</script>

<Row {title} htmlFor={inputId} onReset={disabled || preference.current === preference.fallback ? null : () => preference.set(preference.fallback)}>
  <input id={inputId} data-testid={id} {disabled} class="settings-appearance-slider"
    style:--filled={100 * (preference.current - preference.min) / (preference.max - preference.min) + "%"} type="range" min={preference.min} max={preference.max} step={preference.step}
    value={preference.current} aria-valuetext={readout} oninput={(event) => preference.set(event.currentTarget.valueAsNumber)} />
  <span class="forge-readout">{readout}</span>
</Row>
