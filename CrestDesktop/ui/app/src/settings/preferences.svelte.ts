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

/** Changes the app's preferences, which sends the whole record, as the Mac's store does. */
export function setAppPreferences(session: Session, change: Partial<AppPreferences>) {
  send(session, SetAppPreferences({ workspaceId: session.workspaceId, preferences: { ...appPreferences(session), ...change } }));
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
