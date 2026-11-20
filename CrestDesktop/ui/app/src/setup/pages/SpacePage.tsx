import { type SpaceBranding, SpaceIconStyle } from "@crest/contracts";
import { AnimatePresence } from "motion/react";
import { useId, useRef, useState } from "react";

import type { Session } from "../../boot";
import { ColorPopoverContent } from "../../settings/ColorPopover";
import { Group, Row } from "../../settings/controls";
import { ColorWell, IconPicker, PalettePicker } from "../../settings/SpaceAppearance";
import { Popover } from "../../shell/pickers";
import { accentFill, backgroundFill } from "../../spaces/space-fills";
import { applyingHouse, withAccentFill, withBackgroundFill } from "../../spaces/space-look";
import { useSetupSpace } from "../use-setup-space";

type Well = "background" | "accent";
const wellTitles: Record<Well, string> = { background: "Background", accent: "Accent" };

/**
 * BrowserSetupSpacePage: a draft Space's name, its two colors and the
 * palettes, and its icon. Your Space edits the first Space; a Space's own
 * page under Spaces edits that one, titled with its name as it is typed.
 */
export function SpacePage({ session, spaceId, title }: { session: Session; spaceId: string | null; title: string | null }) {
  const { space, customization, customize, error } = useSetupSpace(session, spaceId);
  const [well, setWell] = useState<{ role: Well; anchor: DOMRect; element: HTMLElement } | null>(null);
  const flush = useRef<(() => void) | null>(null);
  const nameId = useId();
  if (!space || !customization) {
    return <div className="setup-page-content"><p className="setup-unavailable">No Space to Edit</p></div>;
  }
  const branding = customization.branding;
  const setBranding = (change: (look: SpaceBranding) => SpaceBranding) => customize((current) => ({ ...current, branding: change(current.branding) }));
  const closeWell = () => {
    flush.current?.();
    setWell(null);
  };
  const toggle = (role: Well, element: HTMLElement) => {
    if (well?.element === element) {
      closeWell();
      return;
    }
    if (well) closeWell();
    setWell({ role, anchor: element.getBoundingClientRect(), element });
  };
  return (
    <div className="setup-page-content">
      <h2 className="setup-page-heading">{title ?? (customization.name.trim() || "Untitled Space")}</h2>
      <div className="settings-group">
        <div className="settings-card">
          <Row title="Name" htmlFor={nameId}>
            <input id={nameId} className="setup-name-field" data-testid="setup-space-name" value={customization.name} placeholder="Name"
              spellCheck={false} onChange={(event) => {
                const name = event.target.value;
                customize((current) => ({ ...current, name }));
              }} />
          </Row>
        </div>
      </div>
      <Group title="Colors">
        <div className="setup-wells" data-testid="space-color-wells">
          {(["background", "accent"] as const).map((role) => (
            <span key={role} className="setup-well">
              <ColorWell title={wellTitles[role]} fill={role === "background" ? backgroundFill(branding) : accentFill(branding)}
                selected={well?.role === role} onToggle={(element) => toggle(role, element)} />
              <span className="setup-well-title">{wellTitles[role]}</span>
            </span>
          ))}
        </div>
        <PalettePicker className="setup-palettes" branding={branding} onChoose={(next) => setBranding(() => next)} />
      </Group>
      <section className="settings-group">
        <div className="settings-group-header"><h3>Icon</h3></div>
        <IconPicker branding={branding} symbol={customization.symbol}
          onCrest={(house) => setBranding((look) => (house
            ? applyingHouse(house, look)
            : { ...look, iconStyle: SpaceIconStyle.layeredCrest, hasCustomAppearance: true }))}
          // A symbol and the icon style it needs go in one change, which the core takes whole.
          onWear={(symbol) => customize((current) => ({
            ...current,
            symbol,
            branding: current.branding.iconStyle === SpaceIconStyle.simpleSymbol
              ? current.branding
              : { ...current.branding, iconStyle: SpaceIconStyle.simpleSymbol, hasCustomAppearance: true },
          }))} />
      </section>
      {error && <p className="setup-error" role="alert">{error}</p>}
      <AnimatePresence>
        {well && (
          <Popover key={`${well.role}-${well.anchor.x}-${well.anchor.y}`} anchor={well.anchor} label={wellTitles[well.role]} edge="bottom"
            ignore={well.element} className="color-popover" onClose={closeWell}>
            <ColorPopoverContent fill={well.role === "background" ? backgroundFill(branding) : accentFill(branding)} flush={flush}
              onCommit={(fill) => setBranding((look) => (well.role === "background" ? withBackgroundFill(look, fill) : withAccentFill(look, fill)))}
              texture={well.role === "background"
                ? { value: branding.textureStrength, onChange: (textureStrength) => setBranding((look) => ({ ...look, textureStrength, hasCustomAppearance: true })) }
                : null} />
          </Popover>
        )}
      </AnimatePresence>
    </div>
  );
}
