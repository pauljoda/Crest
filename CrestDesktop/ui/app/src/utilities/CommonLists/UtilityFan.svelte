<script lang="ts" module>
  /** CrestLayout.glassIconButtonDiameter. */
  const fanButtonSize = 44;
</script>

<script lang="ts">
  import type { BrandColor, DownloadState } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";
  import { untrack } from "svelte";

  import { css } from "../../branding";
  import { presence, reducesMotion, transitionStyle } from "../../motion";
  import SymbolIcon from "../../SymbolIcon.svelte";
  import { type UtilitySurfaceName, utilitySurfaceOrder, utilitySurfaces } from "../utility-list";
  import { badgeTint, notificationProgress } from "./badges";
  import NotificationBadge from "./NotificationBadge.svelte";

  /**
   * The Mac's BrowserUtilityFanControl: the archive, history and downloads
   * destinations, fanned out from the lists button onto the page beside the
   * sidebar, a column of glass circles centred on the window, the list shown
   * prominent in the Space's colour. They come out one after another and go
   * back together.
   */
  let { expanded, trigger, selected, badgeColor, downloads, newDownloadCount, onSelect }: {
    expanded: boolean;
    /** The lists button the fan comes out of. */
    trigger: HTMLButtonElement | null;
    selected: UtilitySurfaceName | null;
    badgeColor: BrandColor;
    downloads: readonly DownloadState[];
    newDownloadCount: number;
    onSelect: (surface: UtilitySurfaceName) => void;
  } = $props();

  let geometry = $state.raw<{ origin: { x: number; y: number }; x: number; y: number } | null>(null);
  $effect(() => {
    const [open, from] = [expanded, trigger];
    if (!open) return;
    const measure = () => {
      const button = from?.getBoundingClientRect();
      if (!button) return;
      // Beside the trigger on the page's side: half a button, the gap, and the window's extra offset.
      geometry = {
        origin: { x: button.left + button.width / 2, y: button.top + button.height / 2 },
        x: button.right + fanButtonSize / 2 + 18 + 12,
        y: window.innerHeight / 2,
      };
    };
    untrack(measure);
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  });

  /** Where the `index`th button rests, and how far from there the trigger stands. */
  const place = (index: number) => {
    const shown = geometry ?? { origin: { x: 0, y: 0 }, x: 0, y: 0 };
    const at = { x: shown.x, y: shown.y + (index - 1) * 64 };
    return { at, fromTrigger: { x: shown.origin.x - at.x, y: shown.origin.y - at.y } };
  };
  const reveal = (index: number) => ({ ...tokens.utilityFanReveal, delay: index * 0.045 });
  const symbolOf = (name: UtilitySurfaceName) => (name !== "downloads" ? utilitySurfaces[name].symbol
    : downloads.some((download) => download.phase.needsAttention) ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
      : downloads.some((download) => download.phase.isLive) ? "arrow.down.circle" : "arrow.down.circle.fill");
</script>

<div class="utility-fan" aria-hidden={!expanded}>
  {#each expanded && geometry ? utilitySurfaceOrder : [] as name, index (name)}
    {@const surface = utilitySurfaces[name]}
    {@const { at } = place(index)}
    {@const isSelected = selected === name}
    <button
      class={["utility-fan-button", isSelected && "selected"]}
      style:left="0px"
      style:top="0px"
      style:background={isSelected ? css(badgeColor) : undefined}
      style:transform="translate({at.x - fanButtonSize / 2}px, {at.y - fanButtonSize / 2}px)"
      style:transition={transitionStyle("transform", reducesMotion() ? { duration: 0 } : reveal(index))}
      title={surface.title}
      aria-label={surface.title}
      aria-pressed={isSelected}
      {...{ "aria-description": isSelected ? "Selected" : name === "downloads" ? `${downloads.length} downloads` : undefined }}
      in:presence={{
        pose: { ...place(index).fromTrigger, scale: 0.08, opacity: 0 },
        timing: reducesMotion() ? { duration: 0 } : reveal(index),
      }}
      out:presence={reducesMotion() ? { pose: { opacity: 0 }, timing: { duration: 0 } } : {
        pose: { ...place(index).fromTrigger, scale: 0.08, opacity: 0 },
        timing: { duration: 0.18, ease: "easeOut" },
      }}
      onclick={() => onSelect(name)}
    >
      <SymbolIcon name={symbolOf(name)} size={18} strokeWidth={isSelected ? 2.25 : 1.75} />
      {#if name === "downloads" && newDownloadCount > 0}
        <NotificationBadge count={newDownloadCount} tint={badgeTint(downloads, badgeColor)} progress={notificationProgress(downloads)} />
      {/if}
    </button>
  {/each}
</div>
