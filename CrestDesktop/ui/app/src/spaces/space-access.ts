import {
  BeginUnlockingSpace,
  FinishUnlockingSpace,
  LockAllSpaces,
  LockSpace,
  SetSpaceAccess,
  SpaceAccessPolicy,
  type SpaceState,
} from "@crest/contracts";
import { type CrestCore, CoreRejection } from "@crest/core-client";
import { useSyncExternalStore } from "react";

import type { Session } from "../boot";
import { failureNotice, notices } from "../notices";

/**
 * Why the last unlock didn't happen, which the locked Space's view says
 * under its button, as the Mac's BrowserSpaceAccessFailure: the person
 * wasn't verified, or verifying couldn't run.
 */
export type SpaceAccessFailure = "denied" | "unavailable";

export const failureMessages: Readonly<Record<SpaceAccessFailure, string>> = {
  denied: "Authentication failed. Try again.",
  unavailable: "Authentication didn’t complete. Try again.",
};

let failure: SpaceAccessFailure | null = null;
const listeners = new Set<() => void>();
function setFailure(next: SpaceAccessFailure | null) {
  if (next === failure) return;
  failure = next;
  for (const listener of listeners) listener();
}

/** Why the last unlock failed, for the views that say so. */
export function useAccessFailure(): SpaceAccessFailure | null {
  return useSyncExternalStore((listener) => {
    listeners.add(listener);
    return () => listeners.delete(listener);
  }, () => failure);
}

/**
 * BrowserSpaceAccessController.isLocked: a Space that asks for authentication
 * shows only while this process holds the grant for it.
 */
export function isLocked(core: CrestCore, space: SpaceState): boolean {
  return space.settings.requiresAuthentication && core.state.spaceAccess.get(space.id)?.isUnlocked !== true;
}

/** Whether a request to unlock `spaceId` waits on the device's owner now. */
export function isAuthenticating(core: CrestCore, spaceId?: string): boolean {
  if (spaceId) return core.state.spaceAccess.get(spaceId)?.isAuthenticating === true;
  return [...core.state.spaceAccess.values()].some((access) => access.isAuthenticating);
}

/**
 * Asks the device's owner to unlock `space`, answering whether it is
 * unlocked afterwards. The core keeps the one request that may wait; only its
 * own answer unlocks the Space, so a lock while Windows Hello is up keeps it
 * locked. Windows Hello stands in for the Mac's LocalAuthentication.
 */
export async function unlockSpace(session: Session, space: SpaceState): Promise<boolean> {
  const { core } = session;
  if (!isLocked(core, space)) return true;
  if (!session.shell) {
    setFailure("unavailable");
    return false;
  }
  const requestId = crypto.randomUUID();
  try {
    await core.send(BeginUnlockingSpace({ workspaceId: session.workspaceId, spaceId: space.id, requestId }));
  } catch (error) {
    if (error instanceof CoreRejection && error.rejection.$kind === "AuthenticationBusy") return false;
    setFailure("unavailable");
    return false;
  }
  if (!isAuthenticating(core, space.id)) return core.state.spaceAccess.get(space.id)?.isUnlocked === true;
  setFailure(null);
  const verification = await session.shell.verifyOwner(`Authenticate to unlock the ${space.settings.name} Space in Crest.`);
  const authenticated = verification === "verified";
  const answered = await core.send(FinishUnlockingSpace({ spaceId: space.id, requestId, authenticated }))
    .then(() => true, () => false);
  if (!answered) {
    if (authenticated) notices.post(failureNotice(`“${space.settings.name}” locked again. Try again.`));
    return false;
  }
  if (!authenticated) {
    setFailure(verification === "unavailable" ? "unavailable" : "denied");
    return false;
  }
  return true;
}

/**
 * BrowserSpaceAccessController.updatePolicy: Lock Space turns the device
 * owner's authentication on, which locks the Space and its group at once;
 * turning it off asks the owner first. A change the core refuses is said in
 * the window, and the Space keeps the access it had.
 */
export async function setSpaceLock(session: Session, space: SpaceState, locks: boolean): Promise<boolean> {
  if (!locks && !(await unlockSpace(session, space))) return false;
  try {
    await session.core.send(SetSpaceAccess({
      workspaceId: session.workspaceId, spaceId: space.id,
      policy: locks ? SpaceAccessPolicy.DeviceOwnerAuthentication : SpaceAccessPolicy.Open,
    }));
  } catch {
    notices.post(failureNotice(`Couldn’t change the lock on “${space.settings.name}”`));
    return false;
  }
  if (locks) await session.core.send(LockSpace({ spaceId: space.id })).catch(() => undefined);
  return true;
}

/**
 * Locks every Space that asks for authentication, as the Mac does once Crest
 * stops being the app in front. While an unlock waits on Windows Hello, which
 * takes the foreground itself, nothing locks.
 */
export function lockAllSpaces(core: CrestCore) {
  void core.send(LockAllSpaces({ sceneWentInactive: true })).catch(() => undefined);
}

/** How long a window that stopped being active waits to hear that another Crest window became active. */
const handOver = 300;

/**
 * Locks Spaces once Crest as a whole stops being in front, as the Mac's
 * window scene does when the app resigns active. Each window says on a
 * channel the others hear when it becomes active, so moving between Crest's
 * own windows locks nothing; a window that stops being active locks once no
 * other has become active by then. Answers the call that stops.
 */
export function lockWhenCrestInactive(session: Session): () => void {
  const shell = session.shell;
  if (!shell || typeof BroadcastChannel === "undefined") return () => {};
  const channel = new BroadcastChannel("crest-window-activity");
  let lastActive = performance.timeOrigin + performance.now();
  let wasActive = shell.frame.active;
  let timer = 0;
  channel.onmessage = (event: MessageEvent<{ readonly active: boolean; readonly at: number }>) => {
    if (event.data.active) lastActive = Math.max(lastActive, event.data.at);
  };
  const stop = shell.subscribeFrame(() => {
    const active = shell.frame.active;
    if (active === wasActive) return;
    wasActive = active;
    const at = performance.timeOrigin + performance.now();
    if (active) {
      lastActive = at;
      clearTimeout(timer);
      channel.postMessage({ active: true, at });
      return;
    }
    clearTimeout(timer);
    timer = window.setTimeout(() => {
      if (!shell.frame.active && lastActive <= at) lockAllSpaces(session.core);
    }, handOver);
  });
  return () => {
    stop();
    clearTimeout(timer);
    channel.close();
  };
}
