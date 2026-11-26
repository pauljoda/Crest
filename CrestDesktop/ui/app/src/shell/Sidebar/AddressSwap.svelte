<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import type { Snippet } from "svelte";

  import { presence, reducesMotion } from "../../motion";

  /**
   * BrowserAddressSwap: a part of the address field that pops out as the field
   * shows another Space, shrinking to 0.8 as it fades, with the new Space's
   * popping in from 0.8 in its place once the old is nearly out; the field
   * itself stays put. A part that comes or goes on its own, as Site Controls
   * once a page is live, pops the same way: `shows` says whether it has
   * anything to show.
   */
  let { swap, shows, children }: { swap: string | null; shows: boolean; children?: Snippet } = $props();

  // Under Reduce Motion the parts change at once.
  const instant = { duration: 0 } as const;
</script>

<!-- The part going leaves the layout to the one coming, in its place. -->
{#each shows ? [swap ?? "prompt"] : [] as key (key)}
  <span class="address-swap"
    in:presence={{ pose: { scale: 0.8, opacity: 0 }, timing: reducesMotion() ? instant : tokens.addressSwapIn }}
    out:presence={{ pose: { scale: 0.8, opacity: 0 }, timing: reducesMotion() ? instant : tokens.addressSwapOut, pop: true }}>
    {@render children?.()}
  </span>
{/each}
