// Deliberately inert. The offscreen document only has to exist and stay
// loaded, so that the popup's chrome.extension.getViews() sweep has something
// to find if WebKit hands hidden extension web views back as views.
window.__offscreenReady = true;
