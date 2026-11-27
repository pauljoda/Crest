<script lang="ts" generics="T">
  import type { Snippet } from "svelte";

  import SymbolIcon from "../../SymbolIcon.svelte";
  import type { Choice } from "./index";
  import Row from "./Row.svelte";

  /** A setting that takes one of several values, from a menu. */
  let { title, subtitle, value, choices, onChange, disabled, defaultValue, same = Object.is }: {
    title: string | Snippet;
    subtitle?: string | Snippet;
    value: T;
    choices: readonly Choice<T>[];
    onChange: (value: T) => void;
    disabled?: boolean;
    defaultValue?: T;
    same?: (left: T, right: T) => boolean;
  } = $props();

  const id = $props.id();
  // A value no choice matches shows the first choice, as a controlled select does.
  const index = $derived(Math.max(0, choices.findIndex((choice) => same(choice.value, value))));
</script>

<Row {title} {subtitle} htmlFor={id}
  onReset={defaultValue !== undefined && !same(value, defaultValue) && !disabled ? () => onChange(defaultValue) : null}>
  <span class="settings-select">
    <select {id} value={index} {disabled}
      onchange={(event) => {
        onChange(choices[Number(event.currentTarget.value)].value);
        // The menu shows the value it is given, so a choice that changed nothing, such as one a question cancelled, goes back.
        event.currentTarget.value = String(index);
      }}>
      {#each choices as choice, at}
        <option value={at}>{choice.label}</option>
      {/each}
    </select>
    <SymbolIcon name="chevron.up.chevron.down" size={11} class="settings-select-glyph" />
  </span>
</Row>
