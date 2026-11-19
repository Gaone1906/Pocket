import * as store from "./store.js";
import { THEMES, apply } from "./themes.js";
import { $, esc, ICONS } from "./util.js";
import * as orario from "./orario.js";

const TABS = [
  ["orario", "Aqua"],
  ["settings", "Settings"],
];

const ui = {
  setupError: "",
  tab: "orario",
  toast: "",
};

function savedPrefs() {
  return store.get("settings.prefs", "orario") || {};
}

function prefs() {
  const saved = savedPrefs();
  return { ...saved, theme: saved.aquaTheme || "sky" };
}

function viewSettings() {
  const st = store.snapshot();
  const p = prefs();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  const light = THEMES.filter((t) => !t.dark);
  const dark = THEMES.filter((t) => t.dark);
  const swatches = (list) =>
    list.map((t) => `<button class="swatch ${p.theme === t.id ? "on" : ""}" data-theme="${t.id}" style="--sw:${t.dark ? t.accent : t.swatch};--ring:${t.swatchRing};--bg:${t.backdrop}"><i></i><span>${t.name}</span></button>`).join("");
  const night = orario.nightFrom();
  return `
  <section class="settings">
    <div class="card list">
      <h3>Theme</h3>
      <div class="themes">${swatches(light)}</div>
      <div class="themes">${swatches(dark)}</div>
    </div>
    <div class="card list">
      <h3>Aqua</h3>
      <div class="row"><span class="grow">Night routine from<span class="tip">The day rolls over at 4 AM, so a late night still counts for the day before.</span></span>
        <div class="stepper"><button data-night="-1" aria-label="Earlier">−</button><b>${orario.hourLabel(night)}</b><button data-night="1" aria-label="Later">+</button></div>
      </div>
    </div>
    <div class="card list">
      <h3>Sync</h3>
      <div class="row"><span class="grow">This device</span><input class="inline" data-device value="${esc(st.device)}" aria-label="Device name"></div>
      <div class="row"><span class="grow">Last synced</span><span class="sub">${last ? last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" }) : "never"}</span></div>
      <div class="row"><span class="grow">Waiting to upload</span><span class="sub">${store.pendingCount()}</span></div>
      ${st.problem ? `<div class="row warn">${esc(st.problem)}</div>` : ""}
      <div class="controls left"><button class="ghost" data-sync>Sync now</button><button class="ghost" data-export>Download a copy</button><button class="ghost danger" data-signout>Disconnect</button></div>
    </div>
  </section>`;
}

function viewSetup() {
  return `
  <div class="setup">
    <div class="card setup-card">
      <div class="brand"><span class="logo"></span><h1>Aqua</h1></div>
      <p>Every routine, in one place. Paste your Pocket setup link.</p>
      <form data-form="server">
        <input name="link" placeholder="https://gaone1906.github.io/Pocket/aqua/#connect=…" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
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
  const st = store.snapshot();
  apply(prefs().theme);
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  if (!TABS.some(([k]) => k === ui.tab)) ui.tab = "orario";
  const active = document.activeElement;
  const inForm = active && active.closest && active.closest("form, .overlay");
  const keep =
    active && active.name && inForm
      ? { sel: `form[data-form="${active.closest("form")?.dataset.form}"] [name="${active.name}"]`, value: active.value, pos: active.selectionStart, end: active.selectionEnd }
      : null;
  const scrolls = {};
  document.querySelectorAll("[data-keep-scroll]").forEach((el) => (scrolls[el.dataset.keepScroll] = el.scrollTop));
  const views = { orario: orario.view, settings: viewSettings };
  const syncState = st.problem ? "warn" : store.pendingCount() ? "pending" : "ok";
  const tabTitle = TABS.find(([k]) => k === ui.tab)[1];
  const inSettings = ui.tab === "settings";
  app.innerHTML = `
    <main>
      <header>
        ${inSettings ? `<button class="icon quiet back" data-tab="orario" aria-label="Back">${ICONS.left}</button>` : `<span class="logo"></span>`}
        <h2>${tabTitle}</h2>
        <span class="sync ${syncState}" title="${esc(st.problem || (store.pendingCount() ? "Uploading" : "Synced"))}"></span>
        <button class="icon gear ${inSettings ? "on" : ""}" data-tab="${inSettings ? "orario" : "settings"}" aria-label="${inSettings ? "Close settings" : "Settings"}">${ICONS.settings}</button>
      </header>
      ${views[ui.tab]()}
    </main>
    ${ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : ""}`;
  document.querySelectorAll("[data-keep-scroll]").forEach((el) => {
    if (scrolls[el.dataset.keepScroll] != null) el.scrollTop = scrolls[el.dataset.keepScroll];
  });
  if (keep) {
    const el = $(keep.sel);
    if (el) {
      el.value = keep.value;
      el.focus({ preventScroll: true });
      try {
        el.setSelectionRange(keep.pos, keep.end);
      } catch (e) {}
    }
  }
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
  if (d.tab) {
    ui.tab = d.tab;
    render();
    window.scrollTo(0, 0);
    return;
  }
  const handler = ui.tab === "orario" ? orario.onClick : null;
  if (handler) {
    const r = handler(d);
    if (r === "render") render();
    if (r) return;
  }
  if (d.theme) {
    store.put("settings.prefs", "orario", { ...savedPrefs(), aquaTheme: d.theme });
  } else if (d.night) {
    orario.setNightFrom(Number(d.night));
  } else if (d.sync !== undefined) {
    await store.syncNow();
    toast(store.snapshot().problem || "Synced");
  } else if (d.export !== undefined) {
    const blob = new Blob([JSON.stringify(store.exportDocuments(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `orario-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
  } else if (d.signout !== undefined) {
    if (confirm("Disconnect this device? Anything not yet uploaded is lost.")) store.disconnect();
  }
});

document.addEventListener("change", (e) => {
  if (e.target.matches("[data-device]")) {
    store.setDevice(e.target.value);
    return;
  }
  if (ui.tab === "orario" && orario.onChange(e) === "render") render();
});

document.addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.target;
  const kind = form.dataset.form;
  const f = new FormData(form);
  if (kind === "server") {
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
  }
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
