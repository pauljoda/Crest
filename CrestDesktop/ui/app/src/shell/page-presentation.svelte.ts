import { type PagePresentation, PresentPage } from "@crest/contracts";
import type { CrestCore } from "@crest/core-client";
import { untrack } from "svelte";

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
export function usePagePresentation(core: CrestCore, question: () => Question): { readonly current: PagePresentation | null } {
  let answered = $state(0);
  let last: PagePresentation | null = null;
  const key = $derived(keyOf(question()));
  const current = $derived.by(() => {
    void answered;
    const known = answers.get(key);
    if (known) last = known;
    return known ?? last;
  });
  // The key is the question.
  $effect(() => {
    const asked = key;
    if (answers.has(asked)) return;
    let current = true;
    void core.query(PresentPage(untrack(question))).then((answer) => {
      answers.set(asked, answer.presentation);
      if (current) answered += 1;
    });
    return () => {
      current = false;
    };
  });
  return {
    get current() {
      return current;
    },
  };
}
