import { ApplyManualSetup, ImportPreview, type SpaceState } from "@crest/contracts";
import { useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { readsLight } from "../branding";
import { ChromeButton } from "../shell/ChromeButton";
import { SpaceBanner } from "../shell/SpaceBanner";
import { StartPage } from "../shell/StartPage";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { SpaceSwitcher } from "../spaces/SpaceSwitcher";
import { Symbol } from "../symbols";

/** BrowserSetupLiveSessionMetrics.changeInterval: the preview takes the newest draft at most this often. */
const changeInterval = 66;

/**
 * The Spaces Setup will make, as the core would open them once it applies
 * the draft (ImportPreview of ApplyManualSetup), asked again as the draft
 * changes, the first change at once and the newest at most every 66 ms.
 */
export function usePreviewSpaces(session: Session): readonly SpaceState[] {
  const draft = session.core.state.setupDraft;
  const [spaces, setSpaces] = useState<readonly SpaceState[]>([]);
  const last = useRef(0);
  const timer = useRef<number | null>(null);
  useEffect(() => {
    if (!draft) return;
    const ask = () => {
      timer.current = null;
      last.current = performance.now();
      session.core.query(ImportPreview({ import: ApplyManualSetup({ workspaceId: session.workspaceId, windowId: session.windowId }) }))
        .then((preview) => setSpaces(preview.session.spaces), () => undefined);
    };
    if (timer.current !== null) return;
    const wait = Math.max(0, changeInterval - (performance.now() - last.current));
    if (wait === 0) ask();
    else timer.current = window.setTimeout(ask, wait);
  }, [session, draft]);
  useEffect(() => () => {
    if (timer.current !== null) clearTimeout(timer.current);
  }, []);
  return spaces;
}

/**
 * BrowserSetupLiveWindow, as Windows can draw it: Crest's window for the
 * Space Setup shows, at its real size, wearing that Space's look, with its
 * sidebar, its Spaces in the switcher and its Start Page. The Mac runs a
 * second core for a preview the person can use; Windows' host holds one, so
 * this one is still, and only follows the draft.
 */
export function SetupPreview({ spaces, shownSpaceId }: { spaces: readonly SpaceState[]; shownSpaceId: string | null }) {
  const space = spaces.find((each) => each.id === shownSpaceId) ?? spaces[0];
  if (!space) return null;
  const look = space.settings.look;
  return (
    <div className={`browser-window with-title-bar ${readsLight(look) ? "reads-light" : "reads-dark"} sidebar-docked setup-preview-window`}
      role="img" aria-label="Preview of Crest">
      <SpaceBanner spaces={spaces} spaceId={space.id} />
      <div className="sidebar-slot docked">
        <aside className="sidebar">
          <div className="address-area">
            <div className="address-field">
              <span className="address-progress" aria-hidden />
              <span className="address-summary"><span className="address-domain placeholder">Search or enter website</span></span>
            </div>
          </div>
          <div className="space-pages">
            <div className="space-page">
              <div className="space-header without-pins">
                <span className="space-header-title">
                  <span className="space-header-identity">
                    <span className="space-header-crest">
                      <SpaceIdentityIcon symbol={space.settings.symbol} branding={look} size={20} />
                    </span>
                  </span>
                  <span className="space-name">{space.settings.name}</span>
                </span>
                <ChromeButton symbol="ellipsis" label="Space Actions" className="space-header-actions" />
              </div>
              <div className="tab-list">
                <section className="tab-section current-tabs">
                  <span className="sidebar-row new-tab-row">
                    <span className="row-glyph"><Symbol name="plus" size={14} /></span>
                    <span className="row-title">New Tab</span>
                  </span>
                </section>
              </div>
            </div>
          </div>
          <SpaceSwitcher spaces={spaces} selectedId={space.id} onSelect={() => {}}
            leading={<ChromeButton symbol="sidebar.left" label="Hide Sidebar" />}
            trailing={<ChromeButton symbol="archivebox" label="Archive" className="common-lists-button" />} />
        </aside>
      </div>
      <div className="space-content">
        <div className="space-content-page live">
          <div className="page-columns">
            <div className="page-column focused">
              <main className="page-card clear">
                <StartPage palette={null} isPrivate={false} bindings={[]} tabs={[]} obscured={false} takesFocus={false} />
              </main>
            </div>
          </div>
        </div>
      </div>
      <header className="title-bar">
        <div className="title-bar-navigation">
          <ChromeButton symbol="chevron.left" label="Back" disabled className="navigation-button" size={23} />
          <ChromeButton symbol="chevron.right" label="Forward" disabled className="navigation-button" size={23} />
          <ChromeButton symbol="arrow.clockwise" label="Reload" disabled className="navigation-button" size={18} />
        </div>
        <span className="title-bar-drag" />
        {/* Windows' own caption buttons, dimmed, where the Mac's preview dims its traffic lights. */}
        <div className="window-controls inactive" aria-hidden>
          <span className="window-control">{""}</span>
          <span className="window-control">{""}</span>
          <span className="window-control close">{""}</span>
        </div>
      </header>
    </div>
  );
}
