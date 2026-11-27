const makeBridge = () => {
  let current = null;
  const excluded = "script,style,noscript,template,input,textarea,select,option,code,pre,kbd,samp," +
    "svg,canvas,iframe,object,embed,[contenteditable],[role='textbox'],[translate='no'],.notranslate,[hidden]";
  const isVisibleText = (node, parent) => {
    if (parent.checkVisibility({checkVisibilityCSS:true,checkOpacity:true})) return true;
    const style = getComputedStyle(parent);
    if (style.display !== "contents" || style.visibility !== "visible" || Number(style.opacity) === 0) return false;
    let ancestor = parent.parentElement;
    while (ancestor) {
      if (ancestor.checkVisibility({checkVisibilityCSS:true,checkOpacity:true})) {
        const range = document.createRange();
        range.selectNode(node);
        return range.getClientRects().length > 0;
      }
      const ancestorStyle = getComputedStyle(ancestor);
      if (ancestorStyle.display !== "contents" || ancestorStyle.visibility !== "visible"
          || Number(ancestorStyle.opacity) === 0) {
        return false;
      }
      ancestor = ancestor.parentElement;
    }
    return false;
  };
  const eligible = node => {
    const parent = node.parentElement;
    return node.isConnected && parent && !parent.isContentEditable && parent.translate !== false &&
      !parent.closest(excluded) && isVisibleText(node, parent);
  };
  const route = () => location.href.split("#")[0];
  const walker = () => document.body && document.contentType === "text/html"
    ? document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT) : null;
  const sample = () => {
    const tree = walker();
    if (!tree) return {text:"",language:""};
    const start = performance.now();
    let node, count = 0, value = "";
    while ((node = tree.nextNode()) && count++ < 400 && value.length < 3000 && performance.now() - start < 8) {
      if (node.data.trim() && eligible(node)) value += " " + node.data.trim();
    }
    return {text:value.slice(0, 3000), language:document.documentElement.lang.trim()};
  };
  const discardSiteChanges = records => {
    if (!current) return;
    for (const mutation of records) {
      if (mutation.type !== "characterData") continue;
      const entry = current.byNode.get(mutation.target);
      if (entry) entry.disowned = true;
    }
  };
  const observe = state => state.observer.observe(document.body, {subtree:true,characterData:true});
  const restore = id => {
    if (!current || current.id !== id) return false;
    const state = current;
    discardSiteChanges(state.observer.takeRecords());
    state.observer.disconnect();
    current = null;
    for (const entry of state.entries) {
      if (!entry.disowned && entry.translated !== null && entry.node.data === entry.translated) {
        entry.node.data = entry.original;
      }
    }
    return true;
  };
  const capture = async id => {
    if (current) restore(current.id);
    const tree = walker();
    if (!tree) return {texts:[],limited:false};
    const state = {id, route:route(), entries:[], byNode:new WeakMap(), observer:new MutationObserver(discardSiteChanges)};
    current = state;
    observe(state);
    let node, visited = 0, characters = 0, limited = false, sliceStart = performance.now();
    while ((node = tree.nextNode())) {
      if (current !== state || state.route !== route()) return {texts:[],limited:false};
      if (++visited > 30000 || state.entries.length >= 2000 || characters >= 120000) break;
      const text = node.data.trim();
      if (text && text.length > 5000 && eligible(node)) limited = true;
      if (text && text.length <= 5000 && eligible(node)) {
        const entry = {node, original:node.data, translated:null, disowned:false};
        state.entries.push(entry);
        state.byNode.set(node, entry);
        characters += text.length;
      }
      if (performance.now() - sliceStart >= 8) {
        await new Promise(resolve => setTimeout(resolve, 0));
        sliceStart = performance.now();
      }
    }
    if (current !== state || state.route !== route()) return {texts:[],limited:false};
    return {texts:state.entries.map(e => e.original.trim()), limited:limited || !!node};
  };
  const apply = (id, values, start, indices) => {
    if (!current || current.id !== id || current.route !== route()) return 0;
    const state = current;
    discardSiteChanges(state.observer.takeRecords());
    state.observer.disconnect();
    let count = 0;
    values.forEach((value, i) => {
      const entry = state.entries[indices[i] ?? start + i];
      if (!entry || entry.disowned || !eligible(entry.node) || entry.node.data !== entry.original || typeof value !== "string") return;
      const leading = entry.original.match(/^\s*/)[0];
      const trailing = entry.original.match(/\s*$/)[0];
      entry.translated = leading + value.trim() + trailing;
      entry.node.data = entry.translated;
      count++;
    });
    observe(state);
    return count;
  };
  // Restore before WebKit freezes a document in its back/forward cache.
  window.addEventListener("pagehide", () => { if (current) restore(current.id); });
  return {sample,capture,apply,restore};
};
const bridge = window.__crestPageTranslation ??= makeBridge();
if (action === "sample") return bridge.sample();
if (action === "capture") return await bridge.capture(token);
if (action === "apply") return bridge.apply(token,texts,offset,indices);
if (action === "restore") return bridge.restore(token);
return null;
