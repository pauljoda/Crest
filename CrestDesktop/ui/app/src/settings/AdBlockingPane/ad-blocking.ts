import type { Intent } from "@crest/contracts";

import type { Session } from "../../boot";

/** Sends `intent`, answering whether the core took it. */
export function send(session: Session, intent: Intent) {
  return session.core.send(intent).then(() => true, () => false);
}
