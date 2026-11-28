import {
  AdoptLinkPreferences,
  type AppPreferences,
  AppPreferencesStatics,
  type Intent,
  type LinkBehavior,
  type LinkPreferences,
  SetAppPreferences,
  SetLinkBehavior,
} from "@crest/contracts";
import { untrack } from "svelte";

import type { Session } from "../boot";
import { coreState } from "../use-core";

/** Sends `intent`; a refusal leaves the setting as it was. */
export function send(session: Session, intent: Intent) {
  void session.core.send(intent).catch(() => {});
}

export const defaults = AppPreferencesStatics.default;

/** The app's preferences, followed by the expression that reads them. */
export function appPreferences(session: Session): AppPreferences {
  return coreState(session).workspaces.get(session.workspaceId)?.appPreferences ?? AppPreferencesStatics.default;
}

/** The record last sent for a session while the core hasn't answered it, so a change made meanwhile builds on it. */
const unanswered = new WeakMap<Session, AppPreferences>();

/**
 * Changes the app's preferences, which sends the whole record, as the Mac's
 * store does. `change` may read the preferences it changes, which include a
 * change still on its way, so a quick second one never undoes the first.
 */
export function setAppPreferences(
  session: Session,
  change: Partial<AppPreferences> | ((current: AppPreferences) => Partial<AppPreferences>),
) {
  const current = unanswered.get(session) ?? untrack(() => appPreferences(session));
  const preferences = { ...current, ...(typeof change === "function" ? change(current) : change) };
  unanswered.set(session, preferences);
  void session.core.send(SetAppPreferences({ workspaceId: session.workspaceId, preferences })).catch(() => {}).finally(() => {
    if (unanswered.get(session) === preferences) unanswered.delete(session);
  });
}

/** The device's link preferences, which the core publishes once asked. Call during initialization. */
export function useLinkPreferences(session: () => Session): {
  readonly current: LinkPreferences | null;
  readonly setBehavior: (behavior: LinkBehavior, isOn: boolean) => void;
} {
  const links = $derived(coreState(session()).links);
  $effect(() => {
    if (!links) untrack(() => send(session(), AdoptLinkPreferences({ preferences: null })));
  });
  return {
    get current() {
      return links;
    },
    setBehavior: (behavior, isOn) => send(session(), SetLinkBehavior({ behavior, isOn })),
  };
}
