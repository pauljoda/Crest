<script lang="ts">
  import { untrack } from "svelte";

  /** The split's name being edited in place: Enter or leaving keeps it, Escape cancels. */
  let { initial, onDone }: { initial: string; onDone: (name: string | null) => void } = $props();

  let field: HTMLInputElement | null = null;
  let ended = false;
  // The field starts from the name it opened with, whatever the split is named meanwhile.
  const start = untrack(() => initial);
  const end = (name: string | null) => {
    if (ended) return;
    ended = true;
    onDone(name);
  };
  $effect(() => {
    field?.focus();
    field?.select();
  });
</script>

<input bind:this={field} class="rename-field" value={start} placeholder="Split View Name" aria-label="Split View Name"
  onclick={(event) => event.stopPropagation()}
  onkeydown={(event) => {
    event.stopPropagation();
    // A key that composes text, as an input method's Enter does, is the field's.
    if (event.isComposing || event.keyCode === 229) return;
    if (event.key === "Enter") end(event.currentTarget.value);
    if (event.key === "Escape") end(null);
  }}
  onfocusout={(event) => end(event.currentTarget.value)} />
