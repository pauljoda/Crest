import { ShellTransport } from "@crest/core-client";

/**
 * Whether the interface runs inside Crest's Chromium, as `chrome://crest-desktop`.
 * There it has no network of its own: a WebUI document may load only its own
 * files, and a site's image must come from the engine, which loads it in the
 * page's own profile. In an ordinary browser, during development, it may.
 */
export const insideCrest = ShellTransport.available();
