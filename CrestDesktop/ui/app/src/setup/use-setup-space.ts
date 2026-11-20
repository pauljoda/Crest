import {
  CustomizeSetupSpace,
  messageOfRejection,
  type SetupDraftSpace,
  type SpaceCustomization,
} from "@crest/contracts";
import { CoreRejection } from "@crest/core-client";
import { useCallback, useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { useCoreVersion } from "../use-core";

/** What the person is told of a refusal whose rule says nothing of its own, as the Mac's Rejection.unexplained. */
export const unexplained = "Crest couldn’t complete that. Try again.";

/** A refusal in the core's own words, or the Mac's fallback. */
export function explanation(error: unknown): string {
  return error instanceof CoreRejection ? messageOfRejection(error.rejection) ?? unexplained : unexplained;
}

/**
 * The draft Space `spaceId` that a Setup page edits, as the Mac's
 * BrowserManualSetupModel.customize sends it: every change carries the whole
 * customization, name, symbol, accent and look. Changes show at once and
 * reach the core at most once a frame, the newest each time, so a drag on a
 * color wheel or a name typed fast never queues behind itself.
 */
export function useSetupSpace(session: Session, spaceId: string | null) {
  useCoreVersion(session);
  const space: SetupDraftSpace | null = session.core.state.setupDraft?.spaces.find((each) => each.spaceId === spaceId) ?? null;
  const [local, setLocal] = useState<SpaceCustomization | null>(null);
  const [error, setError] = useState<string | null>(null);
  const latest = useRef<SpaceCustomization | null>(null);
  const frame = useRef<number | null>(null);
  const sending = useRef(0);

  // Another Space's page starts from that Space.
  useEffect(() => {
    latest.current = null;
    setLocal(null);
  }, [spaceId]);

  const send = useCallback(() => {
    frame.current = null;
    const customization = latest.current;
    if (!customization || !spaceId) return;
    const ticket = ++sending.current;
    session.core.send(CustomizeSetupSpace({ spaceId, customization })).then(() => {
      setError(null);
      // The core's draft holds it now, unless the person changed it again since.
      if (ticket === sending.current && frame.current === null) {
        latest.current = null;
        setLocal(null);
      }
    }, (failure: unknown) => setError(explanation(failure)));
  }, [session, spaceId]);

  useEffect(() => () => {
    if (frame.current !== null) {
      cancelAnimationFrame(frame.current);
      send();
    }
  }, [send]);

  const customization = local ?? space?.customization ?? null;

  /** The Space with `change` made to its newest customization. */
  const customize = useCallback((change: (current: SpaceCustomization) => SpaceCustomization) => {
    const base = latest.current ?? local ?? space?.customization;
    if (!base) return;
    const next = change(base);
    latest.current = next;
    setLocal(next);
    if (frame.current === null) frame.current = requestAnimationFrame(send);
  }, [local, space, send]);

  return { space, customization, customize, error };
}
