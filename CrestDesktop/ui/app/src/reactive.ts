import { createSubscriber } from "svelte/reactivity";

/**
 * A reader of a store that lives outside Svelte, such as the core's read
 * model or the Space pager: calling it inside a `$derived`, an `$effect` or
 * a template expression reads `get()` and runs that expression again
 * whenever the store tells its listeners. Read anywhere else, it answers the
 * value without following it.
 *
 * A store that changes in place keeps its identity, so derive the values
 * read from it, not the store itself: `$derived(read().pages.get(id))`
 * follows a page, `$derived(read())` never moves.
 */
export function reader<T>(subscribe: (listener: () => void) => () => void, get: () => T): () => T {
  const track = createSubscriber((update) => subscribe(update));
  return () => {
    track();
    return get();
  };
}

/** A set of listeners and the reader that follows them, for a module's own store. */
export class Listeners {
  readonly #listeners = new Set<() => void>();

  /** Adds `listener` until the returned function removes it. */
  readonly subscribe = (listener: () => void): (() => void) => {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  };

  /** Tells every listener the store changed. */
  notify(): void {
    for (const listener of this.#listeners) listener();
  }

  /** A reader of `get()` that follows these listeners. */
  reader<T>(get: () => T): () => T {
    return reader(this.subscribe, get);
  }
}
