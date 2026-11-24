import type { CoreState } from "@crest/core-client";

import type { Session } from "./boot";
import { reader } from "./reactive";

const coreReaders = new WeakMap<Session, () => number>();
const engineReaders = new WeakMap<Session, () => number>();

/**
 * The read model's version, which follows every batch the core publishes:
 * read inside a `$derived`, an `$effect` or a template expression, that
 * expression runs again after each batch. An expression that reads the read
 * model, itself or through a helper, reads this first, as
 * `$derived.by(() => (useCoreVersion(session), session.core.state.pages.get(id)))`.
 */
export function useCoreVersion(session: Session): number {
  let read = coreReaders.get(session);
  if (!read) {
    read = reader((listener) => session.core.state.subscribe(listener), () => session.core.state.version);
    coreReaders.set(session, read);
  }
  return read();
}

/**
 * The read model, followed as `useCoreVersion` follows it. Its maps change
 * in place, so derive what is read from it: a record keeps its identity
 * until the core replaces it, and a derived record moves only then.
 */
export function coreState(session: Session): CoreState {
  useCoreVersion(session);
  return session.core.state;
}

/** The development engine's frames' version, followed as `useCoreVersion` follows the core's. */
export function useEngineVersion(session: Session): number {
  let read = engineReaders.get(session);
  if (!read) {
    read = reader((listener) => session.engine?.subscribe(listener) ?? (() => {}), () => session.engine?.version ?? 0);
    engineReaders.set(session, read);
  }
  return read();
}
