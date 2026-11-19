# Brand assets

## The Crest mark

Three rounded paper banners stacked on a navy tile: butter in front, coral in
the middle (9 grid units down) and sky at the back (18 down), each casting a
soft shadow. The mark is drawn on a 64-unit grid with a tile radius of 15.

- `crest-logo.svg` — the master mark, with a shadow under each banner. Use it
  anywhere above 32 px.
- `crest-favicon.svg` — the flat cut for 32 px and below: no shadows, and a
  2.6-unit navy keyline under the front two banners.
- `../favicon.ico` (16, 32 and 48 px) and `crest-icon-32.png` — the flat cut.
- `crest-icon-192.png` and `crest-icon-512.png` — the master mark, for the web
  app manifest.
- `apple-touch-icon.png` — the master mark on a full-bleed navy square, since
  iOS rounds the corners itself.

## Social and search previews

- `og-card.jpg` (1200 × 630) — the card for `og:image` and `twitter:image` on
  every page, the Help Center included: the mark, "Spaces for your browsing."
  and the section chips on cream. Its SVG source is `press/og-card.svg`.

## Press kit

`press/` holds everything the press kit page (`/press/`) offers, and
`press/crest-press-kit.zip` bundles it:

- `crest-mark.svg`, `crest-mark-1024.png`, `crest-mark-small.svg` — the mark.
- `crest-lockup.svg`, `crest-lockup-light.svg`, `crest-wordmark.svg` and their
  PNGs — the mark beside the wordmark, for light and dark backgrounds.
- `crest-app-icon.png`, `crest-app-icon-dark.png` — the app icon, exported from
  its Icon Composer document.
- `crest-avatar.png`, `crest-avatar-cream.png` (1024) — profile pictures that
  survive a round crop.
- `header-1500x500`, `header-1600x400`, `header-1920x384`, `header-960x540`,
  `header-2560x1440` — banners and headers for social accounts.
- `github-social-preview.png` (1280 × 640) — the repository's social preview.

Text in these files is Nunito outlined to paths, so the SVGs need no fonts.

## Colors and type

Crest blue `#2B6CC4` is for actions only: buttons, links and selection. Pages
sit on cream `#FBF5E6`, cards on paper `#FFFDF7` with a `#EADFC6` hairline,
text is ink `#172238`, and dark sections are slate `#2B3A5C`. Sky `#62A9D8`,
butter `#F2C14E`, coral `#E9604B` and sage `#8DBF9A` are brand colors and never
mark an action.

Headings, buttons and labels use SF Pro Rounded where the system has it and
Nunito elsewhere; body text uses the system font.

## Third-party assets

- `fonts/nunito-latin.woff2` and `fonts/nunito-latin-ext.woff2` — Nunito by the
  Nunito Project Authors, under the SIL Open Font License 1.1
  (`fonts/OFL.txt`). Served from this site so pages make no third-party font
  requests.

The surrounding labels and destinations identify third-party services (the App
Store, TestFlight, GitHub, Reddit, Discord and Ko-fi) without implying
sponsorship or affiliation.
