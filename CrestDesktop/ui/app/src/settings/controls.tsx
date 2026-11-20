import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion } from "motion/react";
import { type ReactNode, useId } from "react";

import { Symbol } from "../symbols";

/**
 * The Mac's CrestSettingsGroup in a grouped form: a section's title, with a
 * quiet Reset that fades in once something in it changed, its rows on one
 * card, and its footnote beneath.
 */
export function Group({ title, footer, onReset, children }: {
  title?: string;
  footer?: ReactNode;
  /** Puts the group's rows back as they ship, offered while any of them changed. */
  onReset?: (() => void) | null;
  children: ReactNode;
}) {
  const id = useId();
  return (
    <section className="settings-group" aria-labelledby={title ? id : undefined}>
      {(title || onReset !== undefined) && (
        <div className="settings-group-header">
          {title && <h3 id={id}>{title}</h3>}
          <AnimatePresence>
            {onReset && (
              <motion.button key="reset" type="button" className="settings-group-reset" onClick={onReset}
                initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={tokens.surface}>
                Reset
              </motion.button>
            )}
          </AnimatePresence>
        </div>
      )}
      <div className="settings-card">{children}</div>
      {footer && <p className="settings-footer">{footer}</p>}
    </section>
  );
}

/**
 * CrestSettingRow: the title, and the subtitle under it, on the left, and
 * the control on the right; a row that changed from how it ships offers to
 * go back, beside its title and in its menu.
 */
export function Row({ title, subtitle, onReset, children, htmlFor }: {
  title: ReactNode;
  subtitle?: ReactNode;
  onReset?: (() => void) | null;
  children?: ReactNode;
  /** The control the title labels. */
  htmlFor?: string;
}) {
  return (
    <div className="settings-row" onContextMenu={undefined}>
      <div className="settings-row-text">
        <span className="settings-row-title">
          {htmlFor ? <label htmlFor={htmlFor}>{title}</label> : title}
          <AnimatePresence>
            {onReset && (
              <motion.button key="reset" type="button" className="settings-row-reset" aria-label="Reset to Default"
                title="Reset to Default" onClick={onReset}
                initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={tokens.surface}>
                <Symbol name="arrow.counterclockwise" size={10} strokeWidth={2.75} />
              </motion.button>
            )}
          </AnimatePresence>
        </span>
        {subtitle && <span className="settings-row-subtitle">{subtitle}</span>}
      </div>
      {children !== undefined && <div className="settings-row-control">{children}</div>}
    </div>
  );
}

/** A setting that is on or off, which Settings always draws as a switch. */
export function Toggle({ title, subtitle, checked, onChange, disabled, defaultValue }: {
  title: ReactNode;
  subtitle?: ReactNode;
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  /** How it ships, which offers a reset while it differs. */
  defaultValue?: boolean;
}) {
  const id = useId();
  return (
    <Row title={title} subtitle={subtitle} htmlFor={id}
      onReset={defaultValue !== undefined && checked !== defaultValue && !disabled ? () => onChange(defaultValue) : null}>
      <Switch id={id} checked={checked} onChange={onChange} disabled={disabled} />
    </Row>
  );
}

export function Switch({ id, checked, onChange, disabled, label }: {
  id?: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  label?: string;
}) {
  return (
    <button id={id} type="button" role="switch" aria-checked={checked} aria-label={label} disabled={disabled}
      className={`settings-switch${checked ? " on" : ""}`} onClick={() => onChange(!checked)}>
      <motion.span className="settings-switch-knob" layout transition={tokens.collection} />
    </button>
  );
}

export interface Choice<T> {
  readonly value: T;
  readonly label: string;
}

/** A setting that takes one of several values, from a menu. */
export function Picker<T>({ title, subtitle, value, choices, onChange, disabled, defaultValue, same = Object.is }: {
  title: ReactNode;
  subtitle?: ReactNode;
  value: T;
  choices: readonly Choice<T>[];
  onChange: (value: T) => void;
  disabled?: boolean;
  defaultValue?: T;
  same?: (left: T, right: T) => boolean;
}) {
  const id = useId();
  const index = choices.findIndex((choice) => same(choice.value, value));
  return (
    <Row title={title} subtitle={subtitle} htmlFor={id}
      onReset={defaultValue !== undefined && !same(value, defaultValue) && !disabled ? () => onChange(defaultValue) : null}>
      <span className="settings-select">
        <select id={id} value={index} disabled={disabled} onChange={(event) => onChange(choices[Number(event.target.value)].value)}>
          {choices.map((choice, at) => <option key={choice.label} value={at}>{choice.label}</option>)}
        </select>
        <Symbol name="chevron.up.chevron.down" size={11} className="settings-select-glyph" />
      </span>
    </Row>
  );
}

/** A few values side by side, one chosen. */
export function Segmented<T>({ value, choices, onChange, label, same = Object.is }: {
  value: T;
  choices: readonly Choice<T>[];
  onChange: (value: T) => void;
  label: string;
  same?: (left: T, right: T) => boolean;
}) {
  return (
    <div className="settings-segmented" role="radiogroup" aria-label={label}>
      {choices.map((choice) => {
        const chosen = same(choice.value, value);
        return (
          <button key={choice.label} type="button" role="radio" aria-checked={chosen} className={chosen ? "chosen" : undefined}
            onClick={() => onChange(choice.value)}>
            {choice.label}
          </button>
        );
      })}
    </div>
  );
}

/** A bordered push button in a row or beneath a group. */
export function Button({ children, onClick, destructive, disabled }: {
  children: ReactNode;
  onClick: () => void;
  destructive?: boolean;
  disabled?: boolean;
}) {
  return (
    <button type="button" className={`settings-button${destructive ? " destructive" : ""}`} disabled={disabled} onClick={onClick}>
      {children}
    </button>
  );
}

/** A page's scroller, which starts where the page was left and remembers where it goes. */
export function keptScroll(scrolls: Map<string, number>, key: string) {
  return {
    ref: (element: HTMLDivElement | null) => {
      if (element) element.scrollTop = scrolls.get(key) ?? 0;
    },
    onScroll: (event: { currentTarget: HTMLDivElement }) => void scrolls.set(key, event.currentTarget.scrollTop),
  };
}
