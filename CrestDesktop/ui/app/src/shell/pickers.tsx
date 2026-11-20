import { type BrandColor, Tincture } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

import { css } from "../branding";
import { Symbol } from "../symbols";

/** The Mac's folderDefault (Slate), the colour a folder or split wears until one is chosen. */
export const folderDefault: BrandColor = { red: 0.43, green: 0.48, blue: 0.54, alpha: 1 };

/** BrowserFolderColorPalette: Slate, then the core's tinctures. */
const colorChoices: readonly { readonly title: string; readonly value: BrandColor }[] = [
  { title: "Slate", value: folderDefault },
  ...["ink", "indigo", "ocean", "sky", "teal", "sage", "gold", "ember", "rose", "sand"].map((name) => {
    const tincture = Tincture.named(name)!;
    return { title: tincture.title, value: tincture.color };
  }),
];

function sameColor(left: BrandColor, right: BrandColor): boolean {
  const near = (a: number, b: number) => Math.abs(a - b) < 0.004;
  return near(left.red, right.red) && near(left.green, right.green) && near(left.blue, right.blue);
}

function hexOf(color: BrandColor): string {
  return `#${[color.red, color.green, color.blue].map((part) => Math.round(part * 255).toString(16).padStart(2, "0")).join("")}`;
}

function colorOfHex(hex: string): BrandColor {
  const value = Number.parseInt(hex.slice(1), 16);
  return { red: ((value >> 16) & 255) / 255, green: ((value >> 8) & 255) / 255, blue: (value & 255) / 255, alpha: 1 };
}

/**
 * A popover at `anchor`, as the Mac's crestPopover: past the anchor's
 * trailing side by default, or, at the bottom edge, hanging below it with its
 * arrow pointing up at the anchor's middle; where the window has no room
 * below, it goes above, and with no room above either, beside the anchor, as
 * NSPopover tries its other edges. It goes when the person presses anywhere
 * else, other than on `ignore`, such as the control that toggles it, or
 * presses Escape.
 */
export function Popover({ anchor, label, onClose, children, edge = "trailing", ignore = null, className }: {
  anchor: DOMRect;
  label: string;
  onClose: () => void;
  children: ReactNode;
  edge?: "trailing" | "bottom";
  ignore?: Element | null;
  className?: string;
}) {
  const panel = useRef<HTMLDivElement>(null);
  const [place, setPlace] = useState<{ left: number; top: number; side?: PopoverSide; arrow?: number }>({ left: anchor.right + 10, top: anchor.top });
  useLayoutEffect(() => {
    const element = panel.current;
    if (!element) return;
    const width = element.offsetWidth;
    const height = element.offsetHeight;
    if (edge === "trailing") {
      setPlace({ left: anchor.right + 10, top: Math.max(8, Math.min(anchor.top + anchor.height / 2 - height / 2, innerHeight - height - 8)) });
      return;
    }
    const margin = 8;
    const reach = popoverArrow.reach;
    const clamp = (value: number, low: number, high: number) => Math.max(low, Math.min(value, high));
    const middleX = anchor.left + anchor.width / 2;
    const middleY = anchor.top + anchor.height / 2;
    const left = clamp(middleX - width / 2, margin, innerWidth - width - margin);
    const top = clamp(middleY - height / 2, margin, innerHeight - height - margin);
    const end = popoverArrow.width / 2 + 16;
    const arrowX = clamp(middleX - left, end, width - end);
    const arrowY = clamp(middleY - top, end, height - end);
    if (anchor.bottom + reach + height <= innerHeight - margin) {
      setPlace({ left, top: anchor.bottom + reach, side: "below", arrow: arrowX });
    } else if (anchor.top - reach - height >= margin) {
      setPlace({ left, top: anchor.top - reach - height, side: "above", arrow: arrowX });
    } else if (anchor.right + reach + width <= innerWidth - margin) {
      setPlace({ left: anchor.right + reach, top, side: "after", arrow: arrowY });
    } else if (anchor.left - reach - width >= margin) {
      setPlace({ left: anchor.left - reach - width, top, side: "before", arrow: arrowY });
    } else {
      setPlace({ left, top: Math.min(anchor.bottom + reach, innerHeight - height - margin), side: "below", arrow: arrowX });
    }
  }, [anchor, edge]);
  useEffect(() => {
    const away = (event: PointerEvent) => {
      if (!(event.target instanceof Node)) return onClose();
      if (panel.current?.contains(event.target) || ignore?.contains(event.target)) return;
      onClose();
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      onClose();
    };
    window.addEventListener("pointerdown", away, true);
    window.addEventListener("keydown", escape, true);
    return () => {
      window.removeEventListener("pointerdown", away, true);
      window.removeEventListener("keydown", escape, true);
    };
  }, [onClose, ignore]);
  const hangs = edge === "bottom" && place.side !== undefined && place.arrow !== undefined;
  return createPortal(
    <motion.div ref={panel} className={`crest-popover${className ? ` ${className}` : ""}`} role="dialog" aria-label={label}
      style={{ left: place.left, top: place.top, transformOrigin: hangs ? arrowOrigin(place.side!, place.arrow!) : undefined }}
      initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.96 }}
      transition={tokens.floatingPane}>
      {hangs && (
        <svg className="crest-popover-arrow" width={popoverArrow.width} height="11" viewBox="0 0 28 11"
          style={arrowPlace(place.side!, place.arrow!, panel.current?.offsetWidth ?? 0)} aria-hidden>
          <path d="M0 11c4 0 6.5-1.6 8.6-3.7l3.6-3.6a2.5 2.5 0 0 1 3.6 0l3.6 3.6C21.5 9.4 24 11 28 11z" fill="currentColor" />
        </svg>
      )}
      {children}
    </motion.div>,
    document.querySelector(".browser-window") ?? document.body,
  );
}

/** The arrow a hanging popover points with: its width, and how far its tip stands the panel from the anchor. */
const popoverArrow = { width: 28, reach: 13 } as const;

/** Which side of its anchor a hanging popover stands on. */
type PopoverSide = "below" | "above" | "after" | "before";

/** Where the arrow stands, `along` the panel's edge facing the anchor: its base just inside the edge, its tip 10.5 out. */
function arrowPlace(side: PopoverSide, along: number, width: number) {
  const half = popoverArrow.width / 2;
  switch (side) {
    case "below": return { left: along - half, top: -10.5 };
    case "above": return { left: along - half, bottom: -10.5, transform: "rotate(180deg)" };
    case "after": return { left: -5 - half, top: along - 5.5, transform: "rotate(-90deg)" };
    case "before": return { left: width + 5 - half, top: along - 5.5, transform: "rotate(90deg)" };
  }
}

/** The arrow's tip, which the popover grows from. */
function arrowOrigin(side: PopoverSide, along: number): string {
  switch (side) {
    case "below": return `${along}px -10px`;
    case "above": return `${along}px calc(100% + 10px)`;
    case "after": return `-10px ${along}px`;
    case "before": return `calc(100% + 10px) ${along}px`;
  }
}

/**
 * BrowserFolderColorPicker: the title, a reset beside it once a colour was
 * chosen, the house colours as swatches six to a line, and the system's own
 * colour picker for any other.
 */
export function ColorPicker({ title, color, resetTitle, onChoose, onReset }: {
  title: string;
  color: BrandColor;
  /** What the reset says, shown while a colour of the person's own is set. */
  resetTitle: string | null;
  onChoose: (color: BrandColor) => void;
  onReset: () => void;
}) {
  return (
    <div className="color-picker">
      <div className="picker-header">
        <span className="picker-title">{title}</span>
        <AnimatePresence>
          {resetTitle && (
            <motion.button key="reset" type="button" className="picker-reset" aria-label={resetTitle} title={resetTitle}
              initial={{ opacity: 0, scale: 0.72 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.72 }}
              transition={tokens.collection} onClick={onReset}>
              <Symbol name="trash" size={14} />
            </motion.button>
          )}
        </AnimatePresence>
      </div>
      <div className="color-swatches" role="radiogroup" aria-label={title}>
        {colorChoices.map((choice) => {
          const chosen = sameColor(color, choice.value);
          return (
            <button key={choice.title} type="button" role="radio" aria-checked={chosen} aria-label={choice.title}
              title={choice.title} className={`color-swatch${chosen ? " chosen" : ""}`} onClick={() => onChoose(choice.value)}>
              <span style={{ background: css(choice.value) }} />
            </button>
          );
        })}
      </div>
      <div className="picker-divider" />
      <label className="custom-color">
        <span>Custom Color</span>
        <input type="color" value={hexOf(color)} onChange={(event) => onChoose(colorOfHex(event.target.value))} />
      </label>
    </div>
  );
}

/** Emoji a person often picks for a folder, split or Space, before Windows' own emoji panel. */
const commonEmoji = [
  "⭐", "❤️", "🔥", "✅", "📌", "📁", "📚", "📝", "💼", "🏠", "🎵", "🎮",
  "🛒", "✈️", "🍔", "☕", "💡", "🧪", "🛠️", "📈", "🎨", "📷", "🌱", "🐶",
];

/**
 * The Mac's icon customization popover, as Windows offers emoji: the title, a
 * reset to the drawn icon once an emoji was set, a field that takes one emoji
 * (Windows' emoji panel, Win+period, types into it), and the emoji people
 * pick most.
 */
export function EmojiPicker({ title, current, resetTitle, onChoose, onReset }: {
  title: string;
  current: string | null;
  resetTitle: string | null;
  onChoose: (emoji: string) => void;
  onReset: () => void;
}) {
  const field = useRef<HTMLInputElement>(null);
  useEffect(() => field.current?.focus(), []);
  return (
    <div className="emoji-picker">
      <div className="picker-header">
        <span className="picker-title">{title}</span>
        {resetTitle && (
          <button type="button" className="picker-reset" aria-label={resetTitle} title={resetTitle} onClick={onReset}>
            <Symbol name="trash" size={14} />
          </button>
        )}
      </div>
      <input ref={field} className="emoji-field" aria-label="Emoji" placeholder="Type an emoji (Win + .)"
        defaultValue={current ?? ""} onInput={(event) => {
          const emoji = firstEmoji(event.currentTarget.value);
          if (emoji) onChoose(emoji);
        }} />
      <div className="emoji-grid">
        {commonEmoji.map((emoji) => (
          <button key={emoji} type="button" className={`emoji-choice${emoji === current ? " chosen" : ""}`} aria-label={emoji}
            onClick={() => onChoose(emoji)}>
            {emoji}
          </button>
        ))}
      </div>
    </div>
  );
}

/** The first emoji in `text`, or null where it holds none. */
function firstEmoji(text: string): string | null {
  const segments = new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text.trim());
  for (const { segment } of segments) {
    if (/\p{Extended_Pictographic}/u.test(segment)) return segment;
  }
  return null;
}
