import { useSyncExternalStore } from "react";

import type { Session } from "./boot";

/** Re-renders when the core publishes a batch, and answers the read model's version. */
export function useCoreVersion(session: Session): number {
  return useSyncExternalStore(
    (listener) => session.core.state.subscribe(listener),
    () => session.core.state.version,
  );
}

/** Re-renders when the development engine's frames change. */
export function useEngineVersion(session: Session): number {
  return useSyncExternalStore(
    (listener) => session.engine?.subscribe(listener) ?? (() => {}),
    () => session.engine?.version ?? 0,
  );
}
