import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import type { CSSProperties } from "react";

import { setupSteps, type SetupStepName } from "./setup-walk";

/** BrowserSetupStepChips' tilt: each chip a little askew, as if laid down by hand. */
const tilts = [-2, 1.5, -1, 2];

/**
 * BrowserSetupStepChips: a numbered paper chip for each step. On the welcome
 * every chip is large, named and colored; in a step's header they are
 * compact, the steps reached colored, the open one named, lifted and a
 * little larger, the ones ahead plain paper. Pressing one opens its step.
 */
export function StepChips({ walk, current, size, onOpen }: {
  walk: readonly SetupStepName[];
  current: SetupStepName | null;
  size: "welcome" | "compact";
  onOpen: (step: SetupStepName) => void;
}) {
  const reached = current ? walk.indexOf(current) : -1;
  const reducesMotion = useReducedMotion() ?? false;
  return (
    <div className={`setup-chips ${size}`} role="group" aria-label="Setup steps">
      {walk.map((name, index) => {
        const step = setupSteps[name];
        const open = index === reached;
        const colored = size === "welcome" || index <= reached;
        const names = size === "welcome" || open;
        return (
          <button key={name} type="button" className={`setup-chip${open ? " open" : ""}${colored ? " colored" : ""}`}
            aria-label={step.title} aria-current={open ? "step" : undefined} data-testid={`setup-step-${name}`}
            style={{ "--chip-color": `rgb(${step.color.join(" ")})`, "--chip-tilt": `${tilts[index % tilts.length]}deg` } as CSSProperties}
            onClick={() => onOpen(name)}>
            <span className="setup-chip-number">{String(index + 1).padStart(2, "0")}</span>
            {/* The open step's name comes in from the number, as the Mac's grows from the leading edge. */}
            <AnimatePresence initial={false}>
              {names && (
                <motion.span key="title" className="setup-chip-title"
                  initial={{ width: 0, opacity: 0, scale: 0.8 }} animate={{ width: "auto", opacity: 1, scale: 1 }}
                  exit={{ width: 0, opacity: 0, scale: 0.8 }} transition={reducesMotion ? { duration: 0 } : tokens.setupChips}>
                  {step.title}
                </motion.span>
              )}
            </AnimatePresence>
          </button>
        );
      })}
    </div>
  );
}
