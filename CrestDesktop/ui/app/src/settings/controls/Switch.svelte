<script lang="ts">
  import { motion as tokens } from "@crest/design";

  import { layoutMotion } from "../../layout-motion.svelte";

  let { id, checked, onChange, disabled, label }: {
    id?: string;
    checked: boolean;
    onChange: (checked: boolean) => void;
    disabled?: boolean;
    label?: string;
  } = $props();

  let knob: HTMLSpanElement | undefined;
  layoutMotion({ element: () => knob, track: () => checked, timing: () => tokens.collection });
</script>

<button {id} type="button" role="switch" aria-checked={checked} aria-label={label} {disabled}
  class={["settings-switch", checked && "on"]} onclick={() => onChange(!checked)}>
  <span bind:this={knob} class="settings-switch-knob"></span>
</button>
