<script lang="ts">
  import { untrack } from "svelte";

  /**
   * A title being renamed in place, as the Mac's rename field: it starts with
   * the whole name selected; Enter or leaving it keeps the name, and Escape
   * cancels.
   */
  let { initial, placeholder, onDone }: {
    initial: string;
    placeholder: string;
    onDone: (title: string | null) => void;
  } = $props();

  let draft = $state(untrack(() => initial));
  let ended = false;
  const end = (title: string | null) => {
    if (ended) return;
    ended = true;
    onDone(title);
  };
</script>

<!-- It takes the keys as it appears, from whatever had them. -->
<input
  class="rename-field"
  bind:value={draft}
  {placeholder}
  aria-label={placeholder}
  spellcheck={false}
  {@attach (field) => field.focus()}
  onfocusin={(event) => event.currentTarget.select()}
  onclick={(event) => event.stopPropagation()}
  onkeydown={(event) => {
    // A key that finishes composing a character belongs to the input method.
    if (event.isComposing) return;
    if (event.key === "Enter") end(draft);
    else if (event.key === "Escape") end(null);
  }}
  onfocusout={() => end(draft)}
/>
