<script lang="ts">
  import type { Snippet } from "svelte";

  import Row from "./Row.svelte";
  import Switch from "./Switch.svelte";

  /** A setting that is on or off, which Settings always draws as a switch. */
  let { title, subtitle, checked, onChange, disabled, defaultValue }: {
    title: string | Snippet;
    subtitle?: string | Snippet;
    checked: boolean;
    onChange: (checked: boolean) => void;
    disabled?: boolean;
    /** How it ships, which offers a reset while it differs. */
    defaultValue?: boolean;
  } = $props();

  const id = $props.id();
</script>

<Row {title} {subtitle} htmlFor={id}
  onReset={defaultValue !== undefined && checked !== defaultValue && !disabled ? () => onChange(defaultValue) : null}>
  <Switch {id} {checked} {onChange} {disabled} />
</Row>
