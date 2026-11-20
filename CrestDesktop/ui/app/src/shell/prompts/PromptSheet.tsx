import {
  AnswerAuthentication,
  AnswerScriptDialog,
  type AuthenticationAsked,
  JavaScriptDialogKind,
  type ScriptDialogAsked,
} from "@crest/contracts";
import type { PagePrompt } from "@crest/core-client";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { type FormEvent, type KeyboardEvent, type ReactNode, useEffect, useRef, useState } from "react";

import type { Session } from "../../boot";
import { authenticationSource, sourceLabel } from "./prompt-text";

/**
 * The question a page asks that holds it until the person answers: a script
 * dialog or a server's sign-in, as a sheet over the page card that keeps the
 * page from input meanwhile, as the Mac's sheets keep its window. The core
 * settles each one however it is answered, and the sheet goes with it.
 */
export function PromptSheet({ session, prompt, spaceName }: {
  session: Session;
  prompt: PagePrompt | null;
  spaceName: string;
}) {
  // An answered question goes at once; the core's settlement follows.
  const [answered, setAnswered] = useState<string | null>(null);
  const shown = prompt && prompt.promptId !== answered && prompt.$kind !== "PermissionAsked" ? prompt : null;
  const settle = (promptId: string, send: () => Promise<unknown>) => {
    setAnswered(promptId);
    void send().catch(() => undefined);
  };
  return (
    <AnimatePresence>
      {shown && (
        <motion.div
          key={shown.promptId}
          className="sheet-backdrop"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={tokens.surface}
        >
          {shown.$kind === "ScriptDialogAsked" ? (
            <ScriptDialog
              asked={shown}
              answer={(accepted, text) =>
                settle(shown.promptId, () =>
                  session.core.send(AnswerScriptDialog({ promptId: shown.promptId, accepted, text })))}
            />
          ) : (
            <SignIn
              asked={shown}
              spaceName={spaceName}
              answer={(credential) =>
                settle(shown.promptId, () =>
                  session.core.send(AnswerAuthentication({ promptId: shown.promptId, credential })))}
            />
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

function ScriptDialog({ asked, answer }: { asked: ScriptDialogAsked; answer: (accepted: boolean, text: string | null) => void }) {
  const { kind, message, defaultText, sourceUrl } = asked.question;
  const [text, setText] = useState(defaultText);
  const source = sourceLabel(sourceUrl);
  switch (kind) {
    case JavaScriptDialogKind.Alert:
      return (
        <Sheet title={`${source} says`} primary="OK" onPrimary={() => answer(true, null)} onEscape={() => answer(true, null)}>
          <p className="sheet-message">{message}</p>
        </Sheet>
      );
    case JavaScriptDialogKind.Confirm:
      return (
        <Sheet title={`${source} says`} primary="OK" secondary="Cancel"
          onPrimary={() => answer(true, null)} onEscape={() => answer(false, null)}>
          <p className="sheet-message">{message}</p>
        </Sheet>
      );
    case JavaScriptDialogKind.Prompt:
      return (
        <Sheet title={`${source} says`} primary="OK" secondary="Cancel"
          onPrimary={() => answer(true, text)} onEscape={() => answer(false, null)}>
          <p className="sheet-message">{message}</p>
          <input className="sheet-field" value={text} onChange={(event) => setText(event.target.value)}
            aria-label={message || "Answer"} data-autofocus />
        </Sheet>
      );
    case JavaScriptDialogKind.BeforeUnload:
      // Pages no longer choose this question's wording, so it names the site
      // rather than repeating the page's text.
      return (
        <Sheet title="Leave this page?" primary="Leave Page" secondary="Stay on Page"
          onPrimary={() => answer(true, null)} onEscape={() => answer(false, null)}>
          <p className="sheet-message">Changes you made on {source} may not be saved.</p>
        </Sheet>
      );
  }
}

/**
 * A server's request for a user name and password. The credential goes to
 * the engine and nowhere else; this build saves no sign-ins yet, so the sheet
 * offers no saving.
 */
function SignIn({ asked, spaceName, answer }: {
  asked: AuthenticationAsked;
  spaceName: string;
  answer: (credential: { username: string; password: string } | null) => void;
}) {
  const { question } = asked;
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const secure = question.url.toLowerCase().startsWith("https:");
  const paragraphs = [
    question.realm ? `Realm: ${question.realm}` : null,
    `This sign-in belongs only to the ${spaceName} Space.`,
    question.previousFailures > 0 ? "The previous credentials were not accepted." : null,
    secure ? null : "Warning: this connection is not protected by HTTPS.",
  ].filter((paragraph): paragraph is string => paragraph !== null);
  return (
    <Sheet title={`Sign in to ${authenticationSource(question)}`} primary="Sign In" secondary="Cancel"
      warning={!secure} onPrimary={() => answer({ username, password })} onEscape={() => answer(null)}>
      {paragraphs.map((paragraph) => <p key={paragraph} className="sheet-message">{paragraph}</p>)}
      <input className="sheet-field" placeholder="Username" aria-label="Username" autoComplete="off"
        value={username} onChange={(event) => setUsername(event.target.value)} data-autofocus />
      <input className="sheet-field" type="password" placeholder="Password" aria-label="Password" autoComplete="off"
        value={password} onChange={(event) => setPassword(event.target.value)} />
    </Sheet>
  );
}

/**
 * A dialog as Windows draws one (ContentDialog): its question above, its
 * buttons across a bar below, the primary one first. Enter answers with the
 * primary button, and Escape as `onEscape` says, which is the second button
 * unless that would go ahead with something the person should choose.
 */
export function Sheet({ title, primary, secondary, warning = false, onPrimary, onSecondary, onEscape, children }: {
  title: string;
  primary: string;
  secondary?: string;
  warning?: boolean;
  onPrimary: () => void;
  onSecondary?: () => void;
  onEscape: () => void;
  children: ReactNode;
}) {
  const onCancel = onEscape;
  const second = onSecondary ?? onEscape;
  const form = useRef<HTMLFormElement>(null);
  useEffect(() => {
    // The page held the keyboard; the question takes it.
    const target = form.current?.querySelector<HTMLElement>("[data-autofocus]")
      ?? form.current?.querySelector<HTMLElement>("button[type=submit]");
    target?.focus();
  }, []);
  const submit = (event: FormEvent) => {
    event.preventDefault();
    onPrimary();
  };
  const escape = (event: KeyboardEvent) => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    onCancel();
  };
  return (
    <motion.div
      className={`sheet${warning ? " warning" : ""}`}
      role="alertdialog"
      aria-modal="true"
      aria-label={title}
      initial={{ opacity: 0, scale: 1.04 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={{ opacity: 0, scale: 0.98 }}
      transition={tokens.floatingPane}
    >
      <form ref={form} onSubmit={submit} onKeyDown={escape}>
        <div className="sheet-body">
          <h2 className="sheet-title">{title}</h2>
          {children}
        </div>
        <div className="sheet-actions">
          <button type="submit" className="sheet-button primary">{primary}</button>
          {secondary && <button type="button" className="sheet-button" onClick={second}>{secondary}</button>}
        </div>
      </form>
    </motion.div>
  );
}
