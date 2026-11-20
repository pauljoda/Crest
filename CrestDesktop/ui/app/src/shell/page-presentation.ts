import { type PagePresentation, PresentPage } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";
import { useEffect, useRef, useState } from "react";

type Question = Omit<PresentPage, "$kind">;

/** The core's answers, by what was asked: the same question always has the same answer. */
const answers = new Map<string, PagePresentation>();

function keyOf(question: Question): string {
  return [question.surface?.name ?? "", question.hasPage, question.hasNavigationFailure, question.hasProcessFailure,
    question.restoresUnloaded].join("|");
}

/**
 * What the page card shows for the shown tab, as the core answers it
 * (`PresentPage`): a Start Page, a native view, the live page or its
 * failure, or nothing yet. An answer is asked once and remembered; until it
 * arrives, the card keeps what it showed.
 */
export function usePagePresentation(core: CrestCore, question: Question): PagePresentation | null {
  const key = keyOf(question);
  const [, answered] = useState(0);
  const last = useRef<PagePresentation | null>(null);
  const known = answers.get(key);
  if (known) last.current = known;
  useEffect(() => {
    if (answers.has(key)) return;
    let current = true;
    void core.query(PresentPage(question)).then((answer) => {
      answers.set(key, answer.presentation);
      if (current) answered((count) => count + 1);
    });
    return () => {
      current = false;
    };
    // The key is the question.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [core, key]);
  return known ?? last.current;
}
