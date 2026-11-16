document.documentElement.dataset.boazParity = "content-script";
// Visible too, so UI tests can see the script ran.
const marker = document.createElement("p");
marker.id = "boaz-parity-marker";
marker.textContent = "Boaz parity content script ran";
document.body?.append(marker);
chrome.runtime.sendMessage({ type: "content" });
