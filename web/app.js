import * as store from "./store.js";
import { THEMES, apply } from "./themes.js";
import { $, esc, ICONS, readLocal, writeLocal } from "./util.js";
import * as pomodoro from "./pomodoro.js";
import * as orario from "./orario.js";

const TABS = [
  ["orario", "Orario"],
  ["pomodoro", "Pomodoro"],
  ["settings", "Settings"],
];

const ui = {
  tab: readLocal("pocket.tab", "orario"),
  setupEmail: "",
  setupStep: "email",
  setupError: "",
  busy: false,
  toast: "",
};

function prefs() {
  return { theme: "sage", ...(store.get("settings.prefs", "prefs") || {}) };
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
      <h3>Orario</h3>
      <div class="row"><span class="grow">Night routine from<span class="tip">The day rolls over at 4 AM, so a late night still counts for the day before.</span></span>
        <div class="stepper"><button data-night="-1" aria-label="Earlier">−</button><b>${orario.hourLabel(night)}</b><button data-night="1" aria-label="Later">+</button></div>
      </div>
    </div>
    <div class="card list">
      <h3>Sync</h3>
      <div class="row"><span class="grow">Account</span><span class="sub">${esc(st.session?.user?.email || "—")}</span></div>
      <div class="row"><span class="grow">This device</span><input class="inline" data-device value="${esc(st.device)}" aria-label="Device name"></div>
      <div class="row"><span class="grow">Last synced</span><span class="sub">${last ? last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" }) : "never"}</span></div>
      <div class="row"><span class="grow">Waiting to upload</span><span class="sub">${store.pendingCount()}</span></div>
      ${st.problem ? `<div class="row warn">${esc(st.problem)}</div>` : ""}
      <div class="controls left"><button class="ghost" data-sync>Sync now</button><button class="ghost" data-export>Download a copy</button><button class="ghost danger" data-signout>Sign out</button></div>
    </div>
  </section>`;
}

function viewSetup() {
  const st = store.snapshot();
  const step = !st.config ? "server" : ui.setupStep;
  return `
  <div class="setup">
    <div class="card setup-card">
      <div class="brand"><span class="logo"></span><h1>Pocket</h1></div>
      ${
        step === "server"
          ? `<p>Connect this device to your Pocket database. Open the setup link from your Mac, or paste the two values from Supabase → Project Settings → API.</p>
        <form data-form="server">
          <input name="url" placeholder="Project URL (https://xxxx.supabase.co)" required autocomplete="off" aria-label="Project URL">
          <input name="key" placeholder="Anon public key" required autocomplete="off" aria-label="Anon public key">
          <button class="primary wide">Continue</button>
        </form>`
          : step === "email"
          ? `<p>Sign in with your email. We'll send a 6-digit code.</p>
        <form data-form="email">
          <input name="email" type="email" placeholder="you@example.com" value="${esc(ui.setupEmail)}" required autocomplete="email" aria-label="Email">
          <button class="primary wide" ${ui.busy ? "disabled" : ""}>${ui.busy ? "Sending…" : "Send code"}</button>
        </form>
        <button class="link" data-reset-server>Use a different database</button>`
          : `<p>Enter the code sent to <b>${esc(ui.setupEmail)}</b>.</p>
        <form data-form="code">
          <input name="code" inputmode="numeric" autocomplete="one-time-code" placeholder="123456" required maxlength="10" aria-label="Code">
          <button class="primary wide" ${ui.busy ? "disabled" : ""}>${ui.busy ? "Checking…" : "Sign in"}</button>
        </form>
        <button class="link" data-back-email>Use a different email</button>`
      }
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
    active && (active.name || active.dataset.edNotes) && inForm
      ? { sel: active.dataset.edNotes ? `[data-ed-notes="${active.dataset.edNotes}"]` : `form[data-form="${active.closest("form")?.dataset.form}"] [name="${active.name}"]`, value: active.value, pos: active.selectionStart, end: active.selectionEnd }
      : null;
  const scrolls = {};
  document.querySelectorAll("[data-keep-scroll]").forEach((el) => (scrolls[el.dataset.keepScroll] = el.scrollTop));
  const views = { orario: orario.view, pomodoro: pomodoro.view, settings: viewSettings };
  const syncState = st.problem ? "warn" : store.pendingCount() ? "pending" : "ok";
  const tabTitle = TABS.find(([k]) => k === ui.tab)[1];
  app.innerHTML = `
    <nav class="tabs">
      <div class="brand side"><span class="logo"></span><b>Pocket</b></div>
      ${TABS.map(([k, l]) => `<button class="tab ${ui.tab === k ? "on" : ""} ${k === "settings" ? "end" : ""}" data-tab="${k}">${ICONS[k]}<span>${l}</span></button>`).join("")}
    </nav>
    <main>
      <header><h2>${tabTitle}</h2><span class="sync ${syncState}" title="${esc(st.problem || (store.pendingCount() ? "Uploading" : "Synced"))}"></span></header>
      ${views[ui.tab]()}
    </main>
    ${ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : ""}`;
  document.body.classList.toggle("locked", !!orario.ui.editor && ui.tab === "orario");
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
  if (ui.tab === "orario") orario.afterRender();
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
    writeLocal("pocket.tab", d.tab);
    render();
    window.scrollTo(0, 0);
    return;
  }
  const handler = ui.tab === "orario" ? orario.onClick : ui.tab === "pomodoro" ? pomodoro.onClick : null;
  if (handler) {
    const r = handler(d);
    if (r === "render") render();
    if (r) return;
  }
  if (d.theme) {
    store.put("settings.prefs", "prefs", { ...prefs(), theme: d.theme });
  } else if (d.night) {
    orario.setNightFrom(Number(d.night));
  } else if (d.sync !== undefined) {
    await store.syncNow();
    toast(store.snapshot().problem || "Synced");
  } else if (d.export !== undefined) {
    const blob = new Blob([JSON.stringify(store.exportDocuments(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `pocket-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
  } else if (d.signout !== undefined) {
    if (confirm("Sign out on this device? Changes not yet uploaded will be lost.")) await store.signOut();
  } else if (d.resetServer !== undefined) {
    store.clearConfig();
  } else if (d.backEmail !== undefined) {
    ui.setupStep = "email";
    ui.setupError = "";
    render();
  }
});

document.addEventListener("input", (e) => {
  if (ui.tab === "orario") orario.onInput(e);
});

document.addEventListener("change", (e) => {
  if (e.target.matches("[data-device]")) {
    store.setDevice(e.target.value);
    return;
  }
  if (ui.tab === "orario" && orario.onChange(e) === "render") render();
});

document.addEventListener("focusout", (e) => {
  if (ui.tab === "orario" && orario.ui.editor) {
    const r = orario.onFocusOut(e);
    if (r === "render") render();
  }
});

document.addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.target;
  const kind = form.dataset.form;
  if (ui.tab === "orario") {
    const r = orario.onSubmit(kind, form);
    if (r === "render") render();
    if (r) return;
  }
  const f = new FormData(form);
  if (kind === "server") {
    store.configure(f.get("url"), f.get("key"));
    ui.setupError = "";
    ui.setupStep = "email";
    render();
  } else if (kind === "email") {
    ui.setupEmail = f.get("email");
    ui.busy = true;
    ui.setupError = "";
    render();
    try {
      await store.sendCode(ui.setupEmail);
      ui.setupStep = "code";
    } catch (err) {
      ui.setupError = err.message;
    }
    ui.busy = false;
    render();
  } else if (kind === "code") {
    ui.busy = true;
    ui.setupError = "";
    render();
    try {
      await store.verifyCode(ui.setupEmail, f.get("code"));
      ui.setupStep = "email";
    } catch (err) {
      ui.setupError = err.message;
    }
    ui.busy = false;
    render();
  }
});

function readSetupLink() {
  const m = location.hash.match(/connect=([^&]+)/);
  if (!m) return;
  try {
    const { url, key } = JSON.parse(atob(decodeURIComponent(m[1])));
    if (url && key) store.configure(url, key);
  } catch (e) {}
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
