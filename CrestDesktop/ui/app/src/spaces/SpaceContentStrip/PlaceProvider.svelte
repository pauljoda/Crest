<script lang="ts">
  import { setContext, type Snippet } from "svelte";

  import { StripPlace } from "./strip-place";

  /** Tells what a card holds the place in the strip it stands in, as `StripPlace` names it. */
  let { id, waits, children }: { id: string; waits: boolean; children: Snippet } = $props();

  setContext<StripPlace>(StripPlace, {
    get id() {
      return id;
    },
    get waits() {
      return waits;
    },
  });
</script>

{@render children()}
