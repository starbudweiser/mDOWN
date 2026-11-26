// mDOWN — menus contextuels : télécharger la page, le lien ou le média sous le curseur.
importScripts("lib.js");

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "video", title: t("menu_video"), contexts: ["page", "link", "video", "audio", "frame"] });
    chrome.contextMenus.create({ id: "audio", title: t("menu_audio"), contexts: ["page", "link", "video", "audio", "frame"] });
  });
});

function badge(tabId, text, color) {
  chrome.action.setBadgeBackgroundColor({ color, tabId });
  chrome.action.setBadgeText({ text, tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: "", tabId }), 2500);
}

async function onMenuClick(info, tab) {
  const candidates = [info.linkUrl, info.srcUrl, info.frameUrl, info.pageUrl, tab && tab.url];
  const url = candidates.find((u) => u && /^https?:/i.test(u) && !u.startsWith("blob:"));
  if (!url || !tab) return;
  const r = await mdown("/add", { url, mode: info.menuItemId });
  if (r.ok) badge(tab.id, "✓", "#2f7d4a");
  else {
    badge(tab.id, "!", "#c0392b");
    if (r.error === "app_off") chrome.tabs.create({ url: `mdown://download?url=${encodeURIComponent(url)}&mode=${info.menuItemId}`, active: false });
  }
}
chrome.contextMenus.onClicked.addListener(onMenuClick);
