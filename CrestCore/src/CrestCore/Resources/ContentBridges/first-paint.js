(() => {
  "use strict";
  const handler = globalThis.webkit?.messageHandlers?.crestFirstPaint;
  if (!handler || typeof PerformanceObserver !== "function") return;
  try {
    const observer = new PerformanceObserver(list => {
      if (!list.getEntries().some(entry => entry.name === "first-contentful-paint")) return;
      observer.disconnect();
      try { handler.postMessage(true); } catch (_) {}
    });
    observer.observe({ type: "paint", buffered: true });
  } catch (_) {}
})();
