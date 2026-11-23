import type { SpaceState } from "@crest/contracts";
import type { CSSProperties, ReactNode } from "react";

import type { Session } from "../boot";
import { css, primaryColor } from "../branding";
import { showContextMenu } from "../menus";
import { PageCard } from "../shell/PageCard";
import { Symbol } from "../symbols";
import { failureMessages, isAuthenticating, unlockSpace, useAccessFailure } from "./space-access";
import { showSpace } from "./show-space";
import { SpaceIdentityIcon } from "./SpaceIdentity";

/**
 * BrowserSpaceAccessView as the page area's overlay: a locked Space's card
 * holds its crest with a lock, its name, "Space Locked", and Unlock, which
 * asks Windows Hello, with why the last try failed under it, and Switch
 * Space while there is another. None of the Space's pages show. `children`
 * layer over the row, as the window's notices do over its cards.
 */
export function SpaceAccessView({ session, space, spaces, passive, children }: {
  session: Session;
  space: SpaceState;
  spaces: readonly SpaceState[];
  passive: boolean;
  children?: ReactNode;
}) {
  const failure = useAccessFailure();
  const authenticating = isAuthenticating(session.core, space.id);
  const others = spaces.filter((candidate) => candidate.id !== space.id);
  const content = (
    <div className="space-access" data-testid="private-space-lock"
      style={{ "--access-tint": css(primaryColor(space.settings.look), 0.1) } as CSSProperties}>
      <div className="space-access-content">
        <span className="space-access-icon">
          <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={64} />
          <span className="space-access-badge"><Symbol name="lock.fill" size={16} /></span>
        </span>
        <div className="space-access-heading">
          <h1>{space.settings.name}</h1>
          <span className="space-access-status"><Symbol name="lock.fill" size={11} />Space Locked</span>
        </div>
        <p>Unlock to view your tabs.</p>
        <button type="button" className="space-access-unlock" data-testid="unlock-private-space" disabled={passive || isAuthenticating(session.core)}
          aria-label={authenticating ? "Authenticating…" : `Unlock ${space.settings.name}`}
          onClick={() => void unlockSpace(session, space)}>
          {authenticating ? <span className="space-access-spinner" aria-hidden /> : <><Symbol name="lock.open.fill" size={13} />Unlock</>}
        </button>
        {/* The message keeps its room, so a failure never moves the button. */}
        <p className={`space-access-failure${failure ? "" : " reserved"}`} aria-live="polite">
          {failureMessages[failure ?? "unavailable"]}
        </p>
        {others.length > 0 && (
          <button type="button" className="space-access-switch" data-testid="switch-private-space" disabled={passive}
            onClick={(event) => {
              const bounds = event.currentTarget.getBoundingClientRect();
              void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom + 4 }, others.map((candidate) => ({
                title: candidate.settings.name,
                run: () => void showSpace(session.core, session.windowId, candidate.id).catch(() => undefined),
              })));
            }}>
            <Symbol name="square.grid.2x2" size={13} />
            Switch Space
          </button>
        )}
      </div>
    </div>
  );
  return (
    <div className="page-columns">
      <div className="page-column focused">
        <PageCard session={session} pageId={null} passive={passive} startPage={content} />
      </div>
      {children}
    </div>
  );
}
