import react from "@vitejs/plugin-react";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { defineConfig, searchForWorkspaceRoot } from "vite";

/** Crest's app icons, which every Crest app shares and the Start Page shows. */
const appIcons = fileURLToPath(new URL("../../../CrestShared/Resources/AppIconPreviews.xcassets", import.meta.url));
/** The heraldic charges a Space's crest draws, shared with the Mac. */
const heraldry = fileURLToPath(new URL("../../../CrestShared/Resources/CrestHeraldry.xcassets", import.meta.url));

/** The version the release pipeline marks the build with, which About and Settings show. */
const version = /MARKETING_VERSION\s*=\s*(\S+)/.exec(
  readFileSync(fileURLToPath(new URL("../../../Config/Version.xcconfig", import.meta.url)), "utf8"))?.[1] ?? "";

export default defineConfig({
  plugins: [react()],
  define: { __CREST_VERSION__: JSON.stringify(version) },
  server: {
    port: 5173,
    strictPort: true,
    host: "127.0.0.1",
    fs: { allow: [searchForWorkspaceRoot(process.cwd()), appIcons, heraldry] },
  },
  build: { target: "chrome130", sourcemap: true },
});
