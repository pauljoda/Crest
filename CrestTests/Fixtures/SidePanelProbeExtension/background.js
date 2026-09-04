const api = globalThis.browser || globalThis.chrome;
const flavor = api.sidePanel ? 'chrome' : api.sidebarAction ? 'firefox' : 'unavailable';
let writes = Promise.resolve();
function record(kind, details = {}) {
  writes = writes.then(async () => {
    const stored = await api.storage.local.get('probeEvents');
    const events = [...(stored.probeEvents || []), {kind, details, time: new Date().toISOString()}].slice(-120);
    await api.storage.local.set({probeEvents: events});
  }).catch(error => console.warn('Probe log failed', String(error)));
  return writes;
}
record('worker-ready', {flavor});
api.runtime.onInstalled.addListener(details => {
  record('installed', details);
  if (flavor === 'chrome') {
    api.sidePanel.setPanelBehavior({openPanelOnActionClick: true})
      .then(() => record('action-behavior-enabled'))
      .catch(error => record('configuration-error', {message: String(error)}));
  }
});
if (flavor === 'chrome') {
  api.sidePanel.onOpened.addListener(info => record('opened', info));
  api.sidePanel.onClosed.addListener(info => record('closed', info));
}
const action = api.action || api.browserAction;
action?.onClicked?.addListener(tab => record('action-clicked', {tabId: tab.id}));
api.commands?.onCommand?.addListener(command => record('command', {command}));
api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.probe !== true) return false;
  const respond = async () => {
    if (message.kind === 'clear') {
      await writes;
      await api.storage.local.set({probeEvents: []});
      return {cleared: true};
    }
    if (message.kind === 'delayed-open') {
      setTimeout(async () => {
        try {
          await api.sidePanel.open({windowId: message.windowId});
          await record('delayed-open-unexpected-success');
        } catch (error) {
          await record('delayed-open-rejected', {message: String(error)});
        }
      }, 6500);
      return {scheduled: true, delayMs: 6500};
    }
    const observation = {senderHasTab: sender.tab !== undefined, senderURL: sender.url || null};
    if (message.kind === 'document-ready') {
      await record('document-ready', {...observation, documentID: message.documentID, path: message.path});
    }
    await writes;
    const stored = await api.storage.local.get('probeEvents');
    return {...observation, events: stored.probeEvents || []};
  };
  respond().then(sendResponse, error => sendResponse({error: String(error)}));
  return true;
});
