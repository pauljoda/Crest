import type { DownloadApprovalAsked } from "@crest/contracts";
import type { ShellTransport } from "@crest/core-client";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { useState } from "react";

import type { Downloads } from "../../downloads";
import { useShellFrame } from "../WindowControls";
import { Sheet } from "./PromptSheet";

/**
 * Whether to go on with a download the core judged dangerous before its file
 * has a place, or to keep one its engine warned about while it downloaded,
 * as the Mac asks it: the core's reasons, the engine's warning, where it came
 * from and the Space it belongs to. The window in use asks; keeping a file
 * the engine warned about is never the default, and Escape never downloads.
 */
export function DownloadApproval({ shell, downloads, asked, spaceName }: {
  shell: ShellTransport;
  downloads: Downloads;
  asked: DownloadApprovalAsked | null;
  spaceName: (spaceId: string | null) => string | null;
}) {
  const frame = useShellFrame(shell);
  const [answered, setAnswered] = useState<string | null>(null);
  const shown = asked && frame.active && asked.promptId !== answered ? asked : null;
  const answer = (approved: boolean) => {
    if (!shown) return;
    setAnswered(shown.promptId);
    downloads.approve(shown.promptId, approved);
  };
  return (
    <AnimatePresence>
      {shown && (
        <motion.div key={shown.promptId} className="sheet-backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }}
          exit={{ opacity: 0 }} transition={tokens.surface}>
          <Question asked={shown} space={spaceName(shown.spaceId)} answer={answer} />
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function Question({ asked, space, answer }: { asked: DownloadApprovalAsked; space: string | null; answer: (approved: boolean) => void }) {
  const keeps = asked.warning !== null;
  const origin = [asked.sourceHost && `Source: ${asked.sourceHost}`, space && `Space: ${space}`].filter(Boolean).join(" · ");
  const paragraphs = [
    ...asked.reasons.map((reason) => reason.message),
    ...(asked.warning ? [asked.warning.approvalMessage] : []),
    ...(origin ? [origin] : []),
    ...(keeps ? [] : ["Windows marks the finished file as downloaded from the internet. Open it only if you trust its source."]),
  ];
  const body = paragraphs.map((paragraph) => <p key={paragraph} className="sheet-message">{paragraph}</p>);
  return keeps ? (
    <Sheet title={`Keep “${asked.filename}”?`} warning primary="Cancel" secondary="Keep Download"
      onPrimary={() => answer(false)} onSecondary={() => answer(true)} onEscape={() => answer(false)}>
      {body}
    </Sheet>
  ) : (
    <Sheet title={`Download “${asked.filename}”?`} warning primary="Download" secondary="Cancel"
      onPrimary={() => answer(true)} onEscape={() => answer(false)}>
      {body}
    </Sheet>
  );
}
