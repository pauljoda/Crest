import { AnswerPermission, type PermissionAsked } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";

import type { Session } from "../../boot";
import { Symbol } from "../../symbols";
import { originName } from "./prompt-text";

/**
 * A site's request for a permission its Space's choices don't answer, below
 * the address field, as the Mac shows it from its site control. Allow and
 * Deny take the Space's "Remember" choice; dismissing it answers this once
 * and never saves a denial.
 */
export function PermissionPrompt({ session, asked, spaceName }: {
  session: Session;
  asked: PermissionAsked | null;
  spaceName: string;
}) {
  const [answered, setAnswered] = useState<string | null>(null);
  const [remembers, setRemembers] = useState(true);
  useEffect(() => setRemembers(true), [asked?.promptId]);
  const shown = asked && asked.promptId !== answered ? asked : null;
  const answer = (grants: boolean, remembered: boolean) => {
    if (!shown) return;
    setAnswered(shown.promptId);
    void session.core.send(AnswerPermission({ promptId: shown.promptId, grants, remembers: remembered })).catch(() => undefined);
  };
  return (
    <AnimatePresence>
      {shown && (
        <motion.div
          key={shown.promptId}
          className="permission-prompt"
          role="dialog"
          aria-label={`${originName(shown.question.origin)} ${shown.question.permission.requestTitle}`}
          initial={{ opacity: 0, y: -6, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -4, scale: 0.98 }}
          transition={tokens.floatingPane}
          onKeyDown={(event) => event.key === "Escape" && answer(false, false)}
        >
          <div className="permission-heading">
            <Symbol name={shown.question.permission.symbol} size={20} className="permission-symbol" />
            <div className="permission-text">
              <span className="permission-origin">{originName(shown.question.origin)}</span>
              <span className="permission-request">{shown.question.permission.requestTitle}</span>
              {originName(shown.question.origin) !== originName(shown.question.topLevelOrigin) && (
                <span className="permission-inside">Inside {originName(shown.question.topLevelOrigin)}</span>
              )}
            </div>
            <button className="permission-dismiss" aria-label="Dismiss Permission Request" title="Dismiss"
              onClick={() => answer(false, false)}>
              <Symbol name="xmark" size={13} />
            </button>
          </div>
          <label className="permission-remember">
            <input type="checkbox" checked={remembers} onChange={(event) => setRemembers(event.target.checked)} />
            Remember in {spaceName}
          </label>
          <div className="permission-actions">
            {/* Nothing is focused, so a key meant for the page never grants. */}
            <button className="permission-button primary" onClick={() => answer(true, remembers)}>Allow</button>
            <button className="permission-button" onClick={() => answer(false, remembers)}>Deny</button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
