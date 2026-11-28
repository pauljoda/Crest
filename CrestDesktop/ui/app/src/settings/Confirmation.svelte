<script lang="ts" module>
  /** How a `motion.div` without a transition of its own faded: Motion's 0.3 s on its gentler ease. */
  const fade = { duration: 0.3, ease: [0.25, 0.1, 0.35, 1] } as const;
</script>

<script lang="ts" generics="T">
  import type { Snippet } from "svelte";

  import { presence } from "../motion";

  /** A question one of the sections asks before it goes on, as the Mac's confirmation dialogs do. */
  let { question, children }: {
    /** What it asks about, or nothing while it asks nothing. */
    question: T | null | false;
    /** The question, asked about it. */
    children: Snippet<[NonNullable<T>]>;
  } = $props();
</script>

{#if question}
  <div class="sheet-backdrop" in:presence={{ pose: { opacity: 0 }, timing: fade }} out:presence={{ pose: { opacity: 0 }, timing: fade }}>
    {@render children(question)}
  </div>
{/if}
