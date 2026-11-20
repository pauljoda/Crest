import { motion as tokens } from "@crest/design";
import { motion } from "motion/react";

import { Symbol } from "../symbols";

/** One of the window's small symbol buttons. */
export function ChromeButton({ symbol, label, onClick, disabled = false, className }: {
  symbol: string;
  label: string;
  /** Hears the click with the button, for a menu that opens below it. */
  onClick?: (button: HTMLButtonElement) => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <motion.button
      className={className ? `chrome-button ${className}` : "chrome-button"}
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={(event) => onClick?.(event.currentTarget)}
      whileTap={disabled ? undefined : { scale: 0.9 }}
      transition={tokens.press}
    >
      <Symbol name={symbol} size={16} />
    </motion.button>
  );
}
