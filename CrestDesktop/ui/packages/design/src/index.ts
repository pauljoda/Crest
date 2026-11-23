/**
 * Crest's design tokens, as CrestShared/DesignSystem/Tokens names them. The
 * Mac and desktop interfaces draw from the same values, so a change to one
 * belongs in both until the tokens have one source both are generated from.
 */

/** `CrestRadius`: from a compact control to the rounded band of a large brand surface. */
export const radius = Object.freeze({ compact: 8, control: 12, card: 16, panel: 24, band: 48 });

/** `CrestSpacing`. */
export const spacing = Object.freeze({
  extraExtraSmall: 2,
  extraSmall: 4,
  small: 8,
  medium: 12,
  large: 16,
  extraLarge: 20,
  extraExtraLarge: 24,
  section: 32,
  screen: 40,
});

/** `CrestOpacity`. */
export const opacity = Object.freeze({
  brandHairline: 0.18,
  dropIndicator: 0.72,
  hover: 0.08,
  selection: 0.13,
  selectionBorder: 0.1,
  selectionShadow: 0.08,
  chromeSurface: 0.055,
  border: 0.12,
  darkSelectionLift: 0.1,
  darkSelectionBorder: 0.18,
  disabled: 0.5,
  unfocusedChrome: 0.5,
  controlShadow: 0.16,
  statusFill: 0.18,
});

/** `CrestLayout`. */
export const layout = Object.freeze({ hairline: 1, focusRing: 3, pinnedAccentBorderWidth: 2, sidebarRowHeight: 40 });

/**
 * `CrestBrandPalette`, as RGB: cream, paper and ink for grounds and text,
 * Crest blue for anything a person can press or select, and butter, coral
 * and sky, the three paper banners of the mark, kept for the mark, crests,
 * gradients and marketing, never for actions.
 */
export const brand = Object.freeze({
  ink: [23, 34, 56],
  slate: [43, 58, 92],
  cream: [251, 245, 230],
  paper: [255, 253, 247],
  /** The warm ground under a control on cream, such as a segmented picker's track. */
  parchment: [246, 238, 219],
  /** The warm hairline round a card on cream. */
  hairline: [234, 223, 198],
  crestBlue: [43, 108, 196],
  butter: [242, 193, 78],
  coral: [233, 96, 75],
  sky: [98, 169, 216],
  sage: [141, 191, 154],
  /** The gold of small caps labels on cream. */
  gold: [138, 106, 34],
} as const);

/**
 * `CrestBrandTheme`: the brand's roles in each scheme, as RGB. Cream and ink
 * trade places, paper's surface becomes slate, and Crest blue is lifted on
 * ink so it stays readable without reading as another color.
 */
export const brandTheme = Object.freeze({
  /** Anything a person can press or select, as a fill, stroke or glyph. */
  accent: { light: brand.crestBlue, dark: [79, 142, 224] },
  /** The accent when it is text, clearing 4.5:1 on canvas, surface and a selected row's wash. */
  accentText: { light: [34, 92, 172], dark: [122, 170, 235] },
  /** The fill of the one action that leads on, under white text. */
  action: { light: brand.crestBlue, dark: brand.crestBlue },
  canvas: { light: brand.cream, dark: brand.ink },
  surface: { light: brand.paper, dark: brand.slate },
  /** Small caps labels: gold on cream, butter on ink. */
  label: { light: brand.gold, dark: brand.butter },
} as const);

/** `CrestColor`'s status tones, light and dark, each 4.5:1 or more as text on Crest's surfaces. */
export const status = Object.freeze({
  danger: { light: [178, 50, 37], dark: [238, 106, 92] },
  warning: { light: [138, 90, 8], dark: [236, 190, 92] },
  success: { light: [47, 112, 66], dark: [134, 196, 142] },
} as const);

/**
 * `CrestTypography`. The Mac sets Crest's voice in SF Pro Rounded, heavy,
 * for hero lines, titles, buttons and small caps labels, over the system
 * face for body and supporting copy. Only Apple's systems carry SF Pro
 * Rounded, so the display face here is Nunito, the brand's own stand-in
 * (the website's too), bundled with the interface.
 */
export const typography = Object.freeze({
  system: '"Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif',
  display: '"Nunito", "Segoe UI Variable Display", system-ui, sans-serif',
  /** The display face's weight: heavy. */
  displayWeight: 800,
  displayPageSize: 24,
  displaySectionSize: 17,
});

/**
 * A spring as SwiftUI describes one: how long it visibly takes and how much
 * it overshoots. Motion's springs take the same two values.
 */
export interface Spring {
  readonly type: "spring";
  readonly visualDuration: number;
  readonly bounce: number;
}

const snappy = (duration: number): Spring => ({ type: "spring", visualDuration: duration, bounce: 0.15 });
const smooth = (duration: number): Spring => ({ type: "spring", visualDuration: duration, bounce: 0 });

/**
 * `CrestMotion`: motion named by role, never invented per view, at the
 * durations the Mac's #1254 gave them: every motion about a quarter shorter,
 * and a change of Space 0.28 s.
 */
export const motion = Object.freeze({
  press: { duration: 0.1, ease: "easeOut" } as const,
  surface: { duration: 0.1, ease: "easeInOut" } as const,
  hover: { duration: 0.1, ease: "easeInOut" } as const,
  /** Choosing one of a few, such as a color wheel's handle, and controls coming with it. */
  selection: { duration: 0.15, ease: "easeInOut" } as const,
  /** A color popping in or out, or springing to where it was put. */
  colorPop: { type: "spring", visualDuration: 0.3, bounce: 0.3 } as const,
  step: snappy(0.22),
  collection: snappy(0.17),
  dragPreview: smooth(0.14),
  navigation: snappy(0.2),
  chrome: smooth(0.2),
  sidebarMorph: smooth(0.21),
  floatingPane: smooth(0.18),
  /** Moving the page aside before a floating sidebar takes its seat. */
  sidebarDockApproach: smooth(0.16),
  /** The floating sidebar's short last step into its seat. */
  sidebarDockAttachment: smooth(0.12),
  /**
   * The floating sidebar coming out over the page as the pointer reaches the
   * window's edge: the Mac's floating pane (0.18) at its default sidebar
   * slide length, 160 ms of the 180 its sidebar motion is drawn at.
   */
  sidebarReveal: smooth(0.16),
  /**
   * The floating sidebar going once the pointer leaves it, as the Mac's
   * recording measures it (D02: 90% in about 90 ms), quicker than the 0.22
   * its source names.
   */
  sidebarRetreat: smooth(0.15),
  toolbar: snappy(0.18),
  feedbackPresentation: snappy(0.16),
  dismissal: { duration: 0.14, ease: "easeOut" } as const,
  disclosure: snappy(0.16),
  spaceSwipe: snappy(0.28),
  /** Aligning a chosen item within a scrolling picker. */
  scrollAlignment: snappy(0.2),
  /** A change of style, such as Space icons turning into dots. */
  styleChange: { duration: 0.25, ease: "easeInOut" } as const,
  /** A Peek coming in: a spring with a little more bounce than snappy, at the Mac's Peek animation time, 240 ms by default. */
  peekEntrance: { type: "spring", visualDuration: 0.24, bounce: 0.2 } as const,
  peekDismissal: snappy(0.16),
  palette: { duration: 0.14, ease: "easeInOut" } as const,
  /** Contents showing on a surface as it arrives, or clearing as it goes. */
  contentReveal: { duration: 0.12, ease: "easeOut" } as const,
  /** The old Space's address and site controls popping out of the address field. */
  addressSwapOut: { duration: 0.1, ease: "easeIn" } as const,
  /** The new Space's popping in, starting as the old ones finish: spring(0.28, bounce 0.25) after 0.07. */
  addressSwapIn: { type: "spring", visualDuration: 0.28, bounce: 0.25, delay: 0.07 } as const,
  /** Snappy with a little extra bounce. */
  contentNavigation: { type: "spring", visualDuration: 0.3, bounce: 0.19 } as const,
  /** The archive, history and downloads destinations coming out of the lists button. */
  utilityFanReveal: { type: "spring", visualDuration: 0.3, bounce: 0.05 } as const,
  /** Setup's pages sliding from one step to the next. */
  onboardingStep: snappy(0.26),
  /** Setup's sheet drawing back from the welcome to the steps, the preview coming in beside it. */
  onboardingSheet: smooth(0.4),
  /** The room behind Setup's preview taking the shown Space's look. */
  onboardingBackdropChange: { duration: 0.25, ease: "easeInOut" } as const,
  /** Setup handing over to the browser window it held back. */
  onboardingHandOver: smooth(0.32),
  /** Setup's step chips as the walk moves: their color, lift and title. */
  setupChips: smooth(0.45),
  /** The Getting Started guide changing chapter: its lessons coming and going. */
  guideChapter: { duration: 0.2, ease: "easeInOut" } as const,
  /** The guide's practice window taking its place for a chapter: SwiftUI's spring(response: 0.55, dampingFraction: 0.9). */
  guideStage: { type: "spring", visualDuration: 0.55, bounce: 0.1 } as const,
});

/**
 * A spring as a CSS easing, for animations the compositor runs from
 * keyframes: SwiftUI's spring of that duration and bounce (its response, and
 * a damping fraction of one less the bounce), sampled into `linear()`, and
 * how long it takes to come within `settled` of rest (a fraction of the way;
 * by default a hair, for what moves). A critically damped spring leaves rest
 * gently and arrives without overshoot, which no cubic-bezier draws.
 */
export function springEasing(spring: Spring, settled = 0.002): { readonly duration: number; readonly easing: string } {
  const { position, duration } = springCurve(spring, settled);
  const end = duration / 1000;
  const samples = 40;
  const points = Array.from({ length: samples + 1 }, (_, index) => (index === samples ? 1 : position((index / samples) * end)));
  return { duration: Math.round(duration), easing: `linear(${points.map((point) => point.toFixed(4)).join(", ")})` };
}

/**
 * A spring as a curve, for motion script draws each frame: how far along the
 * way it stands `seconds` after it starts from rest, and how many
 * milliseconds it takes to come within `settled` of rest.
 */
export function springCurve(spring: Spring, settled = 0.002): { readonly position: (seconds: number) => number; readonly duration: number } {
  const omega = (2 * Math.PI) / spring.visualDuration;
  const damping = Math.min(1, Math.max(0.01, 1 - spring.bounce));
  let position: (time: number) => number;
  let end: number;
  if (damping >= 1) {
    position = (time) => 1 - (1 + omega * time) * Math.exp(-omega * time);
    end = spring.visualDuration;
    while (1 - position(end) > settled) end += 0.005;
  } else {
    const ringing = omega * Math.sqrt(1 - damping * damping);
    const ratio = damping / Math.sqrt(1 - damping * damping);
    position = (time) => 1 - Math.exp(-damping * omega * time) * (Math.cos(ringing * time) + ratio * Math.sin(ringing * time));
    end = Math.log(1 / settled) / (damping * omega);
  }
  return { position, duration: end * 1000 };
}

/** Every token as a CSS custom property, for styles that do not read the values in script. */
export function cssVariables(): Record<string, string> {
  const variables: Record<string, string> = {};
  for (const [name, value] of Object.entries(radius)) variables[`--crest-radius-${name}`] = `${value}px`;
  for (const [name, value] of Object.entries(spacing)) variables[`--crest-space-${name}`] = `${value}px`;
  const kebab = (name: string) => name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
  for (const [name, value] of Object.entries(brand)) variables[`--crest-${kebab(name)}`] = `rgb(${value.join(" ")})`;
  for (const [name, { light, dark }] of Object.entries(brandTheme)) {
    variables[`--crest-${kebab(name)}-light`] = `${light.join(" ")}`;
    variables[`--crest-${kebab(name)}-dark`] = `${dark.join(" ")}`;
  }
  variables["--crest-font-system"] = typography.system;
  variables["--crest-font-display"] = typography.display;
  variables["--crest-font-display-weight"] = `${typography.displayWeight}`;
  // The floating sidebar's slides, which its stylesheet runs as transitions.
  for (const [name, spring] of [["reveal", motion.sidebarReveal], ["retreat", motion.sidebarRetreat]] as const) {
    const { duration, easing } = springEasing(spring);
    variables[`--crest-sidebar-${name}-duration`] = `${duration}ms`;
    variables[`--crest-sidebar-${name}-easing`] = easing;
  }
  variables["--crest-opacity-hover"] = `${opacity.hover}`;
  variables["--crest-opacity-selection"] = `${opacity.selection}`;
  variables["--crest-opacity-border"] = `${opacity.border}`;
  return variables;
}
