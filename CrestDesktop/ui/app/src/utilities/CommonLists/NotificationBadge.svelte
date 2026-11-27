<script lang="ts">
  import type { BrandColor } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import { css, toneOver } from "../../branding";
  import { presence } from "../../motion";

  /**
   * BrowserUtilityNotificationBadge: the count, up to 99, on a capsule of the
   * tint at least 16 points each way, 4 in from its ends, raised 4 points off
   * the button's top trailing corner, and ringed with the newest live
   * download's progress.
   */
  let { count, tint, progress }: { count: number; tint: BrandColor | "danger"; progress: number | null } = $props();

  const reads = $derived(tint === "danger" ? "light" : toneOver(tint));
  const hidden = { scale: 0.4, opacity: 0 };
</script>

<span class="utility-badge" aria-hidden="true"
  style:background={tint === "danger" ? "var(--danger)" : css(tint)} style:color={reads === "light" ? "white" : "black"}
  in:presence|global={{ pose: hidden, timing: tokens.floatingPane }} out:presence={{ pose: hidden, timing: tokens.floatingPane }}>
  {Math.min(count, 99)}{#if progress !== null}
    <svg class="utility-badge-ring" viewBox="0 0 100 100" preserveAspectRatio="none">
      <rect x="0.75" y="0.75" width="98.5" height="98.5" rx="49" ry="49" pathLength={100}
        stroke-dasharray="{Math.max(Math.min(progress, 1), 0.04) * 100} 100" />
    </svg>
  {/if}
</span>
