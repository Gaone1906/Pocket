import * as store from "./store.js";
import { $, esc, ICONS, readLocal, writeLocal } from "./util.js";
import * as P from "./pick.js";

const TAB_ICONS = {
  quotes: '<svg viewBox="0 0 24 24"><path d="M7 7h4v4c0 3-1.5 5-4 6"/><path d="M14 7h4v4c0 3-1.5 5-4 6"/></svg>',
  reels: '<svg viewBox="0 0 24 24"><rect x="6" y="3" width="12" height="18" rx="3"/><path d="M11 9.5l3 2.5-3 2.5z"/></svg>',
  videos: '<svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="3"/><path d="M10.5 9.5l4 2.5-4 2.5z"/></svg>',
  stories: '<svg viewBox="0 0 24 24"><path d="M4 5.5C6.5 4.5 9.5 4.5 12 6c2.5-1.5 5.5-1.5 8-.5V19c-2.5-1-5.5-1-8 .5-2.5-1.5-5.5-1.5-8-.5z"/><path d="M12 6v13.5"/></svg>',
};
const NAMES = { quotes: "Quotes", reels: "Reels", videos: "Videos", stories: "Stories" };
const EXTRA = {
  share: '<svg viewBox="0 0 24 24"><path d="M12 3v12"/><path d="M7 8l5-5 5 5"/><path d="M5 14v5a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-5"/></svg>',
  shuffle: '<svg viewBox="0 0 24 24"><path d="M16 3h5v5"/><path d="M4 20L21 3"/><path d="M21 16v5h-5"/><path d="M15 15l6 6"/><path d="M4 4l5 5"/></svg>',
  search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>',
  play: '<svg viewBox="0 0 24 24"><path d="M8 5.5l10 6.5-10 6.5z"/></svg>',
  down: '<svg viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></svg>',
  upArrow: '<svg viewBox="0 0 24 24"><path d="m18 15-6-6-6 6"/></svg>',
};

const ui = {
  mode: P.MODES.includes(readLocal("ortus.mode", "quotes")) ? readLocal("ortus.mode", "quotes") : "quotes",
  theme: readLocal("ortus.theme", ""),
  category: readLocal("ortus.category", ""),
  qi: 0,
  ri: 0,
  vi: 0,
  story: null,
  kind: "all",
  query: "",
  settings: false,
  setupError: "",
  toast: "",
  played: false,
};

let cache = { rev: -1 };

function strictQuotes() {
  return readLocal("ortus.verified", "0") === "1";
}

function model() {
  const rev = store.revision();
  const strict = strictQuotes();
  const day = P.dayKey();
  if (cache.rev === rev && cache.strict === strict && cache.day === day) return cache;
  const allQuotes = store.all("ortus.quote").filter((q) => q && q.text);
  const quotes = strict ? allQuotes.filter((q) => q.sure !== "moderate") : allQuotes;
  const stories = store.all("ortus.story").filter((s) => s && s.title);
  const reels = store.all("ortus.reel").filter((r) => P.youtubeId(r.url));
  const videos = store.all("ortus.video").filter((r) => P.youtubeId(r.url));
  cache = { rev, strict, day, quotes, stories, reels, videos };
  return cache;
}

function ordered(items, kind, seed) {
  const first = P.daily(items, kind);
  const rest = P.shuffled(items.filter((x) => x !== first), seed + "|" + kind);
  return first ? [first, ...rest] : rest;
}

function quoteList(m) {
  const pool = ui.theme ? m.quotes.filter((q) => q.theme === ui.theme) : m.quotes;
  return ordered(pool, "ortus.quote", m.day);
}

function reelList(m) {
  const pool = ui.category ? m.reels.filter((r) => r.category === ui.category) : m.reels;
  return ordered(pool, "ortus.reel", m.day);
}

function storyList(m) {
  const q = ui.query.trim().toLowerCase();
  return m.stories
    .filter((s) => ui.kind === "all" || s.kind === ui.kind)
    .filter((s) => !q || [s.name, s.title, s.who].join(" ").toLowerCase().includes(q))
    .sort((a, b) => String(a.name).localeCompare(String(b.name)));
}

function wrap(i, n) {
  return n ? ((i % n) + n) % n : 0;
}

function header(title, extra = "") {
  return `<header class="head">
    <img class="logo" src="icon-192.png" alt="">
    <h1>${esc(title)}</h1>
    ${extra}
    <button class="iconbtn" data-act="settings" aria-label="Settings">${ICONS.settings}</button>
  </header>`;
}

function chips(list, current, act, counts) {
  const all = `<button class="chip ${current ? "" : "on"}" data-act="${act}" data-v="">All</button>`;
  return `<div class="chips">${all}${list
    .filter((x) => !counts || counts[x])
    .map((x) => `<button class="chip ${current === x ? "on" : ""}" data-act="${act}" data-v="${esc(x)}">${esc(x)}</button>`)
    .join("")}</div>`;
}

function empty(title, text) {
  return `<div class="empty"><b>${esc(title)}</b><span>${esc(text)}</span></div>`;
}

function viewQuotes(m) {
  const list = quoteList(m);
  const counts = {};
  m.quotes.forEach((q) => (counts[q.theme] = (counts[q.theme] || 0) + 1));
  const top = chips(P.QUOTE_THEMES, ui.theme, "theme", counts);
  if (!list.length) return `<main class="screen">${header("Quotes")}${top}${empty("No quotes yet", "They arrive with the next sync.")}</main>`;
  const q = list[wrap(ui.qi, list.length)];
  const isToday = wrap(ui.qi, list.length) === 0 && !ui.theme;
  const meta = [q.who, q.source].filter(Boolean).join(" · ");
  return `<main class="screen">
    ${header("Quotes")}
    ${top}
    <article class="quote swipe" data-swipe="quote">
      <div class="kick"><span class="pill">${esc(isToday ? "Today · " + q.theme : q.theme)}</span></div>
      <svg class="mark" viewBox="0 0 24 24"><path d="M7 7h4v4c0 3-1.5 5-4 6"/><path d="M14 7h4v4c0 3-1.5 5-4 6"/></svg>
      <p class="qtext ${q.text.length > 160 ? "long" : ""}">${esc(q.text)}</p>
      <div class="by"><b>${esc(q.author)}</b>${meta ? `<span>${esc(meta)}</span>` : ""}</div>
    </article>
    <div class="row">
      <span class="hint">${wrap(ui.qi, list.length) + 1} of ${list.length} · swipe for more</span>
      <button class="iconbtn soft" data-act="share-quote" aria-label="Share quote">${EXTRA.share}</button>
      <button class="iconbtn solid" data-act="quote-next" aria-label="Next quote">${ICONS.right}</button>
    </div>
  </main>`;
}

function player(item, kind) {
  const src = P.embedUrl(item, ui.played);
  return `<div class="player ${kind}" id="player" data-src="${esc(src || "")}">${src ? `<iframe src="${esc(src)}" title="${esc(item.title || "Video")}" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe>` : ""}</div>`;
}

function viewReels(m) {
  const list = reelList(m);
  const counts = {};
  m.reels.forEach((r) => (counts[r.category] = (counts[r.category] || 0) + 1));
  const top = chips(P.REEL_CATEGORIES, ui.category, "category", counts);
  if (!list.length) return `<main class="screen dark">${header("Reels")}${top}${empty("No reels yet", "They arrive with the next sync.")}</main>`;
  const i = wrap(ui.ri, list.length);
  const r = list[i];
  return `<main class="screen dark reels">
    ${header("Reels")}
    ${top}
    ${player(r, "tall")}
    <div class="info swipe" data-swipe="reel">
      <div class="itxt">
        <span class="tag">${esc(r.category || "Reel")}</span>
        <b>${esc(P.cleanTitle(r.title))}</b>
        <span>${esc([r.channel, r.views ? P.views(r.views) + " views" : ""].filter(Boolean).join(" · "))}</span>
      </div>
      <div class="side">
        <button class="iconbtn ghost" data-act="reel-prev" aria-label="Previous reel">${EXTRA.upArrow}</button>
        <button class="iconbtn solid" data-act="reel-next" aria-label="Next reel">${EXTRA.down}</button>
        <a class="iconbtn ghost" href="${esc(P.watchUrl(r))}" target="_blank" rel="noopener" aria-label="Open on YouTube">${ICONS.ext}</a>
      </div>
    </div>
    <div class="hint center">${i + 1} of ${list.length}</div>
  </main>`;
}

function viewVideos(m) {
  const list = ordered(m.videos, "ortus.video", m.day);
  if (!list.length) return `<main class="screen dark">${header("Videos")}${empty("No videos yet", "Longer talks and films land here once they are added to the library.")}</main>`;
  const i = wrap(ui.vi, list.length);
  const v = list[i];
  return `<main class="screen dark">
    ${header("Videos")}
    ${player(v, "wide")}
    <div class="info">
      <div class="itxt"><span class="tag">${esc(v.category || "Video")}</span><b>${esc(P.cleanTitle(v.title))}</b><span>${esc(v.channel || "")}</span></div>
      <div class="side">
        <button class="iconbtn solid" data-act="video-next" aria-label="Next video">${ICONS.right}</button>
        <a class="iconbtn ghost" href="${esc(P.watchUrl(v))}" target="_blank" rel="noopener" aria-label="Open on YouTube">${ICONS.ext}</a>
      </div>
    </div>
    <div class="list">${list
      .map((x, k) => `<button class="vrow ${k === i ? "on" : ""}" data-act="video" data-v="${k}"><span class="vt">${EXTRA.play}</span><span class="vx"><b>${esc(P.cleanTitle(x.title))}</b><span>${esc(x.channel || "")}</span></span></button>`)
      .join("")}</div>
  </main>`;
}

function viewStories(m) {
  if (ui.story) {
    const s = m.stories.find((x) => x.id === ui.story);
    if (s) return viewStory(m, s);
    ui.story = null;
  }
  const list = storyList(m);
  const today = P.daily(m.stories, "ortus.story", m.day);
  const real = m.stories.filter((s) => s.kind === "real").length;
  const filter = (k, label) => `<button class="chip ${ui.kind === k ? "on" : ""}" data-act="kind" data-v="${k}">${label}</button>`;
  return `<main class="screen">
    ${header("Stories", `<button class="iconbtn soft" data-act="story-random" aria-label="Random story">${EXTRA.shuffle}</button>`)}
    ${
      today && !ui.query && ui.kind === "all"
        ? `<button class="today" data-act="story" data-v="${esc(today.id)}"><span class="kicker">Story of the day</span><b>${esc(today.title)}</b><span>${esc(today.name)} · ${P.storyMinutes(today)} min read</span></button>`
        : ""
    }
    <label class="search">${EXTRA.search}<input type="search" data-input="query" placeholder="Search people and stories" value="${esc(ui.query)}" autocomplete="off"></label>
    <div class="chips">${filter("all", "All · " + m.stories.length)}${filter("real", "Real · " + real)}${filter("fiction", "Fiction · " + (m.stories.length - real))}</div>
    <div class="stories">${
      list.length
        ? list.map((s) => `<button class="srow" data-act="story" data-v="${esc(s.id)}"><span>${esc(s.name)}${s.kind === "fiction" ? " · fiction" : ""}</span><b>${esc(s.title)}</b></button>`).join("")
        : empty("Nothing found", m.stories.length ? "Try another name." : "Stories arrive with the next sync.")
    }</div>
  </main>`;
}

function viewStory(m, s) {
  const link = /^https?:\/\//.test(s.source || "") ? `<a class="src" href="${esc(s.source)}" target="_blank" rel="noopener">Read more ${ICONS.ext}</a>` : s.source ? `<span class="src">${esc(s.source)}</span>` : "";
  return `<main class="screen reader">
    <header class="head">
      <button class="iconbtn soft" data-act="story-back" aria-label="All stories">${ICONS.left}</button>
      <span class="crumb">Stories · ${s.kind === "fiction" ? "Fiction" : "Real"}</span>
      <button class="pillbtn" data-act="story-random">Random</button>
    </header>
    <span class="who">${esc(s.name)} · ${esc(s.who || "")}</span>
    <h2>${esc(s.title)}</h2>
    <div class="paras">${(s.paras || []).map((p) => `<p>${esc(p)}</p>`).join("")}</div>
    ${s.line ? `<p class="line">${esc(s.line)}</p>` : ""}
    ${link}
  </main>`;
}

function viewSettings() {
  const snap = store.snapshot();
  const m = model();
  const last = snap.lastSync ? new Date(snap.lastSync).toLocaleString([], { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" }) : "never";
  return `<div class="sheet" data-act="close-settings"><div class="panel" data-stop>
    <div class="phead"><h2>Settings</h2><button class="iconbtn soft" data-act="close-settings" aria-label="Close">${ICONS.left}</button></div>
    <label class="toggle"><span><b>Only quotes with a known source</b><small>Hides the ones that are only widely attributed</small></span><input type="checkbox" data-input="verified" ${strictQuotes() ? "checked" : ""}></label>
    <div class="facts">
      <span>${m.quotes.length} quotes</span><span>${m.stories.length} stories</span><span>${m.reels.length} reels</span><span>${m.videos.length} videos</span>
    </div>
    <div class="synced">Last synced ${esc(last)}${snap.problem ? `<div class="warn">${esc(snap.problem)}</div>` : ""}</div>
    <button class="rowbtn" data-act="sync">Sync now</button>
    <button class="rowbtn danger" data-act="disconnect">Disconnect</button>
  </div></div>`;
}

function viewConnect() {
  return `<main class="connect">
    <img class="bigtile" src="icon-512.png" alt="">
    <div class="name">Ortus</div>
    <form data-form="connect" class="col">
      <input name="link" placeholder="Setup link" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
      <button class="btn">Connect</button>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </form>
  </main>`;
}

function tabs() {
  return `<nav class="tabs ${ui.mode === "reels" || ui.mode === "videos" ? "dark" : ""}" aria-label="Ortus modes">${P.MODES.map(
    (k) => `<button class="tab ${ui.mode === k ? "on" : ""}" data-act="mode" data-v="${k}" ${ui.mode === k ? 'aria-current="page"' : ""}>${TAB_ICONS[k]}<span>${NAMES[k]}</span></button>`
  ).join("")}</nav>`;
}

function render() {
  const app = $("#app");
  if (!store.signedIn()) {
    app.innerHTML = viewConnect();
    return;
  }
  const m = model();
  const views = { quotes: viewQuotes, reels: viewReels, videos: viewVideos, stories: viewStories };
  const focused = document.activeElement && document.activeElement.dataset && document.activeElement.dataset.input === "query";
  app.innerHTML = views[ui.mode](m) + tabs() + (ui.settings ? viewSettings() : "") + (ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : "");
  app.className = ui.mode === "reels" || ui.mode === "videos" ? "dark" : "";
  document.body.classList.toggle("dark", ui.mode === "reels" || ui.mode === "videos");
  if (focused) {
    const input = app.querySelector('[data-input="query"]');
    if (input) {
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
    }
  }
}

function toast(text) {
  ui.toast = text;
  render();
  setTimeout(() => {
    ui.toast = "";
    render();
  }, 1600);
}

function setMode(mode) {
  ui.mode = mode;
  writeLocal("ortus.mode", mode);
  ui.story = null;
}

function step(kind, by) {
  ui.played = true;
  if (kind === "quote") ui.qi += by;
  if (kind === "reel") ui.ri += by;
  render();
}

async function shareQuote() {
  const list = quoteList(model());
  const q = list[wrap(ui.qi, list.length)];
  if (!q) return;
  const text = `“${q.text}” — ${q.author}`;
  try {
    if (navigator.share) await navigator.share({ text });
    else {
      await navigator.clipboard.writeText(text);
      toast("Copied");
    }
  } catch (e) {}
}

document.addEventListener("click", (e) => {
  const el = e.target.closest("[data-act]");
  if (!el) return;
  if (el.dataset.act === "close-settings" && e.target.closest("[data-stop]") && el.classList.contains("sheet")) return;
  const v = el.dataset.v;
  switch (el.dataset.act) {
    case "mode":
      setMode(v);
      break;
    case "theme":
      ui.theme = v;
      ui.qi = 0;
      writeLocal("ortus.theme", v || null);
      break;
    case "category":
      ui.category = v;
      ui.ri = 0;
      writeLocal("ortus.category", v || null);
      break;
    case "quote-next":
      return step("quote", 1);
    case "share-quote":
      return shareQuote();
    case "reel-next":
      return step("reel", 1);
    case "reel-prev":
      return step("reel", -1);
    case "video-next":
      ui.played = true;
      ui.vi += 1;
      break;
    case "video":
      ui.played = true;
      ui.vi = Number(v);
      break;
    case "kind":
      ui.kind = v;
      break;
    case "story":
      ui.story = v;
      document.querySelector(".screen")?.scrollTo(0, 0);
      break;
    case "story-back":
      ui.story = null;
      break;
    case "story-random": {
      const all = model().stories.filter((s) => s.id !== ui.story);
      if (all.length) ui.story = all[Math.floor(Math.random() * all.length)].id;
      break;
    }
    case "settings":
      ui.settings = true;
      break;
    case "close-settings":
      ui.settings = false;
      break;
    case "sync":
      store.syncNow().then(() => toast("Synced"));
      return;
    case "disconnect":
      ui.settings = false;
      store.disconnect();
      break;
    default:
      return;
  }
  render();
  if (el.dataset.act === "story") window.scrollTo(0, 0);
});

document.addEventListener("input", (e) => {
  const t = e.target;
  if (t.dataset.input === "query") {
    ui.query = t.value;
    render();
  }
  if (t.dataset.input === "verified") {
    writeLocal("ortus.verified", t.checked ? "1" : "0");
    ui.qi = 0;
    render();
  }
});

let touch = null;
document.addEventListener("touchstart", (e) => {
  const zone = e.target.closest("[data-swipe]");
  if (!zone || e.touches.length !== 1) return;
  touch = { kind: zone.dataset.swipe, x: e.touches[0].clientX, y: e.touches[0].clientY };
}, { passive: true });
document.addEventListener("touchend", (e) => {
  if (!touch) return;
  const t = e.changedTouches[0];
  const dx = t.clientX - touch.x;
  const dy = t.clientY - touch.y;
  const kind = touch.kind;
  touch = null;
  if (kind === "quote" && Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) step("quote", dx < 0 ? 1 : -1);
  if (kind === "reel" && Math.abs(dy) > 40 && Math.abs(dy) > Math.abs(dx)) step("reel", dy < 0 ? 1 : -1);
}, { passive: true });

document.addEventListener("keydown", (e) => {
  if (e.target.matches("input, textarea")) return;
  if (ui.mode === "quotes" && (e.key === "ArrowRight" || e.key === " ")) step("quote", 1);
  if (ui.mode === "quotes" && e.key === "ArrowLeft") step("quote", -1);
  if (ui.mode === "reels" && (e.key === "ArrowDown" || e.key === "j")) step("reel", 1);
  if (ui.mode === "reels" && (e.key === "ArrowUp" || e.key === "k")) step("reel", -1);
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const form = e.target;
  if (form.dataset.form !== "connect") return;
  const found = parseLink(new FormData(form).get("link") || "");
  if (!found) {
    ui.setupError = "Not a setup link";
    return render();
  }
  ui.setupError = "";
  store.configure(found.url, found.key);
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

let seen = -1;
function onStore() {
  const active = document.activeElement;
  if (active && active.matches && active.matches("input, select")) return;
  const rev = store.revision();
  if (document.querySelector("#player iframe") && seen >= 0 && !ui.settings) {
    seen = rev;
    return;
  }
  seen = rev;
  render();
}

readSetupLink();
store.subscribe(onStore);
render();
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
