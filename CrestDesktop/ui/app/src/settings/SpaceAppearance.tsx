import {
  type SpaceBannerPattern,
  SpaceBannerPattern as BannerPatterns,
  type SpaceBranding,
  SetSpaceBranding,
  SetSpaceIdentity,
  SpaceHouse,
  SpaceHouseStyle,
  SpaceIconStyle,
  type SpaceState,
  SpaceTextColorMode,
  SpaceThemeModeKinds,
  Tincture,
} from "@crest/contracts";
import { AnimatePresence } from "motion/react";
import { useCallback, useEffect, useId, useRef, useState } from "react";

import type { Session } from "../boot";
import { emojiOf } from "../branding";
import { EmojiPicker, Popover } from "../shell/pickers";
import { BannerLayers } from "../shell/SpaceBanner";
import { sameColor } from "../spaces/color-harmony";
import { accentFill, backgroundFill, fillPaint, type SpaceFill } from "../spaces/space-fills";
import {
  applyingHouse,
  applyingPalette,
  type CrestLayer,
  crestFollowsSpace,
  crestLayers,
  type CrestStep,
  followingSpaceColors,
  layerFill,
  houseTileLook,
  paletteAccent,
  paletteBackground,
  patternFill,
  showsPattern,
  spacePalettes,
  startingLook,
  wearingPattern,
  wearsHouse,
  shuffledLook,
  wearsPalette,
  withAccentFill,
  withBackgroundFill,
  withLayerFill,
  withPatternFill,
} from "../spaces/space-look";
import { SpaceCrestIcon, SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { Symbol } from "../symbols";
import { ColorPopoverContent } from "./ColorPopover";
import { Button, Group, Row, Segmented } from "./controls";
import { ChoiceTile, CrestStudio, initialCrestStep, rememberCrestStep, SymbolPicker } from "./CrestStudio";

/** BrowserCrestStudio's undo depth: the oldest look goes past it. */
const historyLimit = 40;

/**
 * The colors a well edits: the Space's Background, its Accent, and the color
 * its sidebar pattern wears, or a part of its crest, by the layer's slot.
 */
type WellRole = "background" | "accent" | "pattern" | number;

const sidebarRoles = ["background", "accent", "pattern"] as const;
const sidebarTitles = { background: "Background", accent: "Accent", pattern: "Pattern" } as const;

const wellTitle = (role: WellRole) => (typeof role === "number" ? crestLayers[role].title : sidebarTitles[role]);

function wellFill(role: WellRole, look: SpaceBranding): SpaceFill {
  if (typeof role === "number") return layerFill(look, crestLayers[role]);
  return role === "background" ? backgroundFill(look) : role === "accent" ? accentFill(look) : patternFill(look);
}

function withWellFill(role: WellRole, look: SpaceBranding, fill: SpaceFill): SpaceBranding {
  if (typeof role === "number") return withLayerFill(look, crestLayers[role], fill);
  return role === "background" ? withBackgroundFill(look, fill) : role === "accent" ? withAccentFill(look, fill) : withPatternFill(look, fill);
}

const sameLook = (left: SpaceBranding, right: SpaceBranding) => JSON.stringify(left) === JSON.stringify(right);

/** A fill's name: Gradient, the tincture its color is, or Custom. */
function colorName(fill: SpaceFill): string {
  if (fill.colors.length > 1) return "Gradient";
  return Tincture.all.find((tincture) => sameColor(tincture.color, fill.colors[0]))?.title ?? "Custom";
}

/**
 * A Space's Appearance page, as the Mac's BrowserSpaceEditorView draws its
 * BrowserCrestForge: the Space's crest on its own sidebar field beside its
 * colors, with Undo; its palettes; its icon, a starter crest, a symbol or an
 * emoji; and More Customization, the sidebar's pattern, strength, fade,
 * folder colors, texture and text. Every change saves the whole look
 * (SetSpaceBranding), which the core normalizes; a symbol saves the Space's
 * identity (SetSpaceIdentity). The page is keyed by its Space, so its undo
 * history is the Space's own.
 */
export function SpaceAppearance({ session, space }: { session: Session; space: SpaceState }) {
  // A drag's looks show at once and save as the core takes them; the page shows the drag's while it runs,
  // and its last until the core's look arrives.
  const [draft, setDraft] = useState<SpaceBranding | null>(null);
  const branding = draft ?? space.settings.look;
  const [history, setHistory] = useState<readonly SpaceBranding[]>([]);
  const [showsMore, setShowsMore] = useState(false);
  const [step, setStep] = useState<CrestStep>(initialCrestStep);
  const dragStart = useRef<SpaceBranding | null>(null);
  const dragLatest = useRef<SpaceBranding | null>(null);
  const pending = useRef<{ branding: SpaceBranding; frame: number } | null>(null);
  const [well, setWell] = useState<{ role: WellRole; anchor: DOMRect; element: HTMLElement } | null>(null);
  const flushWell = useRef<(() => void) | null>(null);
  const defaults = useRef(startingLook(space.settings.look) ?? space.settings.look);

  const send = useCallback((next: SpaceBranding) => {
    void session.core.send(SetSpaceBranding({ workspaceId: session.workspaceId, spaceId: space.id, branding: next })).catch(() => {});
  }, [session, space.id]);

  /** Saves `next`, one undo step from the look before it. */
  const write = (next: SpaceBranding) => {
    setHistory((past) => [...past, branding].slice(-historyLimit));
    send(next);
  };

  /**
   * A drag's look, `change` made to the drag's newest: shown at once, saved
   * at most once a frame, and one undo step for the whole drag. A color
   * popover's whole session is one drag.
   */
  const drag = (change: (look: SpaceBranding) => SpaceBranding) => {
    const next = change(dragLatest.current ?? branding);
    dragStart.current ??= branding;
    dragLatest.current = next;
    setDraft(next);
    if (pending.current) {
      pending.current.branding = next;
      return;
    }
    pending.current = {
      branding: next,
      frame: requestAnimationFrame(() => {
        const latest = pending.current?.branding;
        pending.current = null;
        if (latest) send(latest);
      }),
    };
  };
  const endDrag = () => {
    const start = dragStart.current;
    const latest = dragLatest.current;
    dragStart.current = null;
    dragLatest.current = null;
    if (!start) return;
    if (pending.current) {
      cancelAnimationFrame(pending.current.frame);
      send(pending.current.branding);
      pending.current = null;
    }
    if (!latest || !sameLook(start, latest)) setHistory((past) => [...past, start].slice(-historyLimit));
  };
  useEffect(() => {
    if (!dragStart.current) setDraft(null);
  }, [space.settings.look]);
  useEffect(() => () => {
    if (pending.current) cancelAnimationFrame(pending.current.frame);
  }, []);

  const closeWell = () => {
    flushWell.current?.();
    setWell(null);
    endDrag();
  };
  /** Opens the popover for `role` under `element`, or closes it when it is that well's. */
  const toggleWell = (role: WellRole, element: HTMLElement) => {
    if (well?.element === element) {
      closeWell();
      return;
    }
    if (well) closeWell();
    setWell({ role, anchor: element.getBoundingClientRect(), element });
  };

  /** A crest swatch whose part the crest doesn't draw opens the step that adds it. */
  const openStep = (next: CrestStep) => {
    rememberCrestStep(next);
    setStep(next);
    setShowsMore(true);
  };

  const undo = () => {
    const previous = history.at(-1);
    if (!previous) return;
    setHistory((past) => past.slice(0, -1));
    send(previous);
  };

  /** A symbol or emoji for the Space's icon, which stops it drawing a crest. */
  const wear = (symbol: string) => {
    void session.core.send(SetSpaceIdentity({
      workspaceId: session.workspaceId, spaceId: space.id, name: space.settings.name, symbol, accent: space.settings.accent,
    })).catch(() => {});
    if (branding.iconStyle !== SpaceIconStyle.simpleSymbol) {
      write({ ...branding, iconStyle: SpaceIconStyle.simpleSymbol, hasCustomAppearance: true });
    }
  };

  return (
    <div className="space-appearance" data-testid="space-customization-controls">
      <section className="space-appearance-section">
        <Stage branding={branding} symbol={space.settings.symbol} canUndo={history.length > 0} onUndo={undo}
          onShuffle={() => write(shuffledLook(branding))}
          showsCrest={showsMore && branding.iconStyle === SpaceIconStyle.layeredCrest}
          openWell={well?.element.closest(".forge-stage") ? well.role : null} onWell={toggleWell} onStep={openStep} />
        <PalettePicker className="settings-card" branding={branding} onChoose={write} />
      </section>

      <section className="space-appearance-section">
        <h3 className="forge-heading">Icon</h3>
        <IconPicker branding={branding} symbol={space.settings.symbol}
          onCrest={(house) => write(house ? applyingHouse(house, branding) : { ...branding, iconStyle: SpaceIconStyle.layeredCrest, hasCustomAppearance: true })}
          onWear={wear} />
      </section>

      <section className="space-appearance-section">
        <button type="button" className="settings-card forge-more" aria-expanded={showsMore} data-testid="more-customization"
          onClick={() => setShowsMore((shown) => !shown)}>
          <span>More Customization</span>
          <Symbol name="chevron.right" size={11} strokeWidth={2.5} className="forge-more-chevron" />
        </button>
      </section>

      {showsMore && (
        <>
          <Group title="Sidebar">
            <div className="forge-gallery" data-testid="space-sidebar-patterns">
              {BannerPatterns.all.map((pattern) => (
                <PatternTile key={pattern.name} pattern={pattern} branding={dragStart.current ?? branding}
                  selected={branding.themeMode.kind === SpaceThemeModeKinds.Gradient ? pattern === BannerPatterns.solid : branding.bannerPattern === pattern}
                  onChoose={() => write(wearingPattern(branding, pattern))} />
              ))}
            </div>
          </Group>
          <Group>
            {showsPattern(branding) && (
              <Row title="Pattern color">
                <ColorWell title="Pattern color" fill={patternFill(branding)}
                  selected={well?.role === "pattern" && !well.element.closest(".forge-stage")}
                  onToggle={(element) => toggleWell("pattern", element)} />
              </Row>
            )}
            <SliderRow title="Intensity" value={branding.bannerStrength} defaultValue={defaults.current.bannerStrength}
              onDrag={(bannerStrength) => drag((look) => ({ ...look, bannerStrength, hasCustomAppearance: true }))} onEnd={endDrag}
              onReset={(bannerStrength) => write({ ...branding, bannerStrength, hasCustomAppearance: true })} />
            <SliderRow title="Readability fade" value={branding.readabilityFade} defaultValue={defaults.current.readabilityFade}
              onDrag={(readabilityFade) => drag((look) => ({ ...look, readabilityFade, hasCustomAppearance: true }))} onEnd={endDrag}
              onReset={(readabilityFade) => write({ ...branding, readabilityFade, hasCustomAppearance: true })} />
            <SliderRow title="Folder colors" value={branding.folderColorIntensity} defaultValue={defaults.current.folderColorIntensity}
              onDrag={(folderColorIntensity) => drag((look) => ({ ...look, folderColorIntensity, hasCustomAppearance: true }))} onEnd={endDrag}
              onReset={(folderColorIntensity) => write({ ...branding, folderColorIntensity, hasCustomAppearance: true })} />
            <SliderRow title="Texture" value={branding.textureStrength} defaultValue={defaults.current.textureStrength}
              readout={(value) => (value <= 0 ? "None" : value >= 1 ? "Full" : `${Math.round(value * 100)}%`)}
              onDrag={(textureStrength) => drag((look) => ({ ...look, textureStrength, hasCustomAppearance: true }))} onEnd={endDrag}
              onReset={(textureStrength) => write({ ...branding, textureStrength, hasCustomAppearance: true })} />
            <Row title="Text"
              onReset={branding.textColorMode !== defaults.current.textColorMode
                ? () => write({ ...branding, textColorMode: defaults.current.textColorMode, hasCustomAppearance: true }) : null}>
              <Segmented label="Text" value={branding.textColorMode}
                choices={SpaceTextColorMode.all.map((mode) => ({ value: mode, label: mode.title }))}
                onChange={(textColorMode) => write({ ...branding, textColorMode, hasCustomAppearance: true })} />
            </Row>
          </Group>
          {branding.iconStyle === SpaceIconStyle.layeredCrest && (
            <>
              <CrestStudio branding={branding} preview={dragStart.current ?? branding} defaults={defaults.current} step={step}
                onStep={setStep} write={write} />
              {!crestFollowsSpace(branding) && (
                <Group>
                  <Row title="The crest has colors of its own.">
                    <Button onClick={() => write(followingSpaceColors(branding))}>Use Space Colors</Button>
                  </Row>
                </Group>
              )}
            </>
          )}
        </>
      )}
      <AnimatePresence>
        {well && (
          <Popover key={`${well.role}-${well.anchor.x}-${well.anchor.y}`} anchor={well.anchor} label={wellTitle(well.role)} edge="bottom"
            ignore={well.element} className="color-popover" onClose={closeWell}>
            <ColorPopoverContent fill={wellFill(well.role, branding)} flush={flushWell}
              onCommit={(fill) => drag((look) => withWellFill(well.role, look, fill))}
              texture={well.role === "background"
                ? { value: branding.textureStrength, onChange: (textureStrength) => drag((look) => ({ ...look, textureStrength, hasCustomAppearance: true })) }
                : null} />
          </Popover>
        )}
      </AnimatePresence>
    </div>
  );
}

/**
 * BrowserCrestForgeStage: the Space's icon at 188 on its own sidebar field,
 * shaded toward the trailing edge, its colors beside it, and while More
 * Customization shows a crest, the crest's parts' colors under them, with
 * Shuffle and Undo at the top. The stage reads dark whatever the Space.
 */
function Stage({ branding, symbol, canUndo, onUndo, onShuffle, showsCrest, openWell, onWell, onStep }: {
  branding: SpaceBranding;
  symbol: string;
  canUndo: boolean;
  onUndo: () => void;
  onShuffle: () => void;
  showsCrest: boolean;
  openWell: WellRole | null;
  onWell: (role: WellRole, element: HTMLElement) => void;
  onStep: (step: CrestStep) => void;
}) {
  const stage = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 720, height: 284 });
  useEffect(() => {
    const element = stage.current;
    if (!element) return;
    // The field fills the stage's whole box, its padding included.
    const observer = new ResizeObserver(() => setSize({ width: element.offsetWidth, height: element.offsetHeight }));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return (
    <div ref={stage} className="forge-stage" data-testid="space-forge-stage">
      <div className="forge-stage-field" aria-hidden>
        <BannerLayers branding={branding} width={size.width} height={size.height} />
        <div className="forge-stage-shade" />
      </div>
      <div className="forge-stage-mark" aria-label="Crest preview" role="img">
        <SpaceIdentityIcon symbol={symbol} branding={branding} size={188} />
      </div>
      <div className="forge-swatch-groups">
        <div className="forge-swatch-group">
          <h4>Colors</h4>
          <div className="forge-swatches">
            {sidebarRoles.filter((role) => role !== "pattern" || showsPattern(branding)).map((role) => (
              <Swatch key={role} title={sidebarTitles[role]} fill={wellFill(role, branding)} selected={openWell === role}
                onToggle={(element) => onWell(role, element)} />
            ))}
          </div>
        </div>
        {showsCrest && (
          <div className="forge-swatch-group">
            <h4>Crest</h4>
            <div className="forge-swatches">
              {crestLayers.map((layer) => (
                <LayerSwatch key={layer.slot} layer={layer} branding={branding} selected={openWell === layer.slot}
                  onToggle={(element) => (layer.draws(branding.crest) ? onWell(layer.slot, element) : onStep(layer.step))} />
              ))}
            </div>
          </div>
        )}
      </div>
      <div className="forge-tools">
        <button type="button" className="forge-tool" data-testid="space-forge-shuffle" onClick={onShuffle}>
          <Symbol name="shuffle" size={12} strokeWidth={2} />
          <span>Shuffle</span>
        </button>
        <button type="button" className="forge-tool" disabled={!canUndo} data-testid="space-forge-undo" onClick={onUndo}>
          <Symbol name="arrow.uturn.backward" size={12} strokeWidth={2} />
          <span>Undo</span>
        </button>
      </div>
    </div>
  );
}

/** BrowserCrestForgeSwatch: a 28-point circle of the fill over its title, which opens its color popover. */
function Swatch({ title, fill, selected, onToggle }: {
  title: string;
  fill: SpaceFill;
  selected: boolean;
  onToggle: (element: HTMLElement) => void;
}) {
  const name = colorName(fill);
  return (
    <button type="button" className={`forge-swatch${selected ? " selected" : ""}`} title={name === "Gradient" ? title : name}
      aria-label={title} aria-description={name} aria-expanded={selected} onClick={(event) => onToggle(event.currentTarget)}>
      <FillDot fill={fill} size={28} ring />
      <span className="forge-swatch-title">{title}</span>
    </button>
  );
}

/**
 * A crest part's swatch: its color, dimmed where the crest doesn't draw the
 * part, when a press opens the step that adds it instead of a popover.
 */
function LayerSwatch({ layer, branding, selected, onToggle }: {
  layer: CrestLayer;
  branding: SpaceBranding;
  selected: boolean;
  onToggle: (element: HTMLElement) => void;
}) {
  const fill = layerFill(branding, layer);
  const drawn = layer.draws(branding.crest);
  const name = colorName(fill);
  return (
    <button type="button" className={`forge-swatch${selected ? " selected" : ""}${drawn ? "" : " undrawn"}`}
      title={drawn ? (name === "Gradient" ? layer.title : name) : layer.hint} aria-label={layer.title} aria-description={drawn ? name : layer.hint}
      aria-expanded={drawn ? selected : undefined} onClick={(event) => onToggle(event.currentTarget)}>
      <FillDot fill={fill} size={28} ring />
      <span className="forge-swatch-title">{layer.title}</span>
    </button>
  );
}

/** CrestColorWell: a 30-point circle of the fill in a ring, which opens its color popover below it. */
export function ColorWell({ title, fill, selected, onToggle }: {
  title: string;
  fill: SpaceFill;
  selected: boolean;
  onToggle: (element: HTMLElement) => void;
}) {
  return (
    <button type="button" className={`color-well${selected ? " selected" : ""}`} title={title} aria-label={title}
      aria-description={fill.colors.length > 1 ? "Gradient" : "Color"} aria-expanded={selected} onClick={(event) => onToggle(event.currentTarget)}>
      <FillDot fill={fill} size={30} line />
    </button>
  );
}

/** A circle filled with a color or a gradient, as the Mac blends one, with the stage's light inner ring or the brand's line where asked. */
function FillDot({ fill, size, ring = false, line = false }: { fill: SpaceFill; size: number; ring?: boolean; line?: boolean }) {
  const id = `fill-dot-${useId().replace(/:/g, "")}`;
  const { paint, definition } = fillPaint(fill, id, { x: 0, y: 0, width: size, height: size });
  return (
    <svg className="fill-dot" width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
      <defs>{definition}</defs>
      <circle cx={size / 2} cy={size / 2} r={size / 2} fill={paint} />
      {ring && <circle cx={size / 2} cy={size / 2} r={size / 2 - 0.75} fill="none" stroke="rgb(255 255 255 / 0.35)" strokeWidth={1.5} />}
      {line && <circle className="fill-dot-line" cx={size / 2} cy={size / 2} r={size / 2 - 0.5} fill="none" strokeWidth={1} />}
    </svg>
  );
}

/** BrowserSpacePalettePicker: the palettes as cards, the one the Space wears selected; choosing one applies it. */
export function PalettePicker({ branding, onChoose, className = "" }: {
  branding: SpaceBranding;
  onChoose: (next: SpaceBranding) => void;
  className?: string;
}) {
  return (
    <div className={`space-palettes ${className}`} role="group" aria-label="Palettes" data-testid="space-palettes">
      {spacePalettes.map((palette) => {
        const worn = wearsPalette(palette, branding);
        return (
          <button key={palette.name} type="button" className={`forge-card space-palette${worn ? " selected" : ""}`}
            aria-label={palette.title} aria-pressed={worn} title={palette.title} data-testid={`space-palette-${palette.name}`}
            onClick={() => onChoose(applyingPalette(palette, branding))}>
            <PaletteSwatch background={paletteBackground(palette)} accent={paletteAccent(palette)} />
            <span className="space-palette-title">{palette.title}</span>
          </button>
        );
      })}
    </div>
  );
}

/** BrowserSpacePalettePicker's swatch: the Background across the tile, the Accent's dot where the icon sits. */
function PaletteSwatch({ background, accent }: { background: SpaceFill; accent: SpaceFill }) {
  const id = `palette-${useId().replace(/:/g, "")}`;
  const { paint, definition } = fillPaint(background, id, { x: 0, y: 0, width: 100, height: 24 });
  return (
    <span className="space-palette-swatch">
      <svg width="100%" height="24" viewBox="0 0 100 24" preserveAspectRatio="none" aria-hidden>
        <defs>{definition}</defs>
        <rect width="100" height="24" fill={paint} />
      </svg>
      <span className="space-palette-accent"><FillDot fill={accent} size={10} /></span>
    </span>
  );
}

/** A sidebar pattern's tile: the Space's field wearing it, at 56 by 48. */
function PatternTile({ pattern, branding, selected, onChoose }: {
  pattern: SpaceBannerPattern;
  branding: SpaceBranding;
  selected: boolean;
  onChoose: () => void;
}) {
  return (
    <ChoiceTile title={pattern.title} selected={selected} onChoose={onChoose}>
      <span className="forge-pattern-art">
        <BannerLayers branding={wearingPattern(branding, pattern)} width={56} height={48} />
      </span>
    </ChoiceTile>
  );
}

type IconKind = "crest" | "symbol" | "emoji";

/**
 * BrowserSpaceIconPicker: Crest, Symbol or Emoji. A crest offers the starter
 * houses, Simple then Heraldic, each in its own colors; a symbol and an
 * emoji each open a picker, and wear what is picked.
 */
export function IconPicker({ branding, symbol, onCrest, onWear }: {
  branding: SpaceBranding;
  symbol: string;
  onCrest: (house: SpaceHouse | null) => void;
  onWear: (symbol: string) => void;
}) {
  const emoji = emojiOf(symbol);
  const worn: IconKind = branding.iconStyle === SpaceIconStyle.layeredCrest ? "crest" : emoji ? "emoji" : "symbol";
  // Choosing a first emoji shows the Emoji kind before anything is worn.
  const [override, setOverride] = useState<IconKind | null>(null);
  useEffect(() => setOverride(null), [branding.iconStyle, symbol]);
  const kind = override ?? worn;
  const [picking, setPicking] = useState<{ kind: "symbol" | "emoji"; anchor: DOMRect } | null>(null);
  const button = useRef<HTMLButtonElement>(null);
  const open = (which: "symbol" | "emoji") => {
    const anchor = button.current?.getBoundingClientRect();
    if (anchor) setPicking({ kind: which, anchor });
  };
  return (
    <div className="settings-card forge-icon">
      <div className="forge-icon-kind" data-testid="space-icon-kind">
        <Segmented label="Icon" value={kind}
          choices={[{ value: "crest", label: "Crest" }, { value: "symbol", label: "Symbol" }, { value: "emoji", label: "Emoji" }]}
          onChange={(next: IconKind) => {
            if (next === "crest") onCrest(null);
            else if (next === "symbol") onWear(emoji ? "sparkles" : symbol);
            else {
              setOverride("emoji");
              requestAnimationFrame(() => open("emoji"));
            }
          }} />
      </div>
      {kind === "crest" ? (
        <div className="forge-starters" data-testid="space-starter-crests">
          {SpaceHouseStyle.all.map((style) => (
            <div key={style.name} className="forge-starter-group">
              <h4 className="forge-caps">{style.title}</h4>
              <div className="forge-gallery">
                {SpaceHouse.all.filter((house) => house.style === style).map((house) => (
                  <ChoiceTile key={house.name} title={house.title} selected={wearsHouse(house, branding)} onChoose={() => onCrest(house)}>
                    <SpaceCrestIcon branding={houseTileLook(house)} size={56} />
                  </ChoiceTile>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <button ref={button} type="button" className="forge-artwork-button"
          aria-label={kind === "symbol" ? "Choose SF Symbol" : "Choose Emoji"} onClick={() => open(kind)}>
          <span className="forge-artwork">
            {kind === "emoji"
              ? (emoji ? <span className="forge-artwork-emoji">{emoji}</span> : <Symbol name="face.smiling" size={24} />)
              : <Symbol name={symbol} size={24} />}
          </span>
          <span className="forge-artwork-text">
            <span className="forge-artwork-title">{kind === "symbol" ? "SF Symbol" : "Emoji"}</span>
            <span className="forge-artwork-detail">
              {kind === "symbol" ? (emoji ? "Browse symbols" : symbol) : emoji ? "Change emoji" : "Choose an emoji"}
            </span>
          </span>
          <Symbol name="chevron.right" size={11} strokeWidth={2.5} />
        </button>
      )}
      <AnimatePresence>
        {picking?.kind === "emoji" && (
          <Popover key="emoji" anchor={picking.anchor} label="Space Icon" onClose={() => setPicking(null)}>
            <EmojiPicker title="Space Icon" current={emoji} resetTitle={null}
              onChoose={(chosen) => {
                onWear(`crest.emoji:${chosen}`);
                setPicking(null);
              }}
              onReset={() => setPicking(null)} />
          </Popover>
        )}
        {picking?.kind === "symbol" && (
          <Popover key="symbol" anchor={picking.anchor} label="SF Symbols" onClose={() => setPicking(null)}>
            <SymbolPicker current={emoji ? "" : symbol}
              onChoose={(name) => {
                onWear(name);
                setPicking(null);
              }}
              onDone={() => setPicking(null)} />
          </Popover>
        )}
      </AnimatePresence>
    </div>
  );
}

/** CrestSettingSlider: the title, a reset once it differs from the starting look, a slider, and its readout. */
function SliderRow({ title, value, defaultValue, readout = (v) => `${Math.round(v * 100)}%`, onDrag, onEnd, onReset }: {
  title: string;
  value: number;
  defaultValue: number;
  readout?: (value: number) => string;
  onDrag: (value: number) => void;
  onEnd: () => void;
  onReset: (value: number) => void;
}) {
  return (
    <Row title={title} onReset={Math.abs(value - defaultValue) > 0.0001 ? () => onReset(defaultValue) : null}>
      <input type="range" className="forge-slider" min={0} max={1} step={0.01} value={value} aria-label={title}
        onChange={(event) => onDrag(Number(event.target.value))} onPointerUp={onEnd} onKeyUp={onEnd} onBlur={onEnd} />
      <span className="forge-readout">{readout(value)}</span>
    </Row>
  );
}
