<script lang="ts">
  let { value, size }: { value: number; size: number } = $props();

  const radius = $derived(size / 2 - 2);
  const length = $derived(2 * Math.PI * radius);
  const shown = $derived(Math.min(Math.max(value, 0.02), 1));
</script>

<svg class="progress-ring" width={size} height={size} viewBox="0 0 {size} {size}" aria-hidden="true">
  <circle cx={size / 2} cy={size / 2} r={radius} class="progress-ring-track" />
  <circle cx={size / 2} cy={size / 2} r={radius} class="progress-ring-value"
    stroke-dasharray="{length * shown} {length}" transform="rotate(-90 {size / 2} {size / 2})" />
</svg>
