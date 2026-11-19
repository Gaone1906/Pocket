import * as store from "./store.js";
import { apply } from "./themes.js";
import { $, esc, ICONS } from "./util.js";
import * as orario from "./orario.js";

const ui = {
  setupError: "",
  toast: "",
  syncing: false,
};

function prefs() {
  return { theme: "sage", ...(store.get("settings.prefs", "prefs") || {}) };
}

function syncButton() {
  const st = store.snapshot();
  const state = ui.syncing || store.pendingCount() ? "pending" : st.problem ? "warn" : "ok";
  const label = st.problem || (store.pendingCount() ? "Uploading" : "Sync now");
  return `<button class="icon pill-btn sync-btn ${state}" data-sync aria-label="${esc(label)}" title="${esc(label)}">${ICONS.sync}</button>`;
}

function viewSetup() {
  return `
  <div class="setup">
    <div class="card setup-card">
      <p>Paste your setup link.</p>
      <form data-form="server">
        <input name="link" placeholder="Setup link" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
        <details class="manual"><summary>Or enter the Supabase values</summary>
          <input name="url" placeholder="Project URL (https://xxxx.supabase.co)" autocomplete="off" autocapitalize="off" aria-label="Project URL">
          <input name="key" placeholder="Anon public key" autocomplete="off" autocapitalize="off" aria-label="Anon public key">
        </details>
        <button class="primary wide">Continue</button>
      </form>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </div>
  </div>`;
}

function render() {
  const app = $("#app");
  apply(prefs().theme);
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  app.innerHTML = `
    <main>${orario.view(syncButton())}</main>
    ${ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : ""}`;
}

function toast(text) {
  ui.toast = text;
  render();
  clearTimeout(toast.t);
  toast.t = setTimeout(() => {
    ui.toast = "";
    render();
  }, 2400);
}

document.addEventListener("click", async (e) => {
  const t = e.target.closest("button");
  if (!t || t.disabled) return;
  const d = t.dataset;
  if (d.sync !== undefined) {
    if (ui.syncing) return;
    ui.syncing = true;
    render();
    await store.syncNow();
    ui.syncing = false;
    toast(store.snapshot().problem || "Synced");
    return;
  }
  if (orario.onClick(d) === "render") render();
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const form = e.target;
  if (form.dataset.form !== "server") return;
  const f = new FormData(form);
  const fromLink = parseLink(f.get("link") || "");
  const url = fromLink?.url || f.get("url");
  const key = fromLink?.key || f.get("key");
  if (!url || !key) {
    ui.setupError = "Paste the whole setup link, or both Supabase values.";
    render();
    return;
  }
  ui.setupError = "";
  store.configure(url, key);
});

function parseLink(text) {
  const m = String(text).match(/connect=([^&\s]+)/);
  if (!m) return null;
  try {
    const { url, key } = JSON.parse(atob(decodeURIComponent(m[1])));
    return url && key ? { url, key } : null;
  } catch (e) {
    return null;
  }
}

function readSetupLink() {
  const found = parseLink(location.hash);
  if (!found) return;
  store.configure(found.url, found.key);
  history.replaceState(null, "", location.pathname + location.search);
}

let lastSlot = orario.today() + orario.slotNow();
setInterval(() => {
  const now = orario.today() + orario.slotNow();
  if (now !== lastSlot) {
    lastSlot = now;
    render();
  }
}, 30000);

readSetupLink();
store.subscribe(render);
render();
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
