<script lang="ts" module>
  import type { TransitionConfig } from "svelte/transition";

  import { timed, type Timing } from "../motion";

  /** BrowserSetupStepChips' tilt: each chip a little askew, as if laid down by hand. */
  const tilts = [-2, 1.5, -1, 2];

  /**
   * A chip's name growing out of its number to its own width, fading and
   * scaling up from 0.8 as it comes, and the other way as it goes, as
   * Motion's `width: "auto"` measured and moved it.
   */
  function grow(node: Element, { timing }: { timing: Timing }): TransitionConfig {
    const width = (node as HTMLElement).scrollWidth;
    const { duration, delay, easing } = timed(timing);
    return {
      duration,
      delay,
      easing,
      css: (t) => `width: ${width * t}px; opacity: ${t}; transform: scale(${0.8 + 0.2 * t})`,
    };
  }
</script>

<script lang="ts">
  import { motion as tokens } from "@crest/design";

  import { reducesMotion } from "../motion";
  import { setupSteps, type SetupStepName } from "./setup-walk";

  /**
   * BrowserSetupStepChips: a numbered paper chip for each step. On the welcome
   * every chip is large, named and colored; in a step's header they are
   * compact, the steps reached colored, the open one named, lifted and a
   * little larger, the ones ahead plain paper. Pressing one opens its step.
   */
  let { walk, current, size, onOpen }: {
    walk: readonly SetupStepName[];
    current: SetupStepName | null;
    size: "welcome" | "compact";
    onOpen: (step: SetupStepName) => void;
  } = $props();

  const reached = $derived(current ? walk.indexOf(current) : -1);
</script>

<div class="setup-chips {size}" role="group" aria-label="Setup steps">
  {#each walk as name, index (name)}
    {@const step = setupSteps[name]}
    {@const open = index === reached}
    {@const colored = size === "welcome" || index <= reached}
    {@const names = size === "welcome" || open}
    <button type="button" class={["setup-chip", open && "open", colored && "colored"]}
      aria-label={step.title} aria-current={open ? "step" : undefined} data-testid="setup-step-{name}"
      style:--chip-color="rgb({step.color.join(' ')})" style:--chip-tilt="{tilts[index % tilts.length]}deg"
      onclick={() => onOpen(name)}>
      <span class="setup-chip-number">{String(index + 1).padStart(2, "0")}</span>
      <!-- The open step's name comes in from the number, as the Mac's grows from the leading edge. -->
      {#if names}
        <span class="setup-chip-title"
          in:grow={{ timing: reducesMotion() ? { duration: 0 } : tokens.setupChips }}
          out:grow={{ timing: reducesMotion() ? { duration: 0 } : tokens.setupChips }}>
          {step.title}
        </span>
      {/if}
    </button>
  {/each}
</div>
