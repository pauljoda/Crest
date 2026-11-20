import type { SpaceState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { motion, type Variants } from "motion/react";
import { type CSSProperties, useEffect, useRef, useState } from "react";

import type { Session } from "../boot";
import { backgroundColor, css, toneOver } from "../branding";
import { showContextMenu } from "../menus";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";
import { pageContentId } from "./PageCard";

/** A Peek the window shows: a page the core opened for a link, over the page that followed it. */
export interface Peek {
  /** The Peek's own page, transient until it is kept as a tab. */
  readonly pageId: string;
  readonly sourcePageId: string;
  readonly sourceTabId: string;
  /** The Space the link was followed in, which Open In keeps the page in. */
  readonly spaceId: string;
  readonly url: string;
}

/**
 * The Mac's Peek in its pointer arrangement: the Space's page area dimmed,
 * and over it, inset by 24, the action bar above a card holding the Peek's
 * page. The card grows out of where the link was, the middle of the page
 * area here since the page keeps where it was pressed to itself, and goes
 * back into it as it closes. Clicking outside the card closes it; Open In
 * keeps its page as a tab of the Space it came from, or of another Space
 * its menu names.
 */
export function PeekLayer({ session, peek, spaces, hidden, onClose, onOpenIn }: {
  session: Session;
  peek: Peek;
  spaces: readonly SpaceState[];
  /** Whether the Peek waits unseen while the window shows another tab than its link's. */
  hidden: boolean;
  onClose: () => void;
  onOpenIn: (spaceId: string) => void;
}) {
  useCoreVersion(session);
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const space = spaces.find((candidate) => candidate.id === peek.spaceId) ?? null;
  const page = session.core.state.pages.get(peek.pageId);
  // The page shows once it has committed something, a moment after, as the Mac's reveal does.
  const committed = !!page?.live.url;
  const tint = space ? backgroundColor(space.settings.look) : null;
  const menu = useRef<HTMLButtonElement>(null);
  return (
    <div className={`peek-layer${hidden ? " hidden" : ""}`} inert={hidden} aria-hidden={hidden || undefined}>
      <motion.div className="peek-scrim" aria-hidden onClick={onClose}
        initial={reduce ? false : { opacity: 0 }} animate={{ opacity: 1 }} variants={scrimVariants} exit="gone"
        transition={reduce ? { duration: 0 } : tokens.floatingPane} />
      <motion.div className="peek-stack" role="dialog" aria-label={`Peek from ${sourceTitle(session, peek)}`}
        // A whole transform runs on the compositor, so the page loading beneath doesn't hold it up.
        initial={reduce ? false : { transform: "scale(0.08)", opacity: 1 }} animate={{ transform: "scale(1)", opacity: 1 }}
        variants={stackVariants} exit="gone" transition={reduce ? { duration: 0 } : peekSpring}>
        <div className="peek-bar">
          <button className="peek-close" aria-label="Close Peek" title="Close Peek (Esc or Ctrl+W)" onClick={onClose}>
            <Symbol name="xmark" size={18} strokeWidth={2.4} />
          </button>
          <div className={`peek-destination${tint && toneOver(tint) === "light" ? " reads-light" : ""}`}
            style={tint ? ({ "--peek-tint": css(tint, 0.72) } as CSSProperties) : undefined}>
            <button className="peek-open-in" aria-label="Open In…" aria-description={space?.settings.name ?? "Space"}
              title={`Open in ${space?.settings.name ?? "Space"}`} onClick={() => onOpenIn(peek.spaceId)}>
              {space ? <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={22} />
                : <Symbol name="square.grid.2x2" size={18} />}
              <span>Open In…</span>
            </button>
            <span className="peek-destination-separator" aria-hidden />
            <button ref={menu} className="peek-destination-menu" aria-label="Choose Destination Space"
              aria-description={space?.settings.name ?? "Space"} title="Open in another Space"
              onClick={() => {
                const bounds = menu.current?.getBoundingClientRect();
                if (!bounds) return;
                void showContextMenu(session.shell, { clientX: bounds.left, clientY: bounds.bottom },
                  spaces.map((candidate) => ({ title: candidate.settings.name, run: () => onOpenIn(candidate.id) })));
              }}>
              <Symbol name="chevron.down" size={11} strokeWidth={2.6} />
            </button>
          </div>
        </div>
        <div className="peek-card">
          <PeekPage session={session} pageId={peek.pageId} shown={committed} reduce={reduce} />
        </div>
      </motion.div>
    </div>
  );
}

/**
 * The Mac's spring for a Peek coming out of its link and going back into it,
 * at its Peek animation time's default, 240 ms (BrowserPeekPace).
 */
const peekSpring = { type: "spring", visualDuration: 0.24, bounce: 0.16 } as const;

/**
 * Going back into the link, unless the Peek was kept as a tab, which leaves
 * at once: the card shrinks to nothing as it fades, gone by just over half
 * its way back.
 */
const stackVariants: Variants = {
  gone: (animated: boolean) => (animated && !matchMedia("(prefers-reduced-motion: reduce)").matches
    ? { transform: "scale(0.005)", opacity: 0, transition: { transform: peekSpring, opacity: { duration: 0.22, ease: "easeOut" } } }
    : { opacity: 0, transition: { duration: 0 } }),
};

const scrimVariants: Variants = {
  gone: (animated: boolean) => (animated && !matchMedia("(prefers-reduced-motion: reduce)").matches
    ? { opacity: 0, transition: tokens.floatingPane }
    : { opacity: 0, transition: { duration: 0 } }),
};

function sourceTitle(session: Session, peek: Peek): string {
  const source = session.core.state.pages.get(peek.sourcePageId);
  return source?.live.title || source?.live.url || "page";
}

/** The Peek's page, embedded once the engine has it and taking the keyboard as it comes. */
function PeekPage({ session, pageId, shown, reduce }: { session: Session; pageId: string; shown: boolean; reduce: boolean }) {
  const [content, setContent] = useState<string | null>(null);
  const element = useRef<HTMLEmbedElement>(null);
  const live = session.core.state.pages.get(pageId)?.phase.name === "live";
  useEffect(() => {
    if (!session.shell || !live || content) return;
    let current = true;
    void pageContentId(session, pageId).then((id) => {
      if (current && id) setContent(id);
    });
    return () => {
      current = false;
    };
  }, [session, pageId, live, content]);
  useEffect(() => {
    if (content) element.current?.focus();
  }, [content]);
  if (!content) return null;
  return (
    <motion.embed ref={element} className="page-frame" type="application/x-chromium-surface-embed" data-content-id={content}
      tabIndex={-1} initial={{ opacity: 0 }} animate={{ opacity: shown ? 1 : 0 }}
      transition={reduce ? { duration: 0 } : { duration: 0.12, ease: "easeOut", delay: 0.034 }} />
  );
}
