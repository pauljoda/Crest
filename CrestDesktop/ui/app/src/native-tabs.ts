/**
 * The tabs showing one of Crest's own views that hold that view in this
 * window, as the Mac's native tab runtimes: such a tab is resident, as a tab
 * with a live page is, so its row reads loaded rather than dimmed. A view
 * keeps its place here while its state lives, which for the Getting Started
 * guide is until its tab goes.
 */
export const residentNativeTabs = new Set<string>();
