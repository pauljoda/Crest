import { reader } from "../reactive";

/**
 * Whether the page cards take changes of size at once rather than animating
 * into them. As the sidebar takes its seat or leaves it, the page's edge
 * follows the sidebar's each frame, the page laid out at every width on the
 * way, so a card's own layout animation, which would scale the live page
 * from its last box, stays out of it.
 */
let holds = 0;
let settling = false;
// Each release's settling, so only the latest one's frames end it.
let releases = 0;
const listeners = new Set<() => void>();

function changed() {
  for (const listener of listeners) listener();
}

/**
 * Has the cards take every change of size at once until the release it
 * returns, and until the frame after next once released, by when the last
 * change has drawn.
 */
export function holdCards(): () => void {
  holds++;
  if (holds === 1 && !settling) changed();
  let released = false;
  return () => {
    if (released) return;
    released = true;
    holds--;
    if (holds > 0) return;
    settling = true;
    const release = ++releases;
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (release !== releases) return;
      settling = false;
      if (holds === 0) changed();
    }));
  };
}

/** Whether the cards take a change of size at once now. */
const readCardsSnap = reader((listener) => {
  listeners.add(listener);
  return () => listeners.delete(listener);
}, () => holds > 0 || settling);

export function useCardsSnap(): boolean {
  return readCardsSnap();
}
