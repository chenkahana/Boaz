const status = document.getElementById("status");
chrome.storage.local.get("log").then(({ log = [] }) => {
  const entries = [...log, { event: "popup", window: location.search === "?window", at: Date.now() }];
  return chrome.storage.local.set({ log: entries });
});
document.getElementById("panel").onclick = async () => {
  const win = await chrome.windows.getCurrent();
  await chrome.sidePanel.open({ windowId: win.id });
};
document.getElementById("window").onclick = () => chrome.runtime.sendMessage({ type: "popup-window" });
document.getElementById("host").onclick = async () => {
  status.textContent = String(await chrome.permissions.request({ origins: ["https://example.org/*"] }));
};
document.getElementById("panelclick").onclick = async () => {
  await chrome.runtime.sendMessage({ type: "toggle-panel-on-click" });
  window.close();
};
document.getElementById("webpopup").onclick = () => {
  window.open("https://example.com/", "", "popup,width=480,height=360");
};
document.getElementById("removelater").onclick = async () => {
  await chrome.runtime.sendMessage({ type: "remove-later" });
  window.close();
};
