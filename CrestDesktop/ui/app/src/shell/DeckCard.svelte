<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import { type Snippet, untrack } from "svelte";

  import { reducesMotion, timed, transitionStyle } from "../motion";

  /**
   * One member's icon in a split's deck (SplitGroupHeader.svelte), standing
   * where the deck puts it and moving there on the collection spring as the
   * deck changes; the focused icon hops as focus reaches it.
   */
  let { focused, focusedId, size, style, children }: {
    focused: boolean;
    focusedId: string | null;
    /** The icon's size, a fifth of which the hop rises. */
    size: number;
    style: { scale: number; rotate: number; x: number; y: number; zIndex: number };
    children?: Snippet;
  } = $props();

  let face: HTMLSpanElement | null = null;
  let first = true;
  // The focused icon hops as focus reaches it: up a fifth of its size and back.
  $effect(() => {
    void focusedId;
    void focused;
    untrack(() => {
      if (first) {
        first = false;
        return;
      }
      if (!focused || reducesMotion() || !face) return;
      const { duration, css } = timed({ duration: 0.22, ease: "easeInOut" });
      face.animate([
        { transform: "translateY(0px)", easing: css },
        { transform: `translateY(${-size * 0.18}px)`, easing: css },
        { transform: "translateY(0px)" },
      ], { duration });
    });
  });
</script>

<span class="split-deck-card" style:z-index={style.zIndex} style:transform-origin="50% 100%"
  style:transform="translateX({style.x}px) translateY({style.y}px) scale({style.scale}) rotate({style.rotate}deg)"
  style:transition={transitionStyle("transform", tokens.collection)}>
  <span bind:this={face} class="split-deck-face">{@render children?.()}</span>
</span>
