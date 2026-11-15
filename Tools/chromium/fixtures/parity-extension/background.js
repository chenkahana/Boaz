// State every check reads back: chrome.storage.local "log" holds each event in order.
async function log(event, detail = {}) {
  const { log: entries = [] } = await chrome.storage.local.get("log");
  entries.push({ event, ...detail, at: Date.now() });
  await chrome.storage.local.set({ log: entries });
}

chrome.runtime.onInstalled.addListener(async () => {
  await chrome.action.setBadgeText({ text: "42" });
  await chrome.action.setBadgeBackgroundColor({ color: "#1a73e8" });
  chrome.contextMenus.create({ id: "page", title: "Parity: page item", contexts: ["page"] });
  chrome.contextMenus.create({ id: "action", title: "Parity: action item", contexts: ["action"] });
  await log("installed");
});

chrome.contextMenus.onClicked.addListener((info) => log("menu", { id: info.menuItemId }));

chrome.commands.onCommand.addListener(async (command, tab) => {
  await log("command", { command });
  if (command === "open-panel" && tab) await chrome.sidePanel.open({ windowId: tab.windowId });
});

chrome.sidePanel.onClosed?.addListener((info) => log("panel-closed", { path: info.path }));

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  (async () => {
    switch (message.type) {
      case "open-popup":
        await chrome.action.openPopup();
        break;
      case "open-panel":
        await chrome.sidePanel.open({ windowId: message.windowId });
        break;
      case "panel-on-click":
        await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: message.value });
        break;
      case "popup-window":
        await chrome.windows.create({ url: "popup.html?window", type: "popup", width: 400, height: 300 });
        break;
      case "content":
        await log("content", { url: sender.tab?.url });
        break;
    }
    reply({ ok: true });
  })().catch((error) => reply({ ok: false, error: String(error) }));
  return true;
});

// For automation: the service worker exposes the same entry points.
self.parity = {
  openPopup: () => chrome.action.openPopup(),
  openPanel: async () => chrome.sidePanel.open({ windowId: (await chrome.windows.getLastFocused()).id }),
  panelOnClick: (value) => chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: value }),
  popupWindow: () => chrome.windows.create({ url: "popup.html?window", type: "popup", width: 400, height: 300 }),
  log: async () => (await chrome.storage.local.get("log")).log ?? [],
  requestHost: () => chrome.permissions.request({ origins: ["https://example.org/*"] }),
};
