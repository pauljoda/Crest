<script lang="ts" generics="T">
  import { type Choice, radioKeys } from "./index";

  /** A few values side by side, one chosen. */
  let { value, choices, onChange, label, same = Object.is }: {
    value: T;
    choices: readonly Choice<T>[];
    onChange: (value: T) => void;
    label: string;
    same?: (left: T, right: T) => boolean;
  } = $props();

  const chosenIndex = $derived(choices.findIndex((choice) => same(choice.value, value)));
</script>

<div class="settings-segmented" role="radiogroup" aria-label={label}>
  {#each choices as choice, index (choice.label)}
    {@const chosen = index === chosenIndex}
    <button type="button" role="radio" aria-checked={chosen} class={chosen ? "chosen" : undefined}
      tabindex={chosen || (chosenIndex < 0 && index === 0) ? 0 : -1}
      onclick={() => onChange(choice.value)} onkeydown={radioKeys(choices, index, onChange)}>
      {choice.label}
    </button>
  {/each}
</div>
