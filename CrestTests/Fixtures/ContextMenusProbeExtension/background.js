const menus = [
  {
    id: "page",
    title: "Fixture Page",
    contexts: ["page"],
    documentUrlPatterns: ["http://127.0.0.1/*"]
  },
  {
    id: "link",
    title: "Fixture Link",
    contexts: ["link"],
    targetUrlPatterns: ["https://allowed.example/*"]
  },
  {
    id: "image",
    title: "Fixture Image",
    contexts: ["image"],
    targetUrlPatterns: ["http://127.0.0.1/*.webp"]
  },
  {
    id: "selection",
    title: "Fixture Selection: %s",
    contexts: ["selection"]
  },
  {
    id: "editable",
    title: "Fixture Editable",
    contexts: ["editable"]
  },
  {
    id: "frame",
    title: "Fixture Frame",
    contexts: ["frame"],
    documentUrlPatterns: ["http://127.0.0.1/*"]
  },
  {
    id: "nested",
    title: "Fixture Nested",
    contexts: ["all"]
  },
  {
    id: "nested-image",
    parentId: "nested",
    title: "Nested Image Action",
    contexts: ["image"]
  },
  {
    id: "nested-separator",
    parentId: "nested",
    type: "separator",
    contexts: ["image"]
  },
  {
    id: "nested-disabled",
    parentId: "nested",
    title: "Disabled Image Action",
    contexts: ["image"],
    enabled: false
  },
  {
    id: "hidden",
    title: "Hidden Image Action",
    contexts: ["image"],
    visible: false
  },
  {
    id: "wrong-document",
    title: "Wrong Document Action",
    contexts: ["image"],
    documentUrlPatterns: ["https://blocked.example/*"]
  },
  {
    id: "wrong-target",
    title: "Wrong Target Action",
    contexts: ["image"],
    targetUrlPatterns: ["https://blocked.example/*"]
  },
  {
    id: "tab",
    title: "Fixture Tab",
    contexts: ["tab"]
  }
];

chrome.contextMenus.removeAll(() => {
  for (const menu of menus) chrome.contextMenus.create(menu);
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  const result = {
    menuItemId: info.menuItemId,
    parentMenuItemId: info.parentMenuItemId,
    pageUrl: info.pageUrl,
    frameUrl: info.frameUrl,
    frameId: info.frameId,
    linkUrl: info.linkUrl,
    srcUrl: info.srcUrl,
    selectionText: info.selectionText,
    editable: info.editable,
    tabId: tab?.id,
    tabUrl: tab?.url
  };
  chrome.tabs.create({
    url: chrome.runtime.getURL(
      `result.html?data=${encodeURIComponent(JSON.stringify(result))}`
    )
  });
});
