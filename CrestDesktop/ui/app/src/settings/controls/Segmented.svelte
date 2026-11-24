<script lang="ts" generics="T">
  import type { Choice } from "./index";

  /** A few values side by side, one chosen. */
  let { value, choices, onChange, label, same = Object.is }: {
    value: T;
    choices: readonly Choice<T>[];
    onChange: (value: T) => void;
    label: string;
    same?: (left: T, right: T) => boolean;
  } = $props();
</script>

<div class="settings-segmented" role="radiogroup" aria-label={label}>
  {#each choices as choice (choice.label)}
    {@const chosen = same(choice.value, value)}
    <button type="button" role="radio" aria-checked={chosen} class={chosen ? "chosen" : undefined} onclick={() => onChange(choice.value)}>
      {choice.label}
    </button>
  {/each}
</div>
