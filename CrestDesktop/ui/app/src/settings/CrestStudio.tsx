import {
  type CrestCharge,
  CrestChargeKind,
  type CrestChargeLayout,
  type CrestMonogramStyle,
  CrestMonogramStyle as MonogramStyles,
  type SpaceBranding,
  type SpaceCrest,
  SpaceIconStyle,
} from "@crest/contracts";
import { AnimatePresence } from "motion/react";
import { type ReactNode, useEffect, useId, useRef, useState } from "react";

import { EmojiPicker, Popover } from "../shell/pickers";
import {
  applyingFinish,
  type CrestStep,
  crestSteps,
  finishChoices,
  offeredBackplates,
  offeredDivisions,
  offeredLayouts,
  offeredOrdinaries,
  offeredTrims,
  resolvedCharge,
  selectableSymbols,
  wearsFinish,
} from "../spaces/space-look";
import { SpaceCrestIcon } from "../spaces/SpaceIdentity";
import { Symbol, symbolNames } from "../symbols";
import { Row, Segmented } from "./controls";

/** BrowserCrestForgeMetrics.tileCrestSize, and the Emblem grid's smaller crests. */
const tileCrest = 56;
const emblemCrest = 52;
/** How many emblems show before Browse all. */
const firstEmblems = 12;

/** The step the studio shows, kept as the page moves between Spaces, as the Mac's tabState.forgeStep. */
let rememberedStep: CrestStep = "shape";

/**
 * The Crest section under More Customization, for a crest icon: the
 * Mac's step bar, Shape, Field, Band, Emblem, Border and Finish, over the
 * step's gallery of crests wearing each choice, or for Emblem its source
 * and arrangement. `preview` is the look galleries draw from, the drag's
 * start while one runs; `defaults` the starting look the resets go back to.
 */
export function CrestStudio({ branding, preview, defaults, step, onStep, write }: {
  branding: SpaceBranding;
  preview: SpaceBranding;
  defaults: SpaceBranding;
  step: CrestStep;
  onStep: (step: CrestStep) => void;
  write: (next: SpaceBranding) => void;
}) {
  const crest = branding.crest;
  const writeCrest = (next: SpaceCrest) => write({ ...branding, crest: next, hasCustomAppearance: true });
  const look = (change: (crest: SpaceCrest) => SpaceCrest): SpaceBranding => ({
    ...preview,
    iconStyle: SpaceIconStyle.layeredCrest,
    crest: change(preview.crest),
  });
  const gallery = <T extends { readonly name: string; readonly title: string }>(offered: readonly T[], worn: T, apply: (crest: SpaceCrest, option: T) => SpaceCrest) => {
    // A crest wearing a part no longer offered keeps it among the choices.
    const options = offered.some((option) => option.name === worn.name) ? offered : [...offered, worn];
    return (
      <div className="forge-gallery" data-testid="space-forge-gallery">
        {options.map((option) => (
          <ChoiceTile key={option.name} title={option.title} selected={option.name === worn.name} onChoose={() => writeCrest(apply(crest, option))}>
            <SpaceCrestIcon branding={look((base) => apply(base, option))} size={tileCrest} />
          </ChoiceTile>
        ))}
      </div>
    );
  };
  return (
    <section className="settings-group" aria-label="Crest">
      <div className="settings-group-header forge-step-header">
        <h3>Crest</h3>
        <div data-testid="space-forge-steps">
          <Segmented label="Crest Studio step" value={step} choices={crestSteps.map(({ step: value, title }) => ({ value, label: title }))}
            onChange={(next: CrestStep) => {
              rememberedStep = next;
              onStep(next);
            }} />
        </div>
      </div>
      <div className="settings-card">
        {step === "shape" && gallery(offeredBackplates, crest.backplate, (base, backplate) => ({ ...base, backplate }))}
        {step === "field" && gallery(offeredDivisions, crest.fieldDivision, (base, fieldDivision) => ({ ...base, fieldDivision }))}
        {step === "band" && gallery(offeredOrdinaries, crest.ordinary, (base, ordinary) => ({ ...base, ordinary }))}
        {step === "border" && gallery(offeredTrims, crest.trim, (base, trim) => ({ ...base, trim }))}
        {step === "finish" && (
          <div className="forge-gallery" data-testid="space-forge-gallery">
            {finishChoices.map((choice) => (
              <ChoiceTile key={choice.name} title={choice.title} selected={wearsFinish(choice, crest)}
                onChoose={() => writeCrest(applyingFinish(choice, crest))}>
                <SpaceCrestIcon branding={look((base) => applyingFinish(choice, base))} size={tileCrest} />
              </ChoiceTile>
            ))}
          </div>
        )}
        {step === "emblem" && <CrestEmblem branding={branding} preview={preview} defaults={defaults} write={write} />}
      </div>
    </section>
  );
}

/** The step the studio opens on: the one last shown. */
export function initialCrestStep(): CrestStep {
  return rememberedStep;
}

/** Remembers a step the page opened, such as a crest swatch's. */
export function rememberCrestStep(step: CrestStep) {
  rememberedStep = step;
}

const chargeKey = (charge: CrestCharge) => `${charge.kind.name}|${charge.symbol?.name ?? ""}|${charge.text ?? ""}|${charge.style?.name ?? ""}`;

/**
 * BrowserCrestStudioEmblem: the figure on the crest, from heraldry, a
 * symbol, an emoji or a monogram, or none, and how many of it. Each
 * source keeps what was last picked in it while the person tries others.
 */
function CrestEmblem({ branding, preview, defaults, write }: {
  branding: SpaceBranding;
  preview: SpaceBranding;
  defaults: SpaceBranding;
  write: (next: SpaceBranding) => void;
}) {
  const crest = branding.crest;
  const charge = resolvedCharge(crest);
  const [source, setSource] = useState<CrestChargeKind>(charge.kind);
  const [systemName, setSystemName] = useState("sparkles");
  const [emoji, setEmoji] = useState("🦁");
  const [letters, setLetters] = useState("C");
  const [letterStyle, setLetterStyle] = useState<CrestMonogramStyle>(MonogramStyles.serif);
  const [search, setSearch] = useState("");
  const [showsAll, setShowsAll] = useState(false);
  const [picksEmoji, setPicksEmoji] = useState<DOMRect | null>(null);
  const emojiButton = useRef<HTMLButtonElement>(null);
  const searchId = useId();

  // The source and its field follow the crest's figure, unless it has none.
  const key = chargeKey(charge);
  useEffect(() => {
    if (charge.kind.name === CrestChargeKind.none.name) return;
    setSource(charge.kind);
    if (charge.kind.name === CrestChargeKind.system.name) setSystemName(charge.text ?? "sparkles");
    else if (charge.kind.name === CrestChargeKind.emoji.name) setEmoji(charge.text ?? "🦁");
    else if (charge.kind.name === CrestChargeKind.monogram.name) {
      setLetters(charge.text ?? "C");
      setLetterStyle(charge.style ?? MonogramStyles.serif);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const writeCrest = (next: SpaceCrest) => write({ ...branding, crest: next, hasCustomAppearance: true });
  /** The figure `kind` makes from what was last picked in it. */
  const chargeOf = (kind: CrestChargeKind, fields: { system?: string; emoji?: string; letters?: string; style?: CrestMonogramStyle } = {}): CrestCharge => {
    switch (kind.name) {
      case CrestChargeKind.heraldic.name: return { kind, symbol: crest.symbol, text: null, style: null };
      case CrestChargeKind.system.name: return { kind, symbol: null, text: fields.system ?? systemName, style: null };
      case CrestChargeKind.emoji.name: return { kind, symbol: null, text: fields.emoji ?? emoji, style: null };
      case CrestChargeKind.monogram.name: return { kind, symbol: null, text: fields.letters ?? letters, style: fields.style ?? letterStyle };
      default: return { kind: CrestChargeKind.none, symbol: null, text: null, style: null };
    }
  };
  const choose = (kind: CrestChargeKind) => {
    setSource(kind);
    writeCrest({ ...crest, charge: chargeOf(kind) });
  };

  const words = search.trim().toLowerCase();
  const matching = words ? selectableSymbols.filter((symbol) => symbol.title.toLowerCase().includes(words)) : selectableSymbols;
  const shown = words || showsAll ? matching : matching.slice(0, firstEmblems);
  const defaultCharge = resolvedCharge(defaults.crest);

  return (
    <div className="crest-emblem">
      <MenuRow title="Source" value={source.name} choices={CrestChargeKind.all.map((kind) => ({ value: kind.name, label: kind.title }))}
        onChange={(name) => choose(CrestChargeKind.named(name) ?? CrestChargeKind.none)}
        onReset={chargeKey(charge) !== chargeKey(defaultCharge) ? () => writeCrest({ ...crest, charge: defaults.crest.charge }) : null} />
      {source.name === CrestChargeKind.heraldic.name && (
        <div className="crest-emblem-body">
          <label className="crest-emblem-search-title" htmlFor={searchId}>Find an emblem</label>
          <span className="settings-text-field">
            <Symbol name="magnifyingglass" size={13} className="crest-emblem-search-glyph" />
            <input id={searchId} placeholder="Find an emblem" value={search} onChange={(event) => setSearch(event.target.value)} />
          </span>
          {shown.length > 0 ? (
            <div className="forge-gallery crest-emblem-grid">
              {shown.map((symbol) => (
                <ChoiceTile key={symbol.name} title={symbol.title}
                  selected={charge.kind.name === CrestChargeKind.heraldic.name && charge.symbol?.name === symbol.name}
                  onChoose={() => writeCrest({ ...crest, symbol, charge: null })}>
                  <SpaceCrestIcon branding={{ ...preview, iconStyle: SpaceIconStyle.layeredCrest, crest: { ...preview.crest, symbol, charge: null } }}
                    size={emblemCrest} />
                </ChoiceTile>
              ))}
            </div>
          ) : (
            <p className="crest-emblem-caption">No matching emblems. Try an SF Symbol or a monogram.</p>
          )}
          {!words && matching.length > firstEmblems && (
            <button type="button" className="crest-emblem-more" onClick={() => setShowsAll((all) => !all)}>
              {showsAll ? "Show fewer emblems" : `Browse all emblems (${matching.length})`}
            </button>
          )}
        </div>
      )}
      {source.name === CrestChargeKind.system.name && (
        <div className="crest-emblem-body">
          <SymbolPicker inline current={charge.kind.name === CrestChargeKind.system.name ? charge.text ?? "" : ""}
            onChoose={(name) => {
              setSystemName(name);
              writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.system, { system: name }) });
            }} />
        </div>
      )}
      {source.name === CrestChargeKind.emoji.name && (
        <div className="crest-emblem-body">
          <button ref={emojiButton} type="button" className="forge-artwork-button" aria-label="Choose Emoji" aria-description={emoji}
            onClick={() => setPicksEmoji(emojiButton.current?.getBoundingClientRect() ?? null)}>
            <span className="forge-artwork"><span className="forge-artwork-emoji">{emoji}</span></span>
            <span className="forge-artwork-text">
              <span className="forge-artwork-title">Emoji</span>
              <span className="forge-artwork-detail">Change emoji</span>
            </span>
            <Symbol name="chevron.right" size={11} strokeWidth={2.5} />
          </button>
          <AnimatePresence>
            {picksEmoji && (
              <Popover key="emblem" anchor={picksEmoji} label="Emblem" onClose={() => setPicksEmoji(null)}>
                <EmojiPicker title="Emblem" current={emoji} resetTitle={null}
                  onChoose={(chosen) => {
                    setEmoji(chosen);
                    writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.emoji, { emoji: chosen }) });
                    setPicksEmoji(null);
                  }}
                  onReset={() => setPicksEmoji(null)} />
              </Popover>
            )}
          </AnimatePresence>
        </div>
      )}
      {source.name === CrestChargeKind.monogram.name && (
        <>
          <Row title="Letters">
            <span className="settings-text-field crest-monogram-field">
              <input aria-label="Letters" placeholder="One or two letters" value={letters} maxLength={2}
                onChange={(event) => {
                  const typed = event.target.value;
                  setLetters(typed);
                  if (typed.trim()) writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.monogram, { letters: typed }) });
                }} />
            </span>
          </Row>
          <Row title="Letter style">
            <Segmented label="Letter style" value={letterStyle.name}
              choices={MonogramStyles.all.map((style) => ({ value: style.name, label: style.title }))}
              onChange={(name) => {
                const style = MonogramStyles.all.find((each) => each.name === name) ?? MonogramStyles.serif;
                setLetterStyle(style);
                writeCrest({ ...crest, charge: chargeOf(CrestChargeKind.monogram, { style }) });
              }} />
          </Row>
        </>
      )}
      {source.name !== CrestChargeKind.none.name && (
        <MenuRow title="Arrangement" value={crest.chargeLayout.name}
          choices={layoutChoices(crest.chargeLayout).map((layout) => ({ value: layout.name, label: layout.title }))}
          onChange={(name) => {
            const layout = layoutChoices(crest.chargeLayout).find((each) => each.name === name);
            if (layout) writeCrest({ ...crest, chargeLayout: layout });
          }}
          onReset={crest.chargeLayout.name !== defaults.crest.chargeLayout.name
            ? () => writeCrest({ ...crest, chargeLayout: defaults.crest.chargeLayout }) : null} />
      )}
    </div>
  );
}

/** One, Two and Three, and the crest's own arrangement where it wears another. */
function layoutChoices(worn: CrestChargeLayout): readonly CrestChargeLayout[] {
  return offeredLayouts.some((layout) => layout.name === worn.name) ? offeredLayouts : [...offeredLayouts, worn];
}

/** A row with a menu of choices and a reset once it differs from the starting look. */
function MenuRow({ title, value, choices, onChange, onReset }: {
  title: string;
  value: string;
  choices: readonly { readonly value: string; readonly label: string }[];
  onChange: (value: string) => void;
  onReset: (() => void) | null;
}) {
  const id = useId();
  return (
    <Row title={title} htmlFor={id} onReset={onReset}>
      <span className="settings-select">
        <select id={id} value={value} onChange={(event) => onChange(event.target.value)}>
          {choices.map((choice) => <option key={choice.value} value={choice.value}>{choice.label}</option>)}
        </select>
        <Symbol name="chevron.up.chevron.down" size={11} className="settings-select-glyph" />
      </span>
    </Row>
  );
}

/** BrowserCrestStudioChoice: artwork in a 64 by 58 frame over a two-line title. */
export function ChoiceTile({ title, selected, onChoose, children }: {
  title: string;
  selected: boolean;
  onChoose: () => void;
  children: ReactNode;
}) {
  return (
    <button type="button" className={`forge-card forge-choice${selected ? " selected" : ""}`} aria-label={title} aria-pressed={selected}
      title={title} onClick={onChoose}>
      <span className="forge-choice-art">{children}</span>
      <span className="forge-choice-title">{title}</span>
    </button>
  );
}

/**
 * BrowserSystemSymbolPicker: a search over the symbols this interface
 * draws, every word a part of the name; in a popover with Done, or inline
 * in the Emblem step.
 */
export function SymbolPicker({ current, onChoose, onDone, inline = false }: {
  current: string;
  onChoose: (name: string) => void;
  onDone?: () => void;
  inline?: boolean;
}) {
  const [query, setQuery] = useState("");
  const words = query.toLowerCase().split(/[\s.]+/).filter(Boolean);
  const shown = symbolNames.filter((name) => words.every((word) => name.toLowerCase().includes(word)));
  return (
    <div className={`symbol-picker${inline ? " inline" : ""}`}>
      {!inline && (
        <div className="picker-header">
          <span className="picker-title">SF Symbols</span>
          <button type="button" className="symbol-picker-done" onClick={onDone}>Done</button>
        </div>
      )}
      <input className={inline ? "settings-text-field symbol-picker-search" : "emoji-field"} placeholder="Search symbols" aria-label="Search symbols"
        value={query} autoFocus={!inline} onChange={(event) => setQuery(event.target.value)} />
      <div className="symbol-grid">
        {shown.map((name) => (
          <button key={name} type="button" className={`forge-card symbol-choice${name === current ? " selected" : ""}`} title={name}
            aria-label={name} onClick={() => onChoose(name)}>
            <Symbol name={name} size={24} />
            <span>{name.replace(/\./g, " ")}</span>
          </button>
        ))}
      </div>
      <span className="symbol-count">{shown.length} symbols</span>
    </div>
  );
}
