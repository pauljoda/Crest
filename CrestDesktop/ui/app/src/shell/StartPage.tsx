import type { ShortcutBinding, TabState } from "@crest/contracts";

import { EmbeddedPalette } from "../palette/CommandPalette";
import type { PaletteModel } from "../palette/palette-model";
import { Symbol } from "../symbols";
import { CrestMark } from "./CrestMark";

/**
 * The surface a tab shows before it has a page, as the Mac's BrowserStartPage
 * draws it on the desktop: Crest's icon, the title, the private browsing
 * notice in a private window, and the command palette in place, centered on
 * the Space's backdrop, which the page card lets through. Its palette opens
 * what it is given in this tab.
 */
export function StartPage({ palette, isPrivate, bindings, tabs, obscured, takesFocus = true }: {
  /** The Start Page's palette, or null for a Space's Start Page the pager shows still, as the Mac's preview. */
  palette: PaletteModel | null;
  isPrivate: boolean;
  bindings: readonly ShortcutBinding[];
  tabs: readonly TabState[];
  /** Whether the overlay palette covers the page. */
  obscured: boolean;
  /** Whether the palette takes the keyboard as it opens: a split's other cards leave it where it is. */
  takesFocus?: boolean;
}) {
  return (
    <div className="start-page" data-testid="start-page-surface">
      <div className="start-page-stack">
        <CrestMark size={60} className="start-page-mark" />
        <h1 className="start-page-title">Start Page</h1>
        {isPrivate && (
          <div className="start-page-private" role="note">
            <span className="start-page-private-label">
              <Symbol name="eyeglasses" size={15} />
              Private Browsing
            </span>
            <span className="start-page-private-detail">
              Crest does not save this session or use Crest Passwords. Website data stays in memory only.
            </span>
          </div>
        )}
        {palette ? <EmbeddedPalette model={palette} bindings={bindings} tabs={tabs} obscured={obscured} takesFocus={takesFocus} /> : (
          <div className="palette-card embedded" aria-hidden>
            <div className="palette-field">
              <Symbol name="magnifyingglass" size={19} className="palette-glyph" />
              <div className="palette-input">
                <input readOnly tabIndex={-1} placeholder="Search or Enter URL…" />
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
