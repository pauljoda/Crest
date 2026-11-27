import { reader } from "../reactive";

/**
 * Whether the interface holds the pointer for a drag of its own: resizing
 * the sidebar, or lifting its rows. An embedded page's surface takes the
 * pointer's events whenever the pointer is over it, even in the middle of a
 * drag the interface began, so the page card is covered while a drag lasts.
 */
let holds = 0;
const listeners = new Set<() => void>();

function changed() {
  for (const listener of listeners) listener();
}

/** Holds the pointer for a drag; answers the call that lets it go, which only the first call does. */
export function holdPointer(): () => void {
  holds++;
  changed();
  let released = false;
  return () => {
    if (released) return;
    released = true;
    holds--;
    changed();
  };
}

/** Whether a drag holds the pointer now. */
const readPointerHeld = reader((listener) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
}, () => holds > 0);

export function usePointerHeld(): boolean {
  return readPointerHeld();
}
