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
 * A popover beside `anchor`, as the Mac's crestPopover with its arrow on the
 * trailing edge: it stands past the anchor's trailing side, and goes when
 * the person presses anywhere else or presses Escape.
 */
export function Popover({ anchor, label, onClose, children }: {
  anchor: DOMRect;
  label: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const panel = useRef<HTMLDivElement>(null);
  const [place, setPlace] = useState({ left: anchor.right + 10, top: anchor.top });
  useLayoutEffect(() => {
    const element = panel.current;
    if (!element) return;
    const height = element.offsetHeight;
    setPlace({ left: anchor.right + 10, top: Math.max(8, Math.min(anchor.top + anchor.height / 2 - height / 2, innerHeight - height - 8)) });
  }, [anchor]);
  useEffect(() => {
    const away = (event: PointerEvent) => {
      if (!(event.target instanceof Node) || !panel.current?.contains(event.target)) onClose();
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
  }, [onClose]);
  return createPortal(
    <motion.div ref={panel} className="crest-popover" role="dialog" aria-label={label} style={place}
      initial={{ opacity: 0, scale: 0.96 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.96 }}
      transition={tokens.floatingPane}>
      {children}
    </motion.div>,
    document.querySelector(".browser-window") ?? document.body,
  );
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
