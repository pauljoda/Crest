import {
  CustomizeSetupSpace,
  messageOfRejection,
  type SetupDraftSpace,
  type SpaceCustomization,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { untrack } from "svelte";

import type { Session } from "../boot";
import { useCoreVersion } from "../use-core";

/** What the person is told of a refusal whose rule says nothing of its own, as the Mac's Rejection.unexplained. */
export const unexplained = "Crest couldn’t complete that. Try again.";

/** A refusal in the core's own words, or the Mac's fallback. */
export function explanation(error: unknown): string {
  return error instanceof CoreRejection ? messageOfRejection(error.rejection) ?? unexplained : unexplained;
}

/** The draft Space a Setup page edits, as `useSetupSpace` answers it. */
export interface SetupSpace {
  readonly space: SetupDraftSpace | null;
  /** The customization the page shows: the person's newest change, or the draft's. */
  readonly customization: SpaceCustomization | null;
  /** The Space with `change` made to its newest customization. */
  readonly customize: (change: (current: SpaceCustomization) => SpaceCustomization) => void;
  readonly error: string | null;
}

/**
 * The draft Space `spaceId` that a Setup page edits, as the Mac's
 * BrowserManualSetupModel.customize sends it: every change carries the whole
 * customization, name, symbol, accent and look. Changes show at once and
 * reach the core at most once a frame, the newest each time, so a drag on a
 * color wheel or a name typed fast never queues behind itself.
 *
 * `const setup = useSetupSpace(session, () => spaceId)`, then `setup.current`.
 * Call during a component's initialization.
 */
export function useSetupSpace(session: Session, spaceId: () => string | null): { readonly current: SetupSpace } {
  const space = $derived.by(() => {
    useCoreVersion(session);
    const id = spaceId();
    return session.core.state.setupDraft?.spaces.find((each) => each.spaceId === id) ?? null;
  });
  let local = $state.raw<SpaceCustomization | null>(null);
  let error = $state<string | null>(null);
  let latest: SpaceCustomization | null = null;
  let frame: number | null = null;
  let sending = 0;

  const send = (id: string | null) => {
    frame = null;
    const customization = latest;
    if (!customization || !id) return;
    const ticket = ++sending;
    session.core.send(CustomizeSetupSpace({ spaceId: id, customization })).then(() => {
      error = null;
      // The core's draft holds it now, unless the person changed it again since.
      if (ticket === sending && frame === null) {
        latest = null;
        local = null;
      }
    }, (failure: unknown) => {
      error = explanation(failure);
    });
  };

  // Another Space's page starts from that Space, once what is pending for
  // the last one has gone to it.
  $effect(() => {
    const id = spaceId();
    untrack(() => {
      latest = null;
      local = null;
    });
    return () => {
      if (frame !== null) {
        cancelAnimationFrame(frame);
        send(id);
      }
    };
  });

  const customization = $derived(local ?? space?.customization ?? null);

  /** The Space with `change` made to its newest customization. */
  const customize = (change: (current: SpaceCustomization) => SpaceCustomization) => {
    const base = latest ?? local ?? space?.customization;
    if (!base) return;
    const next = change(base);
    latest = next;
    local = next;
    const id = spaceId();
    if (frame === null) frame = requestAnimationFrame(() => send(id));
  };

  const current = $derived<SetupSpace>({ space, customization, customize, error });
  return {
    get current() {
      return current;
    },
  };
}
