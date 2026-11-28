import { svelte } from "@sveltejs/vite-plugin-svelte";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig, searchForWorkspaceRoot } from "vite";

const peekSample = fileURLToPath(new URL("../../../CrestMac/Features/TransientBrowsing/Models/PeekSample.html", import.meta.url));
const fonts = fileURLToPath(new URL("../../../CrestShared/Resources/Fonts", import.meta.url));

/** Crest's app icons, which every Crest app shares and the Start Page shows. */
const appIcons = fileURLToPath(new URL("../../../CrestShared/Resources/AppIconPreviews.xcassets", import.meta.url));
/** The heraldic charges a Space's crest draws, shared with the Mac. */
const heraldry = fileURLToPath(new URL("../../../CrestShared/Resources/CrestHeraldry.xcassets", import.meta.url));
/** The search providers' logos the palette shows, shared with the Mac. */
const searchLogos = fileURLToPath(new URL("../../../CrestShared/Resources/SearchProviderLogos.xcassets", import.meta.url));
/** The marks the Getting Started practice's tabs wear, shared with the Mac. */
const guideLogos = fileURLToPath(new URL("../../../CrestShared/Resources/GettingStartedLogos.xcassets", import.meta.url));
/** Who drew the heraldic artwork the crest studio offers, which a Space page credits. */
const artworkCredits = fileURLToPath(new URL("../../../CrestShared/Resources/HeraldicArtworkCredits.txt", import.meta.url));

/** The version the release pipeline marks the build with, which About and Settings show. */
const version = /MARKETING_VERSION\s*=\s*(\S+)/.exec(
  readFileSync(fileURLToPath(new URL("../../../Config/Version.xcconfig", import.meta.url)), "utf8"))?.[1] ?? "";

export default defineConfig({
  plugins: [svelte(), {
    name: "crest-font-license",
    generateBundle() {
      this.emitFile({ type: "asset", fileName: "licenses/AlloVariable-OFL.txt",
        source: readFileSync(`${fonts}/AlloVariable-OFL.txt`) });
    },
  }],
  define: { __CREST_VERSION__: JSON.stringify(version) },
  server: {
    port: 5173,
    strictPort: true,
    host: "127.0.0.1",
    fs: { allow: [searchForWorkspaceRoot(process.cwd()), fonts, peekSample, appIcons, heraldry, searchLogos, guideLogos, artworkCredits] },
  },
  build: { target: "chrome130", sourcemap: true, license: { fileName: "licenses/dependencies.md" } },
});
