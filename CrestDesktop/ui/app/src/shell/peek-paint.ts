/** The native page surface observes first contentful paint in the main frame's isolated world. */
export const firstPaintHandler = "crestFirstPaint";
export const firstPaintScript = `(() => {
  const handler = globalThis.webkit?.messageHandlers?.${firstPaintHandler};
  if (!handler || typeof PerformanceObserver !== "function") return;
  const observer = new PerformanceObserver(list => {
    if (!list.getEntriesByName("first-contentful-paint").length) return;
    observer.disconnect();
    handler.postMessage(true);
  });
  observer.observe({ type: "paint", buffered: true });
})();`;
