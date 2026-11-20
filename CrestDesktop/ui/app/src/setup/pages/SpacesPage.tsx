import { AddSetupSpace, MoveSetupSpace, RemoveSetupSpace, type SetupDraftSpace } from "@crest/contracts";
import { Fragment, type MouseEvent, useState } from "react";

import type { Session } from "../../boot";
import { type MenuEntry, showContextMenu } from "../../menus";
import { SpaceIdentityIcon } from "../../spaces/SpaceIdentity";
import { Symbol } from "../../symbols";
import { useCoreVersion } from "../../use-core";
import { explanation } from "../use-setup-space";

/**
 * BrowserSetupSpacesPage: the Spaces Setup will make, each followed by its
 * Sub-Spaces and an Add Sub-Space, then New Space. A row opens its Space's
 * page; its menu moves a Space up or down, or removes one Setup added.
 */
export function SpacesPage({ session, onOpenSpace }: { session: Session; onOpenSpace: (spaceId: string) => void }) {
  useCoreVersion(session);
  const [error, setError] = useState<string | null>(null);
  const draft = session.core.state.setupDraft;
  if (!draft) return <div className="setup-page-content"><h2 className="setup-page-heading">Spaces</h2></div>;
  const primaries = draft.spaces.filter((space) => space.primaryId === null);
  const run = async (intent: Parameters<Session["core"]["send"]>[0]) => {
    try {
      await session.core.send(intent);
      setError(null);
      return true;
    } catch (failure) {
      setError(explanation(failure));
      return false;
    }
  };
  // A new Space or Sub-Space opens its page, as the Mac's does.
  const add = async (fromSpaceId: string | null) => {
    const before = new Set(draft.spaces.map((space) => space.spaceId));
    if (!(await run(AddSetupSpace({ fromSpaceId })))) return;
    const added = session.core.state.setupDraft?.spaces.find((space) => !before.has(space.spaceId));
    if (added) onOpenSpace(added.spaceId);
  };
  const menu = (event: MouseEvent, space: SetupDraftSpace) => {
    event.preventDefault();
    const index = primaries.findIndex((primary) => primary.spaceId === space.spaceId);
    const entries: MenuEntry[] = [];
    if (index > 0) entries.push({ title: "Move Up", run: () => void run(MoveSetupSpace({ spaceId: space.spaceId, targetSpaceId: primaries[index - 1].spaceId })) });
    if (index >= 0 && index < primaries.length - 1) {
      entries.push({ title: "Move Down", run: () => void run(MoveSetupSpace({ spaceId: space.spaceId, targetSpaceId: primaries[index + 1].spaceId })) });
    }
    if (space.isNew) entries.push("separator", { title: "Remove Space", run: () => void run(RemoveSetupSpace({ spaceId: space.spaceId })) });
    void showContextMenu(session.shell, event, entries);
  };
  const row = (space: SetupDraftSpace, sub: boolean) => (
    <button key={space.spaceId} type="button" className={`setup-row setup-space-row${sub ? " sub" : ""}`}
      aria-label={sub ? `${space.shownName}, Sub-Space` : space.shownName}
      onClick={() => onOpenSpace(space.spaceId)} onContextMenu={(event) => menu(event, space)}>
      {sub && <Symbol name="arrow.turn.down.right" size={11} strokeWidth={2.5} className="setup-sub-arrow" />}
      <SpaceIdentityIcon symbol={space.customization.symbol} branding={space.customization.branding} size={sub ? 22 : 26} />
      <span className="setup-space-name">{space.shownName}</span>
      <Symbol name="chevron.forward" size={11} strokeWidth={2.5} className="setup-disclosure" />
    </button>
  );
  return (
    <div className="setup-page-content">
      <h2 className="setup-page-heading">Spaces</h2>
      <section className="settings-group">
        <div className="settings-card setup-list">
          {primaries.map((primary) => (
            <Fragment key={primary.spaceId}>
              {row(primary, false)}
              {draft.spaces.filter((space) => space.primaryId === primary.spaceId).map((space) => row(space, true))}
              <span className="setup-list-item">
                <button type="button" className="setup-tertiary setup-add-sub-space" data-testid="setup-add-sub-space"
                  aria-label={`Add a Sub-Space to ${primary.shownName}`} onClick={() => void add(primary.spaceId)}>
                  <Symbol name="plus" size={13} strokeWidth={2.25} />
                  Add Sub-Space
                </button>
              </span>
            </Fragment>
          ))}
        </div>
        <p className="settings-footer">A Sub-Space shares its Space’s sign-ins and history, with tabs and a look of its own.</p>
      </section>
      <section className="settings-group">
        <div className="settings-card setup-list">
          <span className="setup-list-item">
            <button type="button" className="setup-tertiary" data-testid="setup-add-space" onClick={() => void add(null)}>
              <Symbol name="plus" size={13} strokeWidth={2.25} />
              New Space
            </button>
          </span>
        </div>
      </section>
      {error && <p className="setup-error" role="alert">{error}</p>}
    </div>
  );
}
