import { AddSubSpace, type Intent, JoinSpace, messageOfRejection, SeparateSpace, type SpaceState } from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";

import type { Session } from "../boot";
import { spaceEditing } from "../commands";
import { failureNotice, notices } from "../notices";
import { unlockSpace } from "./space-access";
import { groupMembers, isDeleting, isSubSpace } from "./space-deletion";

/**
 * BrowserSpaceGroupChange: a change to a Space's group that the person
 * confirms first, making a Space a Sub-Space of another group or separating
 * a Sub-Space from its own. It carries what the confirmation says, the
 * Spaces the device's owner unlocks before it runs, and the intent the core
 * applies.
 */
export interface SpaceGroupChange {
  readonly spaceId: string;
  /** Both sides of a join, since a join may raise or share protection; the Sub-Space a separation takes out. */
  readonly unlocking: readonly SpaceState[];
  readonly title: string;
  readonly message: string;
  readonly confirmation: string;
  /** Whether the change puts a Space into a group, which builds that predate Sub-Spaces show on its own. */
  readonly formsGroup: boolean;
  readonly intent: Intent;
}

function isPrivate(session: Session): boolean {
  return session.core.state.workspaces.get(session.workspaceId)?.kind.isPrivate ?? false;
}

/** The primary of `space`'s group: the Space whose session the group shares. */
export function primaryOf(space: SpaceState, spaces: readonly SpaceState[]): SpaceState {
  return spaces.find((candidate) => candidate.id === space.membership?.primaryId) ?? space;
}

/** Whether `space` leads a group: a primary with Sub-Spaces. */
export function leadsGroup(space: SpaceState, spaces: readonly SpaceState[]): boolean {
  return groupMembers(space, spaces).length > 1 && primaryOf(space, spaces).id === space.id;
}

/**
 * Whether `space` may become a Sub-Space of another group: a Space on its
 * own, or a Sub-Space, but never a primary, which owns its session.
 */
export function canJoinGroup(session: Session, space: SpaceState, spaces: readonly SpaceState[]): boolean {
  return !isPrivate(session) && !leadsGroup(space, spaces) && (isSubSpace(space) || !space.membership?.sharedProfileId);
}

/** The groups `space` may join, by the Space each is shown as, its primary: every other group of the workspace. */
export function joinableGroups(session: Session, space: SpaceState, spaces: readonly SpaceState[]): SpaceState[] {
  const own = primaryOf(space, spaces).id;
  return spaces.filter((candidate) => !isDeleting(session, candidate.id) && !isSubSpace(candidate)
    && candidate.id !== own && candidate.id !== space.id);
}

/** Makes `space` a Sub-Space of the group `group` belongs to, which keeps its session; null where it may not join. */
export function joining(session: Session, space: SpaceState, group: SpaceState, spaces: readonly SpaceState[]): SpaceGroupChange | null {
  const target = primaryOf(group, spaces);
  if (!canJoinGroup(session, space, spaces) || target.id === primaryOf(space, spaces).id) return null;
  const name = space.settings.name;
  const targetName = target.settings.name;
  return {
    spaceId: space.id, unlocking: [space, target], formsGroup: true, confirmation: "Make Sub-Space",
    title: `Make “${name}” a Sub-Space of “${targetName}”?`,
    message: `${name} will use ${targetName}’s sign-ins, history and extensions. Its own sign-ins and website data stay on this device and come back if you separate it.`,
    intent: JoinSpace({ workspaceId: session.workspaceId, spaceId: space.id, groupSpaceId: target.id }),
  };
}

/** Separates the Sub-Space `space` from its group; null for a Space that isn't one. */
export function separating(session: Session, space: SpaceState, spaces: readonly SpaceState[]): SpaceGroupChange | null {
  if (!isSubSpace(space)) return null;
  const name = space.settings.name;
  return {
    spaceId: space.id, unlocking: [space], formsGroup: false, confirmation: "Separate",
    title: `Separate “${name}” from “${primaryOf(space, spaces).settings.name}”?`,
    message: `${name} will use sign-ins and extensions of its own. It keeps its tabs.`,
    intent: SeparateSpace({ workspaceId: session.workspaceId, spaceId: space.id }),
  };
}

/**
 * Runs a confirmed change: unlocks the Spaces it names, then has the core
 * apply it. A refusal or a failed unlock leaves the groups as they were, a
 * refusal saying why; the first group a device forms reminds the person to
 * update Crest elsewhere.
 */
export async function applyGroupChange(session: Session, change: SpaceGroupChange) {
  for (const space of change.unlocking) {
    if (!(await unlockSpace(session, space))) return;
  }
  try {
    await session.core.send(change.intent);
    if (change.formsGroup) showUpdateNoticeIfDue();
  } catch (error) {
    const reason = error instanceof CoreRejection ? messageOfRejection(error.rejection) : null;
    notices.post(failureNotice(reason ?? "Crest couldn’t change the Space’s group."));
  }
}

/**
 * Starts a Sub-Space after `fromSpaceId`, which shares its sign-ins; the
 * window shows it and Settings opens its page, as the Mac's does.
 */
export async function addSubSpace(session: Session, fromSpaceId: string) {
  const spaceId = crypto.randomUUID();
  try {
    await session.core.send(AddSubSpace({ workspaceId: session.workspaceId, windowId: session.windowId, spaceId, fromSpaceId }));
  } catch (error) {
    const reason = error instanceof CoreRejection ? messageOfRejection(error.rejection) : null;
    notices.post(failureNotice(reason ?? "Crest couldn’t add the Sub-Space."));
    return;
  }
  showUpdateNoticeIfDue();
  spaceEditing.open(spaceId);
}

/** Whether `space` can start a Sub-Space: outside a private window, while it isn't being deleted. */
export function offersSubSpace(session: Session, space: SpaceState): boolean {
  return !isPrivate(session) && !isDeleting(session, space.id);
}

const updateNoticeShown = "crest.subSpaces.updateNoticeShown";

/**
 * BrowserSpaceGroupUpdateNotice: the first group a device forms says, once,
 * that builds that predate Sub-Spaces show each Sub-Space on its own,
 * signed out, until they update.
 */
export function showUpdateNoticeIfDue() {
  try {
    if (localStorage.getItem(updateNoticeShown)) return;
    localStorage.setItem(updateNoticeShown, "1");
  } catch {
    return;
  }
  notices.post({ message: "Update Crest on your other devices to share sign-ins there.", symbol: "arrow.down.circle" });
}
