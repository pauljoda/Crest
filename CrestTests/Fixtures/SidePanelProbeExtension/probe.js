const api = globalThis.browser || globalThis.chrome;
const flavor = api.sidePanel ? 'chrome' : api.sidebarAction ? 'firefox' : 'unavailable';
const documentID = crypto.randomUUID();
let currentWindow;
const heading = document.createElement('h1');
heading.textContent = document.title;
const identity = document.createElement('p');
identity.textContent = 'Document: ' + documentID + ' · ' + location.pathname;
const selectLabel = document.createElement('label');
selectLabel.textContent = 'Tab to configure';
const selectedTab = document.createElement('select');
selectedTab.setAttribute('aria-label', 'Tab to configure');
selectLabel.append(selectedTab);
const focus = document.createElement('input');
focus.placeholder = 'Type here to test panel focus';
focus.setAttribute('aria-label', 'Panel focus test');
const actions = document.createElement('div');
actions.className = 'actions';
const outcome = document.createElement('output');
outcome.setAttribute('aria-live', 'polite');
const status = document.createElement('pre');
status.setAttribute('aria-label', 'Probe status');
const link = document.createElement('a');
link.href = 'https://example.com/?crest-sidepanel-link';
link.textContent = 'Open example.com as a normal tab';
document.body.append(heading, identity, selectLabel, focus, actions, outcome, link, status);
function message(kind, extra = {}) {
  return api.runtime.sendMessage({probe: true, kind, ...extra});
}
function tabID() {
  const value = Number(selectedTab.value);
  if (!Number.isInteger(value) || !selectedTab.value) throw new Error('Choose a tab first.');
  return value;
}
function windowID() {
  if (!Number.isInteger(currentWindow?.id)) throw new Error('Refresh status to resolve this window.');
  return currentWindow.id;
}
function button(title, operation) {
  const control = document.createElement('button');
  control.textContent = title;
  control.addEventListener('click', async () => {
    try {
      const result = await operation();
      outcome.textContent = title + ': ' + JSON.stringify(result ?? 'ok');
      await refresh();
    } catch (error) {
      outcome.textContent = title + ': ' + String(error);
    }
  });
  actions.append(control);
}
async function refresh() {
  currentWindow = await api.windows.getCurrent();
  const tabs = await api.tabs.query({currentWindow: true});
  const previous = selectedTab.value;
  selectedTab.replaceChildren();
  for (const tab of tabs) {
    const option = document.createElement('option');
    option.value = String(tab.id);
    option.textContent = tab.id + ': ' + (tab.title || tab.url || 'Untitled');
    option.selected = previous ? previous === option.value : tab.active;
    selectedTab.append(option);
  }
  const worker = await message('status');
  let views;
  try { views = api.extension.getViews().map(view => view.location.pathname); }
  catch (error) { views = {error: String(error)}; }
  const details = {
    flavor, documentID, path: location.pathname, userActivationAvailable: !!navigator.userActivation,
    window: currentWindow, tabs: tabs.map(tab => ({id: tab.id, index: tab.index, url: tab.url, active: tab.active})),
    panelAppearsAsTab: tabs.some(tab => [api.runtime.getURL('panel.html'), api.runtime.getURL('tab.html')].includes(tab.url)),
    views, worker
  };
  if (flavor === 'chrome') {
    details.behavior = await api.sidePanel.getPanelBehavior();
    details.globalOptions = await api.sidePanel.getOptions({});
    details.layout = await api.sidePanel.getLayout();
    if (selectedTab.value) details.selectedTabOptions = await api.sidePanel.getOptions({tabId: tabID()});
    details.offscreenDocument = await api.offscreen.hasDocument();
  } else if (flavor === 'firefox') {
    details.panel = await api.sidebarAction.getPanel({});
    details.title = await api.sidebarAction.getTitle({});
    details.isOpen = await api.sidebarAction.isOpen({});
  }
  status.textContent = JSON.stringify(details, null, 2);
}
button('Refresh status', refresh);
button('Clear event log', () => message('clear'));
button('Create test tab', () => api.tabs.create({url: 'https://example.com/?crest-sidebar-probe', active: false}));
if (flavor === 'chrome') {
  button('Open from extension page', () => api.sidePanel.open({windowId: windowID()}));
  button('Close global panel', () => api.sidePanel.close({windowId: windowID()}));
  button('Try tab-only close', () => api.sidePanel.close({tabId: tabID()}));
  button('Enable action opening', () => api.sidePanel.setPanelBehavior({openPanelOnActionClick: true}));
  button('Disable action opening', () => api.sidePanel.setPanelBehavior({openPanelOnActionClick: false}));
  button('Use tab-specific document', () => api.sidePanel.setOptions({tabId: tabID(), path: 'tab.html', enabled: true}));
  button('Disable selected tab panel', () => api.sidePanel.setOptions({tabId: tabID(), enabled: false}));
  button('Re-enable selected tab panel', () => api.sidePanel.setOptions({tabId: tabID(), enabled: true}));
  button('Try worker open after 6.5 seconds', () => message('delayed-open', {windowId: windowID()}));
  button('Create offscreen document', () => api.offscreen.createDocument({
    url: 'offscreen.html', reasons: ['DOM_PARSER'], justification: 'Verify the panel and offscreen document coexist.'
  }));
  button('Close offscreen document', () => api.offscreen.closeDocument());
} else if (flavor === 'firefox') {
  button('Toggle sidebar', () => api.sidebarAction.toggle());
  button('Open sidebar', () => api.sidebarAction.open());
  button('Close sidebar', () => api.sidebarAction.close());
  button('Clear global panel', () => api.sidebarAction.setPanel({panel: ''}));
  button('Restore global panel', () => api.sidebarAction.setPanel({panel: 'panel.html'}));
  button('Use tab-specific document', () => api.sidebarAction.setPanel({tabId: tabID(), panel: 'tab.html'}));
  button('Clear selected tab panel', () => api.sidebarAction.setPanel({tabId: tabID(), panel: null}));
  button('Set global title', () => api.sidebarAction.setTitle({title: 'Global probe title'}));
  button('Set window title', () => api.sidebarAction.setTitle({windowId: windowID(), title: 'Window probe title'}));
  button('Set selected tab title', () => api.sidebarAction.setTitle({tabId: tabID(), title: 'Tab probe title'}));
  button('Clear selected tab title', () => api.sidebarAction.setTitle({tabId: tabID(), title: null}));
}
message('document-ready', {documentID, path: location.pathname})
  .then(refresh).catch(error => { outcome.textContent = String(error); });
