import {
  BeginDeletingSpace,
  DeleteProfileData,
  FinishDeletingSpace,
  messageOfRejection,
  ReleasePage,
  type SpaceDeletionState,
  type SpaceState,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";

import type { Session } from "../boot";
import { failureNotice, notices } from "../notices";
import { deletion as erasure } from "../shell/site-control";
import { forgetTabIcons } from "../tab-icon-store";

/** A Space the person asked to delete, and whether its Sub-Spaces go with it. */
export interface SpaceDeletionRequest {
  readonly spaceId: string;
  readonly includesSubSpaces: boolean;
}

/**
 * BrowserSpaceDeletionPlan: what deleting a Space removes, as its
 * confirmation says it. A Sub-Space goes alone and leaves its group's
 * session; a primary that leads Sub-Spaces hands its group to the one the
 * person chooses, unless the whole group goes; a Space on its own goes with
 * all of its data.
 */
export interface SpaceDeletionPlan {
  readonly request: SpaceDeletionRequest;
  readonly title: string;
  readonly message: string;
  readonly confirmation: string;
  /** The Sub-Spaces of which one takes the group over: empty unless a primary that leads them goes alone. */
  readonly successors: readonly SpaceState[];
}

/** The Space's group: its primary and the Sub-Spaces that follow it, in order. */
export function groupMembers(space: SpaceState, spaces: readonly SpaceState[]): SpaceState[] {
  const primaryId = space.membership?.primaryId ?? space.id;
  return spaces.filter((candidate) => candidate.id === primaryId || candidate.membership?.primaryId === primaryId);
}

/** Whether `space` is a Sub-Space of another. */
export function isSubSpace(space: SpaceState): boolean {
  const primaryId = space.membership?.primaryId;
  return !!primaryId && primaryId !== space.id;
}

/** The plan for `request` among `spaces`, or null once the Space is gone. */
export function deletionPlan(request: SpaceDeletionRequest, spaces: readonly SpaceState[]): SpaceDeletionPlan | null {
  const space = spaces.find((candidate) => candidate.id === request.spaceId);
  if (!space) return null;
  const name = space.settings.name;
  const subSpaces = groupMembers(space, spaces).filter((member) => member.id !== space.id);
  if (isSubSpace(space)) {
    const primary = spaces.find((candidate) => candidate.id === space.membership?.primaryId);
    return {
      request, title: `Delete “${name}”?`, confirmation: "Delete Sub-Space", successors: [],
      message: `Deletes its tabs. ${primary?.settings.name ?? "Its primary"}’s sign-ins, history, passwords and extensions stay.`,
    };
  }
  if (subSpaces.length === 0) {
    return {
      request, title: `Delete “${name}”?`, confirmation: "Delete Space and Data", successors: [],
      message: "This permanently removes this Space’s browser data from Crest. Downloaded files you already saved are kept.",
    };
  }
  if (request.includesSubSpaces) {
    return {
      request,
      title: subSpaces.length === 1 ? `Delete “${name}” and its Sub-Space?` : `Delete “${name}” and its ${subSpaces.length} Sub-Spaces?`,
      message: "This permanently removes their tabs and browser data from Crest. Downloaded files you already saved are kept.",
      confirmation: "Delete Spaces and Data", successors: [],
    };
  }
  return {
    request, title: `Delete “${name}”?`, confirmation: `Delete ${name}`, successors: subSpaces,
    message: `Choose the Space that keeps ${name}’s sign-ins, history, passwords and pinned tabs.`,
  };
}

/** The Spaces this window is deleting now, which it never starts deleting twice. */
const deleting = new Set<string>();

/** Whether `spaceId` is being deleted, here or by a deletion a launch carries on. */
export function isDeleting(session: Session, spaceId: string): boolean {
  return deleting.has(spaceId)
    || (session.core.state.workspaces.get(session.workspaceId)?.spaceDeletions.some((entry) => entry.spaceId === spaceId) ?? false);
}

/**
 * Deletes what `plan` names, handing a primary's group to `successor` when it
 * goes alone: the whole group's Sub-Spaces first, then its primary. A failure
 * keeps what was not deleted yet and says so in the window, since the page
 * that asked may be gone with the Space.
 */
export async function runDeletion(session: Session, plan: SpaceDeletionPlan, spaces: readonly SpaceState[],
  successor: string | null) {
  const space = spaces.find((candidate) => candidate.id === plan.request.spaceId);
  if (!space) return;
  try {
    if (plan.request.includesSubSpaces) {
      for (const member of groupMembers(space, spaces)) if (member.id !== space.id) await deleteSpace(session, member.id, null);
    }
    await deleteSpace(session, space.id, plan.successors.length === 0 ? null : successor ?? plan.successors[0].id);
  } catch (error) {
    const reason = error instanceof CoreRejection ? messageOfRejection(error.rejection) : error instanceof Error ? error.message : null;
    notices.post(failureNotice(`${reason ?? "Crest couldn’t delete the Space."} The Space was kept so you can try again.`));
  }
}

/**
 * BrowserStore.deleteSpace: the core starts the deletion, which leaves the
 * window showing another Space; the Space's pages here go for good with the
 * icons its tabs wore; every engine erases each profile the deletion erases;
 * then the core lets the Space go. Windows keeps no passwords of its own, so
 * there are none to hand on or delete. Throws why a step failed.
 */
async function deleteSpace(session: Session, spaceId: string, newPrimaryId: string | null) {
  if (deleting.has(spaceId)) return;
  deleting.add(spaceId);
  try {
    const { core, workspaceId, windowId } = session;
    const deletions = () => core.state.workspaces.get(workspaceId)?.spaceDeletions ?? [];
    const operationId = deletions().find((entry) => entry.spaceId === spaceId)?.id ?? crypto.randomUUID();
    const tabIds = core.state.workspaces.get(workspaceId)?.spaces.get(spaceId)?.tabs.map((tab) => tab.id) ?? [];
    await core.send(BeginDeletingSpace({ workspaceId, windowId, spaceId, operationId, newPrimaryId }));
    const deletion = deletions().find((entry) => entry.spaceId === spaceId);
    if (!deletion) throw new Error("The Space was already gone.");
    await releasePages(session, deletion);
    void forgetTabIcons(tabIds);
    const ephemeral = core.state.workspaces.get(workspaceId)?.kind.isPrivate ?? false;
    for (const profileId of deletion.erasing) {
      const requestId = crypto.randomUUID();
      await core.send(DeleteProfileData({ requestId, profileId, ephemeral }));
      if (!(await erasure(core, requestId))) throw new Error("Crest couldn’t erase this Space’s browser data.");
    }
    await core.send(FinishDeletingSpace({ workspaceId, windowId, spaceId, operationId }));
  } finally {
    deleting.delete(spaceId);
  }
}

/** Lets go of this window's pages of the Space `deletion` names, and of every page of a profile it erases. */
async function releasePages(session: Session, deletion: SpaceDeletionState) {
  const erasing = new Set(deletion.erasing);
  const spaces = session.core.state.workspaces.get(session.workspaceId)?.spaces;
  for (const page of [...session.core.state.pages.values()]) {
    const profileId = spaces?.get(page.spaceId)?.profileId;
    if (page.spaceId !== deletion.spaceId && !(profileId && erasing.has(profileId))) continue;
    await session.core.send(ReleasePage({ pageId: page.id, keepsState: false })).catch(() => undefined);
  }
}

/**
 * BrowserStore.resumePendingSpaceDeletions: a launch finishes each deletion
 * the last one began, once each; one that fails again waits for the next.
 */
export async function resumeSpaceDeletions(session: Session) {
  const attempted = new Set<string>();
  for (;;) {
    const pending = session.core.state.workspaces.get(session.workspaceId)?.spaceDeletions
      .find((entry) => !attempted.has(entry.spaceId) && !deleting.has(entry.spaceId));
    if (!pending) return;
    attempted.add(pending.spaceId);
    await deleteSpace(session, pending.spaceId, null).catch(() => undefined);
  }
}
