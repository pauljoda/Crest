import type { BrandColor, PaletteRow, PaletteScope, SearchProvider, ShortcutBinding, TabState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, usePresence } from "motion/react";
import {
  type CompositionEvent,
  type KeyboardEvent,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import { cachedTabIcon } from "../page-icon";
import { shortcutText } from "../shortcuts";
import { Symbol } from "../symbols";
import { type PaletteItem, type PaletteModel, providerActionTitle } from "./palette-model";
import { closePalette, openPalette, type PaletteParts, setOverlayPresent, useOverlayPresent } from "./palette-morph";

/** BrowserCommandPaletteMetrics: the overlay card's sizes, in CSS pixels for the Mac's points. */
const metrics = {
  maximumResultAreaHeight: 390,
  minimumResultAreaHeight: 82,
  reservedHeight: 117,
  fieldHeight: 68,
  cardPadding: 24,
  maximumCardWidth: 720,
} as const;

interface PaletteProps {
  readonly model: PaletteModel;
  /** The keys each command answers to, for the badges command rows wear. */
  readonly bindings: readonly ShortcutBinding[];
  /** The Space's tabs, for the icons tab rows wear. */
  readonly tabs: readonly TabState[];
}

/**
 * The command palette over a window, as the Mac's overlay shows it: a scrim
 * over the whole window, and the card centered over the page, its top edge
 * where a card with its tallest results would sit centered, growing only
 * downward. It grows out of the sidebar's address field and shrinks back
 * into it (`palette-morph.ts`), its glass apart from its contents so each
 * keeps its own pace.
 */
export function CommandPalette({ model, bindings, tabs }: PaletteProps) {
  useSyncExternalStore((listener) => model.subscribe(listener), () => model.version);
  const area = useRef<HTMLDivElement>(null);
  const size = useElementSize(area);
  const width = Math.min(metrics.maximumCardWidth, Math.max(0, size.width - 2 * metrics.cardPadding));
  const resultsHeight = Math.max(metrics.minimumResultAreaHeight,
    Math.min(metrics.maximumResultAreaHeight, size.height - metrics.reservedHeight));
  const top = Math.max(metrics.cardPadding, (size.height - (metrics.fieldHeight + resultsHeight)) / 2);

  const scrim = useRef<HTMLDivElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const moving = useRef<HTMLDivElement>(null);
  const resting = useRef<HTMLDivElement>(null);
  const reveal = useRef<HTMLDivElement>(null);
  const contents = useRef<HTMLDivElement>(null);
  const parts = (): PaletteParts | null => {
    const [s, c, m, r, v, n] = [scrim.current, card.current, moving.current, resting.current, reveal.current, contents.current];
    return s && c && m && r && v && n ? { scrim: s, card: c, moving: m, resting: r, reveal: v, contents: n } : null;
  };
  // The palette comes in once its card is laid out where it rests; the scrim waits unseen until then.
  const laidOut = size.width > 0;
  const opened = useRef(false);
  useLayoutEffect(() => {
    if (opened.current) return;
    const found = parts();
    if (!found) {
      scrim.current?.style.setProperty("opacity", "0");
      return;
    }
    opened.current = true;
    void openPalette(found);
  }, [laidOut]);
  useEffect(() => {
    setOverlayPresent(true);
    return () => setOverlayPresent(false);
  }, []);
  // It leaves once it has shrunk back into the field, or faded where it rests.
  const [present, safeToRemove] = usePresence();
  useEffect(() => {
    if (present) return;
    const found = parts();
    if (!found || !opened.current) {
      safeToRemove();
      return;
    }
    void closePalette(found).then(safeToRemove);
    // Leaving runs once, as the palette is taken away.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [present]);

  return (
    <div className="palette-layer">
      <div ref={scrim} className="palette-scrim" onMouseDown={() => model.host.dismiss()} />
      <div className="palette-area" ref={area}>
        {laidOut && (
          <div ref={card} className="palette-card" role="dialog" aria-label="Command Palette" style={{ width, marginTop: top }}>
            <div ref={moving} className="palette-glass moving" aria-hidden />
            <div ref={resting} className="palette-glass resting" aria-hidden />
            <div ref={reveal} className="palette-reveal">
              <div ref={contents} className="palette-contents">
                <SearchField model={model} embedded={false} />
                {model.providerChips.length > 0 && <ProviderChips model={model} />}
                <div className="palette-divider" />
                <ResultList model={model} bindings={bindings} tabs={tabs}
                  size={{ height: resultsHeight - (model.providerChips.length > 0 ? 44 : 0) }} />
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/**
 * The palette in place on a Start Page, as the Mac's embedded presentation:
 * no scrim and no close button, Escape only leaves a scope or a completion,
 * and the results show below the field once there are some, up to the
 * overlay's tallest.
 */
export function EmbeddedPalette({ model, bindings, tabs, obscured, takesFocus }: PaletteProps & {
  /** Whether the overlay palette covers this one, which then hides from assistive technology. */
  readonly obscured: boolean;
  /** Whether the field takes the keyboard as it opens, as the focused card's does. */
  readonly takesFocus: boolean;
}) {
  useSyncExternalStore((listener) => model.subscribe(listener), () => model.version);
  const showsResults = model.groups.some((group) => group.items.length > 0);
  const overlaid = useOverlayPresent();
  return (
    <div className={`palette-card embedded${overlaid ? " overlaid" : ""}`} aria-hidden={obscured || undefined}>
      <SearchField model={model} embedded takesFocus={takesFocus} />
      {model.providerChips.length > 0 && <ProviderChips model={model} />}
      {showsResults && (
        <>
          <div className="palette-divider" />
          <ResultList model={model} bindings={bindings} tabs={tabs} size={{ maxHeight: metrics.maximumResultAreaHeight }} />
        </>
      )}
    </div>
  );
}

function SearchField({ model, embedded, takesFocus = true }: { model: PaletteModel; embedded: boolean; takesFocus?: boolean }) {
  const input = useRef<HTMLInputElement>(null);
  const composing = useRef(false);
  const report = () => {
    const field = input.current;
    if (!field) return;
    model.updateEditing(field.value, field.selectionStart ?? 0, field.selectionEnd ?? 0, composing.current);
  };
  useLayoutEffect(() => {
    const field = input.current;
    if (!field) return;
    model.field = {
      applyCompletion(text, start, end) {
        field.setRangeText(text, start, end, "end");
        report();
      },
      replaceText(text) {
        field.value = text;
        field.setSelectionRange(text.length, text.length);
        report();
      },
    };
    field.value = model.query;
    // The palette opens with what it holds selected, as the Mac's field does.
    if (takesFocus) {
      field.focus();
      field.select();
    }
    report();
    return () => {
      model.field = null;
    };
    // The field binds once for the palette it opened with.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [model]);

  // A palette kept while its card was only shown still takes the keyboard
  // once its card becomes the one in use.
  const tookFocus = useRef(takesFocus);
  useEffect(() => {
    if (takesFocus && !tookFocus.current) input.current?.focus();
    tookFocus.current = takesFocus;
  }, [takesFocus]);

  const held = (event: KeyboardEvent<HTMLInputElement>) =>
    model.setHeld({ control: event.ctrlKey, shift: event.shiftKey, alt: event.altKey });

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    held(event);
    if (composing.current || event.nativeEvent.isComposing) return;
    const field = event.currentTarget;
    const handled = (() => {
      switch (event.key) {
        case "Tab":
          if (event.shiftKey) model.moveSelection(-1);
          else model.pressTab();
          return true;
        case "ArrowRight":
        case "End":
          return model.acceptCompletion();
        case "ArrowDown":
          if (event.altKey) model.moveSection(1);
          else model.pressDown();
          return true;
        case "ArrowUp":
          if (event.altKey) model.moveSection(-1);
          else model.moveSelection(-1);
          return true;
        case "Enter":
          model.pressReturn();
          return true;
        case "Delete":
        case "Backspace":
          if (event.shiftKey && model.forgetSelectedRow()) return true;
          return event.key === "Backspace" && field.value === "" && field.selectionStart === 0 && model.leaveScope();
        case "Escape":
          if (model.leaveScope()) return true;
          if (model.urlCompletion) {
            model.rejectCompletion();
            return true;
          }
          // The Start Page's palette stays where it is.
          if (embedded) return false;
          model.host.dismiss();
          return true;
        default:
          return false;
      }
    })();
    if (handled) event.preventDefault();
  };

  const completion = model.urlCompletion;
  const provider = model.activeProvider;
  const scope = model.activeScope;
  const placeholder = provider ? `${providerActionTitle(provider)}…` : scope ? `Search ${scope.title}…` : "Search or Enter URL…";
  return (
    <div className="palette-field">
      <Symbol name="magnifyingglass" size={19} className="palette-glyph" />
      {provider && <ProviderPill provider={provider} onClose={() => model.leaveScope()} />}
      {scope && <ScopeChip scope={scope} onClose={() => model.leaveScope()} />}
      <div className="palette-input">
        <input
          ref={input}
          aria-label="Command Palette"
          placeholder={placeholder}
          spellCheck={false}
          autoComplete="off"
          onInput={report}
          onSelect={report}
          onKeyDown={onKeyDown}
          onKeyUp={held}
          onBlur={() => model.setHeld({ control: false, shift: false, alt: false })}
          onCompositionStart={() => {
            composing.current = true;
            report();
          }}
          onCompositionEnd={(_event: CompositionEvent<HTMLInputElement>) => {
            composing.current = false;
            report();
          }}
        />
        {completion && <CompletionSuffix field={input} suffix={completion.suffix} />}
      </div>
      <Offer model={model} />
      {!embedded && (
        <button type="button" className="palette-close" title="Close" aria-label="Close" onClick={() => model.host.dismiss()}>
          <Symbol name="xmark" size={14} />
        </button>
      )}
    </div>
  );
}

/**
 * The rest of the address the core completes, after the caret, in the
 * field's own font: never part of what is typed until Tab or Right Arrow
 * accepts it. It shimmers now and then, as the Mac's does.
 */
function CompletionSuffix({ field, suffix }: { field: React.RefObject<HTMLInputElement | null>; suffix: string }) {
  const [left, setLeft] = useState(0);
  const mirror = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const input = field.current;
    if (!input || !mirror.current) return;
    mirror.current.textContent = input.value;
    setLeft(mirror.current.offsetWidth - input.scrollLeft);
  });
  return (
    <>
      <span ref={mirror} className="palette-mirror" aria-hidden />
      <span key={suffix} className="palette-suffix" style={{ left }} aria-hidden>{suffix}</span>
    </>
  );
}

/** What Tab does next: enter the offered provider, accept the completion, or enter the offered scope. */
function Offer({ model }: { model: PaletteModel }) {
  const provider = model.providerOffer;
  if (provider) {
    return (
      <span className="palette-offer" title={`Press Tab to ${providerActionTitle(provider)}`}>
        <ProviderPill provider={provider} />
        <TabHint />
      </span>
    );
  }
  if (model.urlCompletion) {
    return (
      <button type="button" className="palette-offer" title="Accept URL completion (Tab or Right Arrow)"
        aria-label="Accept URL completion" onMouseDown={(event) => event.preventDefault()}
        onClick={() => model.acceptCompletion()}>
        <TabHint />
      </button>
    );
  }
  const scope = model.scopeOffer;
  if (scope) {
    return (
      <span className="palette-offer" aria-label={`Search ${scope.title}`}>
        <ScopeChip scope={scope} />
        <TabHint />
      </span>
    );
  }
  return null;
}

function TabHint() {
  return (
    <span className="palette-tab-hint">
      <Symbol name="arrow.right.to.line" size={11} />
      Tab
    </span>
  );
}

function ProviderPill({ provider, onClose }: { provider: SearchProvider; onClose?: () => void }) {
  return (
    <span className="palette-chip" style={{ "--chip-tint": brandColor(provider.color) } as React.CSSProperties}>
      <ProviderIcon provider={provider} />
      <span className="palette-chip-title">{provider.title}</span>
      {onClose && (
        <button type="button" className="palette-chip-close" onClick={onClose}
          title={`Stop searching ${provider.title}`} aria-label={`Stop searching ${provider.title}`}>
          <Symbol name="xmark" size={10} />
        </button>
      )}
    </span>
  );
}

function ScopeChip({ scope, onClose }: { scope: PaletteScope; onClose?: () => void }) {
  return (
    <span className="palette-chip accent">
      <Symbol name={scope.symbol} size={11} />
      <span className="palette-chip-title">{scope.title}</span>
      {onClose && (
        <button type="button" className="palette-chip-close" onClick={onClose} title="Show all results"
          aria-label={`Stop searching ${scope.title}`}>
          <Symbol name="xmark" size={10} />
        </button>
      )}
    </span>
  );
}

/** A provider's icon on its paper plate: the kind's symbol until the providers' logos ship here. */
function ProviderIcon({ provider, size = 14 }: { provider: SearchProvider; size?: number }) {
  return (
    <span className="palette-provider-icon" style={{ width: size + 6, height: size + 6 }}>
      <Symbol name={provider.kind.symbol} size={Math.round(size * 0.65)} />
    </span>
  );
}

/** The providers what is typed names, as chips under the field; clicking one enters it. */
function ProviderChips({ model }: { model: PaletteModel }) {
  return (
    <div className="palette-provider-chips" role="group" aria-label="Search providers">
      {model.providerChips.map((provider, index) => (
        <button key={provider.name} type="button" className="palette-chip interactive"
          style={{ "--chip-tint": brandColor(provider.color) } as React.CSSProperties}
          title={providerActionTitle(provider)} onMouseDown={(event) => event.preventDefault()}
          onClick={() => model.enterProvider(provider)}>
          <ProviderIcon provider={provider} />
          {provider.shortcuts[0]
            ? <span className="palette-chip-title shortcut">{provider.shortcuts[0]}</span>
            : <span className="palette-chip-title">{provider.title}</span>}
          {index === 0 && <Symbol name="arrow.right.to.line" size={10} />}
        </button>
      ))}
    </div>
  );
}

/** The results: the overlay's keep one height, and the Start Page's grow with them up to the most. */
function ResultList({ model, bindings, tabs, size }: PaletteProps & {
  size: { readonly height: number } | { readonly maxHeight: number };
}) {
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    list.current?.querySelector(`[data-index="${model.selectedIndex}"]`)?.scrollIntoView({ block: "nearest" });
    // Only the keyboard scrolls the list; hover never does.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [model.keyboardRevision]);
  return (
    <div className="palette-results" ref={list} style={size} role="listbox">
      {model.groups.map((group) => {
        const rows = group.items.map((item) => (
          <Row key={item.id} model={model} item={item} section={group.section.name} bindings={bindings} tabs={tabs} />
        ));
        if (group.items.length === 0) return null;
        return group.section.title ? (
          <div key={group.section.name} className="palette-group">
            <div className="palette-group-title">{group.section.title}</div>
            {rows}
          </div>
        ) : rows;
      })}
    </div>
  );
}

function Row({ model, item, section, bindings, tabs }: {
  model: PaletteModel; item: PaletteItem; section: string; bindings: readonly ShortcutBinding[]; tabs: readonly TabState[];
}) {
  const { row } = item;
  const selected = item.index === model.selectedIndex;
  const intent = row.kind.isPrimary || section === "topHit";
  const opening = selected ? model.openingFor(row) : null;
  return (
    <div
      className={`palette-row ${selected ? "selected" : ""}`}
      data-index={item.index}
      role="option"
      aria-selected={selected}
      aria-label={row.title}
      onMouseMove={() => model.selectResult(item.index)}
      onMouseDown={(event) => event.preventDefault()}
      onClick={() => model.activate(row)}
    >
      <RowIcon row={row} intent={intent} tabs={tabs} />
      <div className="palette-row-text">
        <div className="palette-row-title">{row.title}</div>
        {row.subtitle && <div className="palette-row-detail">{row.subtitle}</div>}
      </div>
      <span className="palette-row-spacer" />
      <RowTrailing row={row} section={section} opening={opening?.title ?? null} bindings={bindings} />
      <Symbol
        name={selected ? opening!.symbol : intent ? "arrow.turn.down.left" : "arrow.right"}
        size={intent ? 12 : 14}
        className="palette-row-end"
      />
    </div>
  );
}

/** A tab row wears its tab's icon; a provider row the provider's; any other its symbol. */
function RowIcon({ row, intent, tabs }: { row: PaletteRow; intent: boolean; tabs: readonly TabState[] }) {
  const tab = row.tabId ? tabs.find((candidate) => candidate.id === row.tabId) : undefined;
  const icon = row.tabId ? cachedTabIcon(row.tabId) : null;
  return (
    <span className={`palette-row-icon ${intent ? "intent" : ""}`}>
      {icon ? <img src={icon} width={20} height={20} alt="" />
        : row.provider ? <ProviderIcon provider={row.provider} size={intent ? 18 : 20} />
        : <Symbol name={tab?.symbol ?? row.symbol} size={intent ? 18 : 16} />}
    </span>
  );
}

/**
 * What a row says at its end: where it opens while keys are held, else a
 * command's keys, else its kind in the blended list, else what choosing it
 * does.
 */
function RowTrailing({ row, section, opening, bindings }: {
  row: PaletteRow; section: string; opening: string | null; bindings: readonly ShortcutBinding[];
}) {
  const keys = row.command ? bindings.find((binding) => binding.command.name === row.command!.name)?.keys : null;
  return (
    <AnimatePresence mode="popLayout" initial={false}>
      {opening ? (
        <motion.span key="opening" className="palette-row-opening" initial={{ opacity: 0, filter: "blur(4px)" }}
          animate={{ opacity: 1, filter: "blur(0px)" }} exit={{ opacity: 0, filter: "blur(4px)" }} transition={tokens.hover}>
          {opening}
        </motion.span>
      ) : keys ? (
        <span key="keys" className="palette-shortcut">{shortcutText(keys)}</span>
      ) : section === "results" ? (
        <span key="label" className="palette-row-kind">{row.kind.label}</span>
      ) : row.kind.action ? (
        <span key="action" className="palette-row-kind">{row.kind.action}</span>
      ) : null}
    </AnimatePresence>
  );
}

function brandColor(color: BrandColor): string {
  const channel = (value: number) => Math.round(Math.min(Math.max(value, 0), 1) * 255);
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)})`;
}

/** The element's size, kept current as it resizes. */
function useElementSize(element: React.RefObject<HTMLElement | null>) {
  const [size, setSize] = useState({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const measure = () => setSize({ width: target.clientWidth, height: target.clientHeight });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(target);
    return () => observer.disconnect();
  }, [element]);
  return size;
}
