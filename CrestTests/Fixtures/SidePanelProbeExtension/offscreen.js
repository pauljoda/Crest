const api = globalThis.browser || globalThis.chrome;
api.runtime.sendMessage({probe: true, kind: 'document-ready', documentID: crypto.randomUUID(), path: location.pathname});
