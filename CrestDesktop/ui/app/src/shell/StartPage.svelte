<script lang="ts">
  import type { ShortcutBinding, TabState } from "@crest/contracts";

  import { EmbeddedPalette } from "../palette/CommandPalette";
  import type { PaletteModel } from "../palette/palette-model";
  import SymbolIcon from "../SymbolIcon.svelte";
  import AppIcon from "./AppIcon.svelte";

  /**
   * The surface a tab shows before it has a page, as the Mac's BrowserStartPage
   * draws it on the desktop: Crest's icon, the title, the private browsing
   * notice in a private window, and the command palette in place, centered on
   * the Space's backdrop, which the page card lets through. Its palette opens
   * what it is given in this tab.
   */
  let { palette, isPrivate, bindings, tabs, obscured, takesFocus = true }: {
    /** The Start Page's palette, or null for a Space's Start Page the pager shows still, as the Mac's preview. */
    palette: PaletteModel | null;
    isPrivate: boolean;
    bindings: readonly ShortcutBinding[];
    tabs: readonly TabState[];
    /** Whether the overlay palette covers the page. */
    obscured: boolean;
    /** Whether the palette takes the keyboard as it opens: a split's other cards leave it where it is. */
    takesFocus?: boolean;
  } = $props();
</script>

<div class="start-page" data-testid="start-page-surface">
  <div class="start-page-stack">
    <AppIcon size={60} />
    <h1 class="start-page-title">Start Page</h1>
    {#if isPrivate}
      <div class="start-page-private" role="note">
        <span class="start-page-private-label">
          <SymbolIcon name="eyeglasses" size={15} />
          Private Browsing
        </span>
        <span class="start-page-private-detail">
          Crest does not save this session or use Crest Passwords. Website data stays in memory only.
        </span>
      </div>
    {/if}
    {#if palette}
      <EmbeddedPalette model={palette} {bindings} {tabs} {obscured} {takesFocus} />
    {:else}
      <div class="palette-card embedded" aria-hidden="true">
        <div class="palette-field">
          <SymbolIcon name="magnifyingglass" size={19} class="palette-glyph" />
          <div class="palette-input">
            <input readonly tabindex={-1} placeholder="Search or Enter URL…" />
          </div>
        </div>
      </div>
    {/if}
  </div>
</div>
