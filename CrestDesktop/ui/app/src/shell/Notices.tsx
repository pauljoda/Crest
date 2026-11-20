import type { ShellTransport } from "@crest/core-client";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useEffect, useRef, useState } from "react";

import { noticeDuration, notices, type WindowNotice } from "../notices";
import { Symbol } from "../symbols";

interface ShownNotice extends WindowNotice {
  readonly id: number;
}

/**
 * What the shell reports in Chromium's name: what a feature Crest does not
 * offer here would have shown (UnavailableFeature in crest_desktop_host.h, in
 * its order), with the Mac's own words for each.
 */
const unavailable: readonly (readonly [message: string, symbol: string])[] = [
  ["Autofill is not connected in Crest yet.", "person"],
  ["Payment autofill is not available in Crest yet.", "creditcard"],
  ["Address autofill is not available in Crest yet.", "person.text.rectangle"],
  ["Autofill with AI is not available in Crest yet.", "sparkles"],
  ["Profiles are not available in Crest yet.", "person.crop.circle"],
  ["The eye dropper is not available in Crest yet.", "eyedropper"],
  ["Caret browsing is not available in Crest yet.", "text.cursor"],
  ["This private browsing option is not available in Crest yet.", "eye.slash"],
  ["Chrome Labs is not available in Crest.", "flask"],
  ["Translating a selection is not available in Crest yet.", "translate"],
];
const fallback = ["This is not available in Crest yet.", "info.circle"] as const;

/**
 * The window's notices, as the Mac's BrowserNoticeLayer shows them: one at a
 * time in the top trailing corner of the page, a newer one replacing one
 * still showing, each going by itself once it has been up long enough to
 * read.
 */
export function Notices({ shell }: { shell: ShellTransport | null }) {
  const [notice, setNotice] = useState<ShownNotice | null>(null);
  const next = useRef(0);
  const reducesMotion = useReducedMotion();
  useEffect(() => {
    const show = (shown: WindowNotice) => setNotice({ ...shown, id: ++next.current });
    const stop = notices.subscribe((event) => {
      if ("shows" in event) show(event.shows);
      else setNotice((current) => (current?.key === event.dismisses ? null : current));
    });
    if (!shell) return stop;
    shell.onNotice = (message, kind) => show({ message, symbol: kind === "link" ? "link" : "checkmark.circle.fill" });
    shell.onUnavailable = (feature) => {
      const [message, symbol] = unavailable[feature] ?? fallback;
      show({ message, symbol });
    };
    return () => {
      stop();
      shell.onNotice = undefined;
      shell.onUnavailable = undefined;
    };
  }, [shell]);
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice((current) => (current?.id === notice.id ? null : current)),
      noticeDuration(notice.message));
    return () => clearTimeout(timer);
  }, [notice]);
  return (
    <div className="notices" role="status" aria-live="polite">
      <AnimatePresence>
        {notice && (
          <motion.div
            key={notice.id}
            className="notice"
            initial={reducesMotion ? { opacity: 0 } : { opacity: 0, y: -12 }}
            animate={{ opacity: 1, y: 0, transition: tokens.feedbackPresentation }}
            exit={reducesMotion ? { opacity: 0 } : { opacity: 0, y: -12, transition: tokens.dismissal }}
          >
            <Symbol name={notice.symbol} size={15} />
            <span aria-label={notice.accessibilityLabel}>{notice.message}</span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
