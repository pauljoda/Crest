<script lang="ts">
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { Row } from "../controls";

  /** A row with a menu of choices and a reset once it differs from the starting look. */
  let { title, value, choices, onChange, onReset }: {
    title: string;
    value: string;
    choices: readonly { readonly value: string; readonly label: string }[];
    onChange: (value: string) => void;
    onReset: (() => void) | null;
  } = $props();

  const id = $props.id();
</script>

<Row {title} htmlFor={id} {onReset}>
  <span class="settings-select">
    <select {id} {value} onchange={(event) => onChange(event.currentTarget.value)}>
      {#each choices as choice (choice.value)}
        <option value={choice.value}>{choice.label}</option>
      {/each}
    </select>
    <SymbolIcon name="chevron.up.chevron.down" size={11} class="settings-select-glyph" />
  </span>
</Row>
