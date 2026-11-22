import * as store from "./store.js";
import { $, esc, ICONS, isoNow, readJSON, readLocal, writeLocal, reduceMotion, buzz } from "./util.js";
import { LANGUAGES, GENRES, KINDS, KIND_NAMES, KIND_LANGS, KIND_GENRES, kindOf, noun, card, meta, metaRow, posterStyle, thumb, ratingText, ratingClass, genreList } from "./films.js";
import { attach, fly, springBack } from "./drag.js";
import { caller, createRoom, lobbyView, swipeView, matchedView, notice, nameSheet, bindSwipe } from "./room.js";
import { P, lk } from "./profile.js";

const SWIPE = `${P.pre}.swipe`;
const LOG = `${P.pre}.log`;
const UNSEEN = `${P.pre}.unseen`;
const GUIDE = `${P.pre}.guide`;
const VIEWS = ["recommend", "watchlist", "log", "match", "refiner", "ai"];
const REF_LANGS = ["English", "Hindi", "Telugu", "Tamil", "Malayalam", "Kannada", "Korean", "Japanese", "Spanish"];
const REF_GENRES = ["Action", "Animation", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Thriller", "War"];
const REF_KIND_LANGS = { movie: REF_LANGS, show: KIND_LANGS.show, anime: [] };
const REF_KIND_GENRES = { movie: REF_GENRES, show: KIND_GENRES.show, anime: KIND_GENRES.anime };
const START_KIND = KINDS.includes(readLocal(lk("kind"), "")) ? readLocal(lk("kind"), "") : "movie";

function filterKey(name, kind) {
  return kind === "movie" ? lk(name) : lk(`${name}.${kind}`);
}
const IDEAS = ["Cosy and clever", "Edge of my seat", "Make me cry", "Something weird"];
const ADDED = ["Any time", "This week", "This month"];
const SORTS = ["Rating", "Recently logged", "Title", "Year"];

function list(key, allowed) {
  const v = readJSON(key, []);
  return Array.isArray(v) ? v.filter((x) => allowed.includes(x)) : [];
}

function freshRef(langs = [], genres = [], kind = START_KIND) {
  return { step: "pick", kind, langs, genres, films: [], scores: {}, shown: [], fresh: [], rated: 0, unseen: 0, loading: false, error: "", taste: null, tasteLoading: false, tasteError: "", seq: 0 };
}

function freshAi(draft = "") {
  return { step: "mood", draft, mood: "", notes: [], thread: [], shown: [], films: [], chosen: null, round: 0, loading: false, error: "", note: "", seq: 0 };
}

const ui = {
  view: viewFromHash(),
  nav: false,
  sheet: null,
  pick: null,
  kind: START_KIND,
  langs: list(filterKey("langs", START_KIND), KIND_LANGS[START_KIND]),
  genres: list(filterKey("genres", START_KIND), KIND_GENRES[START_KIND]),
  queue: [],
  swiped: new Set(),
  history: [],
  loading: false,
  exhausted: false,
  deckError: "",
  gen: 0,
  enter: false,
  busy: false,
  wlLang: [],
  wlGenre: [],
  wlAdded: "Any time",
  logQuery: "",
  logSort: SORTS.includes(readLocal(lk("sort"), "")) ? readLocal(lk("sort"), "") : "Rating",
  setupError: "",
  toast: "",
  dragging: false,
  stale: false,
  name: readLocal(lk("name"), ""),
  nameDraft: readLocal(lk("name"), ""),
  askName: false,
  ref: freshRef(),
  ai: freshAi(),
};

const savedRoom = readJSON(lk("match"), null);
const room = createRoom({
  call: (body) => caller(store.projectUrl() + "/functions/v1/fabula-match", store.authHeaders())(body),
  code: savedRoom && savedRoom.code,
  member: savedRoom && savedRoom.member,
  save: (code, member) => writeLocal(lk("match"), code && member ? JSON.stringify({ code, member }) : null),
  onChange: () => {
    if (ui.view === "match") render();
  },
});

function viewFromHash() {
  const h = location.hash.replace(/^#/, "");
  return VIEWS.includes(h) ? h : "recommend";
}

function go(view) {
  ui.nav = false;
  ui.sheet = null;
  ui.pick = null;
  if (view === "refiner" && ui.ref.step === "done") ui.ref = freshRef(ui.ref.langs, ui.ref.genres, ui.ref.kind);
  if (ui.view === view) return render();
  ui.view = view;
  const hash = view === "recommend" ? "" : "#" + view;
  if (location.hash !== hash) history.pushState(null, "", location.pathname + location.search + hash);
  enterView();
}

function enterView() {
  room.show(ui.view === "match");
  if (ui.view === "match" && store.signedIn() && !room.code && !room.busy) {
    if (ui.name) createRoom_();
    else ui.askName = true;
  }
  render();
  window.scrollTo(0, 0);
}

function createRoom_() {
  ui.askName = false;
  room.create(ui.name, ui.langs.length ? ui.langs : null, ui.genres.length ? ui.genres : null, ui.kind);
}

window.addEventListener("popstate", () => {
  ui.view = viewFromHash();
  ui.nav = false;
  ui.sheet = null;
  ui.pick = null;
  enterView();
});

function swipeRecord(film, verdict) {
  const now = isoNow();
  return {
    tmdb: film.tmdb,
    kind: kindOf(film),
    verdict,
    at: now,
    title: film.title || "",
    year: film.year ?? null,
    poster: film.poster ?? null,
    language: film.language ?? null,
    genres: genreList(film),
    runtime: film.runtime ?? null,
    director: film.director ?? null,
    ...extras(film),
    updated: now,
  };
}

function logRecord(film, rating, comment) {
  const now = isoNow();
  const old = store.get(LOG, String(film.tmdb));
  return {
    tmdb: film.tmdb,
    kind: kindOf(film),
    title: film.title || "",
    year: film.year ?? null,
    rating,
    comment: comment || "",
    poster: film.poster ?? null,
    language: film.language ?? null,
    genres: genreList(film),
    director: film.director ?? null,
    runtime: film.runtime ?? null,
    ...extras(film),
    logged: (old && old.logged) || now,
    updated: now,
  };
}

function extras(film) {
  const out = {};
  for (const k of ["seasons", "episodes", "format"]) if (film[k] != null) out[k] = film[k];
  return out;
}

function setKind(kind) {
  if (!KINDS.includes(kind) || kind === ui.kind) return;
  ui.kind = kind;
  writeLocal(lk("kind"), kind);
  ui.langs = list(filterKey("langs", kind), KIND_LANGS[kind]);
  ui.genres = list(filterKey("genres", kind), KIND_GENRES[kind]);
  ui.wlLang = [];
  ui.wlGenre = [];
  ui.history = [];
  ui.hookOpen = null;
  resetDeck();
}

function kindSeg(act = "kind") {
  return `<div class="kseg" role="group">${KINDS.map(
    (k) => `<button class="kopt ${ui.kind === k ? "on" : ""}" data-act="${act}" data-v="${k}" aria-pressed="${ui.kind === k}">${KIND_NAMES[k]}</button>`
  ).join("")}</div>`;
}

function putSwipe(film, verdict) {
  store.put(SWIPE, String(film.tmdb), swipeRecord(film, verdict));
}

function tonight() {
  const t = readJSON(lk("tonight"), null);
  return t && t.tmdb ? Number(t.tmdb) : null;
}

function watchlist() {
  const logged = new Set(store.all(LOG).map((l) => Number(l.tmdb)));
  const pick = tonight();
  return store
    .all(SWIPE)
    .filter((s) => (s.verdict === "yes" || s.verdict === "super") && !logged.has(Number(s.tmdb)) && kindOf(s) === ui.kind)
    .sort((a, b) => {
      const pa = Number(a.tmdb) === pick ? 1 : 0;
      const pb = Number(b.tmdb) === pick ? 1 : 0;
      if (pa !== pb) return pb - pa;
      const sa = a.verdict === "super" ? 1 : 0;
      const sb = b.verdict === "super" ? 1 : 0;
      if (sa !== sb) return sb - sa;
      return String(b.at || "").localeCompare(String(a.at || ""));
    });
}

async function refill() {
  if (ui.loading || !store.signedIn()) return;
  ui.loading = true;
  const gen = ++ui.gen;
  if (!ui.queue.length) render();
  try {
    const exclude = [...new Set([...ui.swiped, ...ui.queue.map((f) => f.tmdb)])];
    const rows = await store.rpc("fabula_deck", {
      p_who: P.who,
      p_kind: ui.kind,
      p_langs: ui.langs.length && ui.kind !== "anime" ? ui.langs : null,
      p_genres: ui.genres.length ? ui.genres : null,
      p_limit: 20,
      p_exclude: exclude,
    });
    if (gen !== ui.gen) return;
    const have = new Set(exclude);
    const fresh = (Array.isArray(rows) ? rows : []).filter((f) => f && f.tmdb && !have.has(f.tmdb));
    ui.queue.push(...fresh);
    ui.exhausted = fresh.length === 0;
    ui.deckError = "";
  } catch (e) {
    if (gen === ui.gen) ui.deckError = e.message || `Can't load ${noun(ui.kind, 2)}`;
  } finally {
    if (gen === ui.gen) {
      ui.loading = false;
      render();
    }
  }
}

function maybeRefill() {
  if (ui.queue.length <= 5 && !ui.exhausted && !ui.deckError) refill();
}

function resetDeck() {
  ui.gen++;
  ui.loading = false;
  ui.queue = [];
  ui.exhausted = false;
  ui.deckError = "";
  refill();
}

function advance(film, verdict) {
  ui.history.push({ film, verdict, logged: false });
  if (ui.history.length > 50) ui.history.shift();
  ui.swiped.add(film.tmdb);
  ui.queue = ui.queue.filter((f) => f.tmdb !== film.tmdb);
  ui.enter = true;
  maybeRefill();
}

async function commit(dir, el) {
  const film = ui.queue[0];
  if (!film || ui.busy) return;
  ui.busy = true;
  ui.dragging = true;
  if (el) await fly(el, dir);
  ui.busy = false;
  ui.dragging = false;
  const verdict = { right: "yes", left: "no", up: "seen" }[dir];
  putSwipe(film, verdict);
  advance(film, verdict);
  if (verdict === "seen") ui.sheet = { type: "rate", mode: "seen", film, rating: null, comment: "" };
  render();
}

function superlike(el) {
  const film = ui.queue[0];
  if (!film || ui.busy) return;
  ui.busy = true;
  ui.dragging = true;
  buzz(30);
  const quick = reduceMotion();
  if (!quick) el.classList.add("shake");
  setTimeout(() => {
    el.classList.remove("shake");
    el.classList.add("gold");
    putSwipe(film, "super");
    setTimeout(() => {
      ui.busy = false;
      ui.dragging = false;
      advance(film, "super");
      ui.enter = false;
      ui.pick = film;
      render();
    }, quick ? 150 : 380);
  }, quick ? 0 : 520);
}

function undo() {
  if (ui.busy) return;
  const last = ui.history.pop();
  if (!last) return;
  const id = String(last.film.tmdb);
  store.remove(SWIPE, id);
  if (last.logged) store.remove(LOG, id);
  if (tonight() === last.film.tmdb) writeLocal(lk("tonight"), null);
  ui.swiped.delete(last.film.tmdb);
  ui.queue = [last.film, ...ui.queue.filter((f) => f.tmdb !== last.film.tmdb)];
  if (ui.sheet && ui.sheet.film && ui.sheet.film.tmdb === last.film.tmdb) ui.sheet = null;
  ui.pick = null;
  ui.enter = false;
  render();
}

function sum(arr, word) {
  return arr.length === 0 ? word : arr.length === 1 ? arr[0] : `${word} · ${arr.length}`;
}

function pill(label, on, act, v) {
  return `<button class="pill ${on ? "on" : ""}" data-act="${act}" data-v="${v}">${esc(label)} ▾</button>`;
}

function header() {
  return `<header class="head">
    <button class="brand" data-act="nav" aria-label="Open menu"><img src="logo-96.png" alt=""><span>${esc(P.name)}</span>${ICONS.chevron}</button>
    <div class="acts">
      <button class="round" data-act="go" data-v="watchlist" aria-label="Watchlist" title="Watchlist">${ICONS.bookmark}</button>
    </div>
  </header>`;
}

function subhead(title, right = "") {
  return `<header class="head sub"><button class="backbtn" data-act="go" data-v="recommend" aria-label="Back to Recommend">${ICONS.back}</button><h1>${esc(title)}</h1>${right}</header>`;
}

function viewRecommend() {
  const top = ui.queue[0];
  let stage;
  if (top) {
    stage = `${card(ui.queue[1])}${card(top, { top: true, undo: true, canUndo: ui.history.length > 0, open: ui.hookOpen === top.tmdb })}`;
  } else if (ui.deckError) {
    stage = `<div class="plate"></div><div class="done"><b>Can't load ${noun(ui.kind, 2)}</b><span>${esc(ui.deckError)}</span><button class="btn" data-act="retry">Try again</button></div>`;
  } else if (ui.loading || !ui.exhausted) {
    stage = `<div class="plate"></div><div class="card skeleton"><div class="face"><div class="poster"></div><div class="lower"><div class="info"><span class="bar w60"></span><span class="bar"></span><span class="bar w80"></span></div></div></div></div>`;
  } else {
    stage = `<div class="plate"></div><div class="done"><b>That's every ${noun(ui.kind)} for now</b>${
      ui.langs.length || ui.genres.length ? `<button class="btn ghost" data-act="clear-all">Clear filters</button>` : ""
    }${ui.history.length ? `<button class="iconbtn" data-act="undo" aria-label="Undo last swipe">${ICONS.undo}</button>` : ""}</div>`;
  }
  return `<main class="screen rec">
    ${header()}
    <div class="pills">${pill(KIND_NAMES[ui.kind], false, "filter", "kind")}${ui.kind === "anime" ? "" : pill(sum(ui.langs, "Language"), ui.langs.length, "filter", "langs")}${pill(sum(ui.genres, "Genre"), ui.genres.length, "filter", "genres")}</div>
    <div class="stack">${stage}</div>
  </main>`;
}

function chips(names, chosen, act) {
  return `<div class="chips">${names
    .map((n) => `<button class="chip ${chosen(n) ? "on" : ""}" data-act="${act}" data-v="${esc(n)}" aria-pressed="${chosen(n)}">${esc(n)}</button>`)
    .join("")}</div>`;
}

let lastSheet = null;
let lastPick = null;
let lastNav = false;

function sheet(inner, cls = "") {
  const fresh = ui.sheet !== lastSheet ? "fresh" : "";
  return `<div class="sheet ${cls} ${fresh}" data-act="close-sheet"><div class="panel" data-stop><div class="grip"></div>${inner}</div></div>`;
}

function filterSheet() {
  const s = ui.sheet;
  const deck = s.key === "langs" || s.key === "genres";
  let title, names, chosen;
  if (s.key === "kind") {
    return sheet(`<h2>Type</h2>${chips(KINDS.map((k) => KIND_NAMES[k]), (n) => KIND_NAMES[s.draft] === n, "opt")}
    <div class="two"><button class="btn wide" data-act="opt-done">Done</button></div>`);
  }
  if (deck) {
    title = s.key === "langs" ? "Language" : "Genre";
    names = s.key === "langs" ? KIND_LANGS[ui.kind] : KIND_GENRES[ui.kind];
    chosen = (n) => s.draft.includes(n);
  } else {
    const items = watchlist();
    if (s.key === "added") {
      title = "Added";
      names = ADDED;
      chosen = (n) => s.draft === n;
    } else if (s.key === "lang") {
      title = "Language";
      const present = new Set(items.map((f) => f.language).filter(Boolean));
      names = [...LANGUAGES.filter((l) => present.has(l)), ...[...present].filter((l) => !LANGUAGES.includes(l)).sort()];
      chosen = (n) => s.draft.includes(n);
    } else {
      title = "Genre";
      const present = new Set(items.flatMap((f) => genreList(f)));
      names = [...GENRES.filter((g) => present.has(g)), ...[...present].filter((g) => !GENRES.includes(g)).sort()];
      chosen = (n) => s.draft.includes(n);
    }
  }
  return sheet(`<h2>${title}</h2>${chips(names, chosen, "opt")}
    <div class="two"><button class="btn ghost" data-act="opt-clear">Clear</button><button class="btn wide" data-act="opt-done">Done</button></div>`);
}

function rateSheet() {
  const s = ui.sheet;
  const f = s.film;
  const sub = [f.year, f.director].filter(Boolean).join(" · ");
  const grid = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    .map((n) => `<button class="score ${Number(s.rating) === n ? "on" : ""}" data-act="score" data-v="${n}" aria-label="Rate ${n}">${n}</button>`)
    .join("");
  const edit = s.mode === "edit";
  return sheet(
    `<div class="titles"><h2>How was ${esc(f.title)}?</h2>${sub ? `<span class="muted">${esc(sub)}</span>` : ""}</div>
    <div class="scores">${grid}</div>
    <input class="field" data-input="comment" aria-label="Comments" placeholder="Tell us about the ${{ movie: "movie", show: "show", anime: "anime" }[kindOf(f)]}!" value="${esc(s.comment)}" maxlength="500">
    <div class="two">${
      edit ? `<button class="btn ghost danger" data-act="log-delete">Delete</button>` : `<button class="btn ghost" data-act="rate-skip">Skip rating</button>`
    }<button class="btn wide" data-act="rate-save" ${s.rating ? "" : "disabled"}>${edit ? "Save" : "Save to Log"}</button></div>`,
    "rate"
  );
}

function wlFilmSheet() {
  const f = ui.sheet.film;
  return sheet(`<div class="wlhead">${thumb(f, "thumb lg")}<div class="titles"><h2>${esc(f.title)}</h2>${metaRow(f, undefined, "muted")}</div></div>
    <div class="two"><button class="btn ghost danger" data-act="wl-remove">Remove</button><button class="btn wide" data-act="wl-seen">Seen it</button></div>`);
}

function addSheet() {
  const s = ui.sheet;
  return sheet(
    `<h2>Add ${ui.kind === "anime" ? "an anime" : `a ${noun(ui.kind)}`}</h2>
    <div class="searchrow">${ICONS.search}<input class="field" type="search" data-input="add-q" aria-label="Search ${noun(ui.kind, 2)}" placeholder="Search ${noun(ui.kind, 2)}" value="${esc(s.q)}" autocomplete="off" autocapitalize="off" spellcheck="false"></div>
    <div class="results" id="add-results">${addResults()}</div>`,
    "add"
  );
}

function addResults() {
  const s = ui.sheet;
  if (!s || s.type !== "add") return "";
  if (s.error) return `<div class="warn">${esc(s.error)}</div>`;
  if (s.loading && !s.results.length) return `<div class="spin"></div>`;
  return s.results
    .map(
      (r) => `<button class="result" data-act="add-pick" data-v="${esc(r.tmdb)}">${thumb(r, "thumb sm")}<span class="rt"><b>${esc(r.title)}</b><span class="muted">${esc(
        [r.year, r.format || r.language, r.original_title && r.original_title !== r.title ? r.original_title : ""].filter(Boolean).join(" · ")
      )}</span></span>${store.get(LOG, String(r.tmdb)) ? `<span class="rating ${ratingClass(store.get(LOG, String(r.tmdb)).rating)}">${esc(ratingText(store.get(LOG, String(r.tmdb)).rating))}</span>` : ""}</button>`
    )
    .join("");
}

function sortSheet() {
  return sheet(`<h2>Sort</h2>${chips(SORTS, (n) => ui.logSort === n, "sort")}`);
}

function pickView(fresh) {
  const f = ui.pick;
  const others = watchlist()
    .filter((w) => Number(w.tmdb) !== f.tmdb)
    .slice(0, 3);
  const providers = Array.isArray(f.providers) ? f.providers : [];
  return `<div class="pick ${fresh ? "fresh" : ""}">
    <span class="kicker">Tonight's pick</span>
    <div class="pposter" style="${posterStyle(f, "w500")}"><span>${esc(f.title)}</span></div>
    <div class="ptext"><h2>${esc(f.title)}</h2>${metaRow(f, { director: true }, "muted")}${
      providers.length ? `<span class="stream">Streaming on ${esc(providers.slice(0, 2).join(" and "))} in India</span>` : ""
    }</div>
    ${
      others.length
        ? `<div class="others"><span class="faint">Your other yeses tonight</span><div class="otherrow">${others
            .map((o) => `<div class="other" style="${posterStyle(o, "w185")}"><span>${esc(o.title)}</span></div>`)
            .join("")}</div></div>`
        : ""
    }
    <div class="pacts"><button class="btn big gold" data-act="pick-watch">Watch this tonight</button><button class="link" data-act="pick-keep">Keep swiping</button></div>
  </div>`;
}

function inRange(at, label) {
  if (label === "Any time") return true;
  const t = Date.parse(at || "");
  if (!t) return false;
  const days = label === "This week" ? 7 : 31;
  return Date.now() - t <= days * 86400000;
}

function when(at) {
  const t = new Date(at || "");
  if (isNaN(t)) return "";
  const day = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const diff = Math.round((day(new Date()) - day(t)) / 86400000);
  if (diff === 0) return "Today";
  if (diff === 1) return "Yesterday";
  return t.toLocaleDateString([], { day: "numeric", month: "short", year: t.getFullYear() === new Date().getFullYear() ? undefined : "numeric" });
}

function viewWatchlist() {
  const pick = tonight();
  const items = watchlist().filter(
    (f) =>
      (!ui.wlLang.length || ui.wlLang.includes(f.language)) &&
      (!ui.wlGenre.length || genreList(f).some((g) => ui.wlGenre.includes(g))) &&
      inRange(f.at, ui.wlAdded)
  );
  const supers = items.filter((f) => f.verdict === "super");
  const yeses = items.filter((f) => f.verdict !== "super");
  const row = (f, gold) => {
    const isPick = Number(f.tmdb) === pick;
    const d = isPick ? "Tonight's pick" : gold ? `Superliked ${when(f.at).replace(/^Today$/, "today").replace(/^Yesterday$/, "yesterday")}` : when(f.at);
    return `<button class="wl ${gold ? "gold" : ""} ${isPick ? "tonight" : ""}" data-act="wl-open" data-v="${esc(f.tmdb)}">
      ${thumb(f, gold ? "thumb md" : "thumb")}
      <span class="rt"><b>${esc(f.title)}</b><span class="muted">${esc(meta(f, { genres: 1 }))}</span>${gold ? `<span class="faint">${esc(d)}</span>` : ""}</span>
      ${gold ? `<span class="staricon">${ICONS.star}</span>` : `<span class="faint">${esc(d)}</span>`}
    </button>`;
  };
  const total = items.length;
  return `<main class="screen wlist">
    ${subhead("Watchlist", `<span class="count">${total} ${noun(ui.kind, total)}</span>`)}
    ${kindSeg()}
    <div class="pills three">${pill(sum(ui.wlLang, "Language"), ui.wlLang.length, "wfilter", "lang")}${pill(sum(ui.wlGenre, "Genre"), ui.wlGenre.length, "wfilter", "genre")}${pill(
    ui.wlAdded,
    ui.wlAdded !== "Any time",
    "wfilter",
    "added"
  )}</div>
    <div class="rows">
      ${supers.length ? `<span class="section gold">Superlikes · ${supers.length}</span>${supers.map((f) => row(f, true)).join("")}` : ""}
      ${yeses.length ? `<span class="section green">Yeses · ${yeses.length}</span>${yeses.map((f) => row(f, false)).join("")}` : ""}
      ${total ? "" : `<div class="done quiet"><b>Nothing here yet</b></div>`}
    </div>
  </main>`;
}

function logStats(logs) {
  const rated = logs.filter((l) => Number.isFinite(Number(l.rating)));
  const avg = rated.length ? rated.reduce((a, l) => a + Number(l.rating), 0) / rated.length : null;
  const decades = {};
  for (const l of rated) {
    const y = Number(l.year);
    if (!y) continue;
    const d = Math.floor(y / 10) * 10;
    (decades[d] = decades[d] || []).push(Number(l.rating));
  }
  let best = null;
  for (const d in decades) {
    const r = decades[d];
    if (r.length < 3) continue;
    const a = r.reduce((x, y) => x + y, 0) / r.length;
    if (!best || a > best.avg || (a === best.avg && r.length > best.n)) best = { d, avg: a, n: r.length };
  }
  return { count: logs.length, avg: avg == null ? "–" : avg.toFixed(1), best: best ? best.d + "s" : "–" };
}

function logItems() {
  const q = ui.logQuery.trim().toLowerCase();
  const logs = store.all(LOG).filter((l) => kindOf(l) === ui.kind).filter((l) => !q || [l.title, l.comment, l.director, l.year, l.language].join(" ").toLowerCase().includes(q));
  const by = {
    Rating: (a, b) => Number(b.rating) - Number(a.rating) || String(b.logged || "").localeCompare(String(a.logged || "")),
    "Recently logged": (a, b) => String(b.logged || "").localeCompare(String(a.logged || "")),
    Title: (a, b) => String(a.title).localeCompare(String(b.title)),
    Year: (a, b) => Number(b.year || 0) - Number(a.year || 0) || String(a.title).localeCompare(String(b.title)),
  }[ui.logSort];
  return logs.sort(by);
}

function logRows() {
  return logItems()
    .map(
      (l) => `<button class="lrow" data-act="log-open" data-v="${esc(l.tmdb)}">${thumb(l, "thumb sm")}
      <span class="rt"><b>${esc(l.title)}${l.year ? ` · ${esc(l.year)}` : ""}</b>${l.comment ? `<span class="muted">${esc(l.comment)}</span>` : ""}</span>
      <span class="rating ${ratingClass(l.rating)}">${esc(ratingText(l.rating))}</span></button>`
    )
    .join("");
}

function viewLog() {
  const logs = store.all(LOG).filter((l) => kindOf(l) === ui.kind);
  const st = logStats(logs);
  return `<main class="screen log">
    ${subhead("Log", `<button class="addbtn" data-act="add-open" aria-label="Add ${noun(ui.kind)}">+ Add ${noun(ui.kind)}</button>`)}
    ${kindSeg()}
    <div class="stats">
      <div class="stat"><b>${st.count}</b><span>${noun(ui.kind, st.count)} logged</span></div>
      <div class="stat"><b>${st.avg}</b><span>your average</span></div>
      <div class="stat"><b>${st.best}</b><span>best decade</span></div>
    </div>
    <div class="searchbar"><input type="search" class="field" data-input="log-q" aria-label="Search your log" placeholder="Search ${st.count} ${noun(ui.kind, st.count)}" value="${esc(ui.logQuery)}"><button class="sortbtn" data-act="sort-open">${esc(ui.logSort)} ▾</button></div>
    <div class="lrows" id="log-rows">${logRows()}</div>
  </main>`;
}

function shareLink() {
  let ref = "";
  try {
    ref = new URL(store.projectUrl()).hostname.split(".")[0];
  } catch (e) {}
  const u = new URL("match.html", location.href);
  u.search = "";
  u.hash = ref + "." + room.code;
  return u.toString();
}

function viewMatch() {
  const top = `<div class="mbar"><button class="link" data-act="go" data-v="recommend">‹ Back</button>${room.code ? `<button class="link" data-act="match-leave">Leave</button>` : ""}</div>`;
  if (ui.askName && !room.code) {
    return `<main class="screen match">${top}<div class="mhead"><h1>Watch Party</h1></div></main>${nameSheet(ui.nameDraft, room.busy)}`;
  }
  if (room.error && !room.state) {
    const again = `<button class="btn" data-act="match-new">${room.code ? "Try again" : "New match night"}</button>`;
    return `<main class="screen match">${top}${notice(room.error.message, "", again)}</main>`;
  }
  if (!room.state) return `<main class="screen match">${top}<div class="mhead"><h1>Watch Party</h1></div><div class="spin"></div></main>`;
  const s = room.state;
  if (s.matched) return matchedView(room, { host: true });
  if (s.started) return swipeView(room, { host: true, top });
  return lobbyView(room, { host: true, link: shareLink(), top });
}

function backhead(title, act, label, right = "") {
  return `<header class="head bk"><button class="rback" data-act="${act}" aria-label="${esc(label)}">${ICONS.back}</button><h1>${esc(title)}</h1>${right}</header>`;
}

function refChoice(r) {
  const lang = r.kind === "anime" ? "" : `${r.langs.length ? r.langs.join(", ") : "Any language"} · `;
  return `${KIND_NAMES[r.kind]} · ${lang}${r.genres.length ? r.genres.join(", ") : "Any genre"}`;
}

function refRated(r) {
  return r.rated + Object.keys(r.scores).length;
}

function refRow(f) {
  const id = String(f.tmdb);
  const s = ui.ref.scores[id];
  return `<div class="rf-row">
    <div class="rf-poster" style="${posterStyle(f, "w342")}"></div>
    <div class="rf-body">
      <b class="rf-title">${esc(f.title)}</b>
      <span class="muted">${esc(kindOf(f) === "movie" ? [f.year, f.director].filter(Boolean).join(" · ") : meta(f, { director: true }))}</span>
      ${f.overview ? `<span class="rf-blurb">${esc(f.overview)}</span>` : ""}
      <div class="rf-rate"><input type="range" min="1" max="10" step="1" value="${s || 5}" class="range ${s ? "" : "untouched"}" data-input="ref-score" data-v="${esc(id)}" aria-label="Rate ${esc(f.title)}"><span class="rf-val ${s ? "on" : ""}">${s ? `${s} / 10` : "Not seen"}</span></div>
    </div>
  </div>`;
}

function rowSkeleton(cls) {
  return `<div class="${cls} skeleton"><div class="${cls === "rf-row" ? "rf-poster" : "ai-poster"} shimmer"></div><div class="rf-body"><span class="bar w60"></span><span class="bar w80"></span><span class="bar"></span><span class="bar w60"></span></div></div>`;
}

function viewRefiner() {
  const r = ui.ref;
  if (r.step === "list") {
    let body;
    if (r.loading) body = [0, 1, 2, 3].map(() => rowSkeleton("rf-row")).join("");
    else if (r.error) body = `<div class="done quiet"><b>Can't load ${noun(r.kind, 2)}</b><span>${esc(r.error)}</span><button class="btn" data-act="ref-retry">Try again</button></div>`;
    else if (!r.films.length) body = `<div class="done quiet"><b>That's every ${noun(r.kind)} for now</b></div>`;
    else body = r.films.map(refRow).join("");
    const foot = r.loading
      ? ""
      : `<div class="two rf-foot"><button class="btn ghost" data-act="ref-stop">Stop</button>${r.films.length && !r.error ? `<button class="btn wide" data-act="ref-more">Continue: 10 more</button>` : ""}</div>`;
    return `<main class="screen rf-list">
      <header class="rf-head"><button class="rback" data-act="ref-back" aria-label="Change what to refine">${ICONS.back}</button><div class="rf-ttl"><h1>Refiner</h1><span>${esc(refChoice(r))}</span></div><span class="rf-count" id="ref-count">${refRated(r)} rated</span></header>
      <div class="rf-rows">${body}${foot}</div>
    </main>`;
  }
  if (r.step === "done") {
    return `<main class="screen rf-done">
      <div class="rf-hero"><div class="rf-tick">${ICONS.check}</div><h1>Taste updated</h1><span class="muted">${r.rated} ${noun(r.kind, r.rated)} rated, ${r.unseen} not seen.</span></div>
      ${r.fresh.length ? tasteCards(r) : ""}
      <div class="grow"></div>
      <button class="btn big" data-act="ref-home">Back to Recommend</button>
      <button class="link" data-act="ref-again">Refine something else</button>
    </main>`;
  }
  const on = (key) => (n) => (n === "Any" ? !r[key].length : r[key].includes(n));
  return `<main class="screen rf-pick">
    ${backhead("Refiner", "nav", "Back to menu")}
    <h1 class="bigq">What would you like to refine?</h1>
    <div class="rf-group"><span class="flabel">Type</span>${chips(KINDS.map((k) => KIND_NAMES[k]), (n) => KIND_NAMES[r.kind] === n, "ref-kind")}</div>
    ${r.kind === "anime" ? "" : `<div class="rf-group"><span class="flabel">Language</span>${chips(["Any", ...REF_KIND_LANGS[r.kind]], on("langs"), "ref-lang")}</div>`}
    <div class="rf-group"><span class="flabel">Genre</span>${chips(["Any", ...REF_KIND_GENRES[r.kind]], on("genres"), "ref-genre")}</div>
    <div class="grow"></div>
    <button class="btn big" data-act="ref-start">Start refining</button>
  </main>`;
}

function label(x) {
  return typeof x === "string" ? x : x && (x.label || x.name || x.text) ? x.label || x.name || x.text : "";
}

function tasteCards(r) {
  if (r.tasteLoading || (!r.taste && !r.tasteError)) {
    return `<div class="tcard skeleton"><span class="flabel">What changed</span><span class="bar w80"></span><span class="bar w60"></span><span class="bar w80"></span></div>
      <div class="tcard wash skeleton"><span class="flabel">Your taste, in a line</span><span class="bar"></span><span class="bar w60"></span></div>`;
  }
  if (r.tasteError) return `<div class="tcard"><span class="warn">${esc(r.tasteError)}</span><button class="btn ghost" data-act="ref-taste">Try again</button></div>`;
  const t = r.taste || {};
  const more = (Array.isArray(t.more) ? t.more : []).map(label).filter(Boolean);
  const less = (Array.isArray(t.less) ? t.less : []).map(label).filter(Boolean);
  const rows = [...more.map((m) => `<div class="tline"><span>${esc(m)}</span><span class="up">↑ more</span></div>`), ...less.map((m) => `<div class="tline"><span>${esc(m)}</span><span class="down">↓ less</span></div>`)].join("");
  return `${rows ? `<div class="tcard"><span class="flabel">What changed</span>${rows}</div>` : ""}${
    t.summary ? `<div class="tcard wash"><span class="flabel">Your taste, in a line</span><span class="tsum">${esc(t.summary)}</span></div>` : ""
  }`;
}

function aiCard(f) {
  const on = ui.ai.chosen === Number(f.tmdb);
  return `<div class="ai-card ${on ? "on" : ""}">
    <div class="ai-poster" style="${posterStyle(f, "w342")}"></div>
    <div class="rf-body">
      <b class="rf-title">${esc(f.title)}</b>
      ${metaRow(f, { director: true }, "muted")}
      ${f.why ? `<span class="ai-why">${esc(f.why)}</span>` : ""}
      <button class="ai-pick ${on ? "on" : ""}" data-act="ai-choose" data-v="${esc(f.tmdb)}" aria-pressed="${on}">${on ? "Chosen" : "This one"}</button>
    </div>
  </div>`;
}

function viewAi() {
  const a = ui.ai;
  if (a.step !== "results") {
    return `<main class="screen ai-mood">
      ${backhead("AI Mode", "nav", "Back to menu")}
      <div class="grow"></div>
      <div class="ai-hero"><div class="ai-spark">${ICONS.sparkle}</div><h1 class="bigq">What are you in the mood for?</h1></div>
      ${kindSeg()}
      <div class="ai-ideas">${IDEAS.map((i) => `<button class="ai-idea" data-act="ai-idea" data-v="${esc(i)}">${esc(i)}</button>`).join("")}</div>
      <div class="grow"></div>
      <form class="ai-box" data-form="mood">
        <label class="flabel" for="ai-mood">Your mood</label>
        <textarea id="ai-mood" rows="4" data-input="ai-mood" maxlength="500" placeholder="Rainy Sunday, want something cosy but not dumb, under 2 hours">${esc(a.draft)}</textarea>
        <button class="btn big ai-find" ${a.draft.trim().length < 2 ? "disabled" : ""}>Find ${noun(ui.kind, 2)}${ICONS.arrow}</button>
      </form>
    </main>`;
  }
  let cards;
  if (a.loading) cards = [0, 1, 2, 3].map(() => rowSkeleton("ai-card")).join("");
  else if (!a.films.length && !a.error) cards = `<div class="done quiet"><b>Nothing new this round</b></div>`;
  else cards = a.films.map(aiCard).join("");
  const chosen = a.films.find((f) => Number(f.tmdb) === a.chosen);
  return `<main class="screen ai-res">
    <header class="ai-head">
      <div class="ai-top"><button class="rback" data-act="ai-back" aria-label="Change mood">${ICONS.back}</button><h1>AI Mode</h1><span class="faint">Round ${a.round}</span></div>
      <div class="ai-thread">${a.thread
        .slice(-2)
        .map((t) => `<span class="bubble">${esc(t)}</span>`)
        .join("")}</div>
    </header>
    <div class="ai-cards">${cards}${a.error ? `<div class="warn ai-err">${esc(a.error)}</div>` : ""}</div>
    <div class="ai-bar">
      ${chosen && !a.loading ? `<button class="btn big gold" data-act="ai-watch">Watch ${esc(chosen.title)} tonight</button>` : ""}
      <form class="ai-tune" data-form="tune"><label class="sr" for="ai-note">Fine-tune these picks</label><input id="ai-note" class="field" data-input="ai-note" placeholder="Less animation, more like Knives Out" value="${esc(
        a.note
      )}" maxlength="300" autocomplete="off"><button class="ai-send" aria-label="Send fine-tune note" ${a.loading ? "disabled" : ""}>${ICONS.arrow}</button></form>
      <button class="btn ghost ai-none" data-act="ai-none" ${a.loading ? "disabled" : ""}>None of these, try again</button>
    </div>
  </main>`;
}

function sidebar() {
  const item = (v, icon, label) =>
    `<button class="navitem ${ui.view === v ? "on" : ""}" data-act="go" data-v="${v}">${icon}${label}</button>`;
  return `<div class="scrim" data-act="nav-close"></div>
  <nav class="side" aria-label="${esc(P.name)}">
    <div class="sidebrand"><img src="logo-96.png" alt=""><span>${esc(P.name)}</span></div>
    ${item("recommend", ICONS.cards, "Recommend")}${item("log", ICONS.list, "Log")}${item("refiner", ICONS.sliders, "Refiner")}${item("ai", ICONS.sparkle, "AI Mode")}
    <button class="navitem party ${ui.view === "match" ? "on" : ""}" data-act="go" data-v="match">${ICONS.people}Watch Party</button>
  </nav>`;
}

function viewConnect() {
  return `<main class="connect">
    <img class="bigtile" src="icon-512.png" alt="">
    <div class="name">${esc(P.name)}</div>
    <form data-form="connect" class="col">
      <input class="field" name="link" placeholder="Setup link" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
      <button class="btn big">Connect</button>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </form>
  </main>`;
}

const guide = { cache: {}, scores: {}, loading: false, error: "", batch: null, ready: false, dropping: false, taste: null, tasteLoading: false, tasteError: "", seq: 0, short: {} };

function guideList() {
  const d = store.get(GUIDE, "list");
  if (!d || !Array.isArray(d.langs)) return null;
  return d.langs.map((l) => ({ name: String(l.name || ""), per: Number(l.per) || 40, seed: (Array.isArray(l.seed) ? l.seed : []).map(Number).filter(Boolean) }));
}

function guideDone() {
  return !!store.get(GUIDE, "done");
}

function guideAnswered(id) {
  return !!(store.get(LOG, String(id)) || store.get(UNSEEN, String(id)));
}

function guideRecords() {
  return [...store.all(LOG), ...store.all(UNSEEN)].filter((d) => d && d.guide);
}

function guideState() {
  const langs = guideList();
  if (!langs) return null;
  const mine = guideRecords();
  const counts = langs.map((l) => Math.min(l.per, mine.filter((d) => d.guide === l.name).length));
  const stage = langs.findIndex((l, i) => counts[i] < l.per && !guide.short[l.name]);
  const total = counts.reduce((a, b) => a + b, 0);
  const all = langs.reduce((a, l) => a + l.per, 0);
  let next = [];
  let need = 0;
  if (stage >= 0) {
    const l = langs[stage];
    need = Math.min(10, l.per - counts[stage]);
    const seedLeft = l.seed.filter((id) => !guideAnswered(id));
    if (seedLeft.length) next = seedLeft.slice(0, need);
    else if (guide.batch && guide.batch.lang === l.name) next = guide.batch.ids.filter((id) => !guideAnswered(id)).slice(0, need);
  }
  return { langs, counts, stage, total, all, next, need };
}

function guideGated() {
  return P.guided && store.signedIn() && (guide.ready || !guideDone());
}

async function guideLoad(ids) {
  const want = ids.filter((id) => !guide.cache[id]);
  if (!want.length || guide.loading) return;
  guide.loading = true;
  guide.error = "";
  const seq = ++guide.seq;
  try {
    const rows = await store.rpc("fabula_films", { p_ids: want });
    for (const f of Array.isArray(rows) ? rows : []) if (f && f.tmdb) guide.cache[f.tmdb] = f;
  } catch (e) {
    guide.error = e.message || "Can't load movies";
  }
  if (seq !== guide.seq) return;
  guide.loading = false;
  render();
}

async function guidePick(st) {
  if (guide.loading) return;
  const l = st.langs[st.stage];
  guide.loading = true;
  guide.error = "";
  const seq = ++guide.seq;
  try {
    await store.pushNow();
    const exclude = guideRecords().map((d) => Number(d.tmdb)).filter(Boolean);
    const rows = await store.rpc("fabula_guide", { p_who: P.who, p_lang: l.name, p_limit: st.need, p_exclude: exclude });
    const films = (Array.isArray(rows) ? rows : []).filter((f) => f && f.tmdb && !guideAnswered(f.tmdb));
    for (const f of films) guide.cache[f.tmdb] = f;
    if (seq === guide.seq) {
      guide.batch = { lang: l.name, ids: films.map((f) => f.tmdb) };
      if (!films.length) guide.short[l.name] = true;
    }
  } catch (e) {
    guide.error = e.message || "Can't load movies";
  }
  if (seq !== guide.seq) return;
  guide.loading = false;
  if (guideState() && guideState().stage < 0) return guideFinish();
  render();
}

function guideRow(f) {
  const id = String(f.tmdb);
  const s = guide.scores[id];
  return `<div class="rf-row">
    <div class="rf-poster" style="${posterStyle(f, "w342")}"></div>
    <div class="rf-body">
      <b class="rf-title">${esc(f.title)}</b>
      <span class="muted">${esc(kindOf(f) === "movie" ? [f.year, f.director].filter(Boolean).join(" · ") : meta(f, { genres: 1 }))}
      ${f.overview ? `<span class="rf-blurb">${esc(f.overview)}</span>` : ""}
      <div class="rf-rate"><input type="range" min="1" max="10" step="1" value="${s || 5}" class="range ${s ? "" : "untouched"}" data-input="guide-score" data-v="${esc(id)}" aria-label="Rate ${esc(f.title)}"><span class="rf-val ${s ? "on" : ""}">${s ? `${s} / 10` : "Not seen"}</span></div>
    </div>
  </div>`;
}

function guideHead(st) {
  const bars = st
    ? st.langs
        .map((l, i) => {
          const c = st.counts[i];
          const n = l.per || 1;
          return `<div class="gd-stage ${i === st.stage ? "on" : ""}"><div class="gd-bar"><i style="width:${Math.round((c / n) * 100)}%" class="${c >= n ? "full" : ""}"></i></div><span>${esc(l.name)} ${c}/${l.per}</span></div>`;
        })
        .join("")
    : "";
  return `<header class="gd-head">
    <div class="gd-top"><div class="brand still"><img src="logo-96.png" alt=""><span>${esc(P.name)}</span></div>${st ? `<span class="rf-count" id="guide-count">${st.total} / ${st.all}</span>` : ""}</div>
    ${bars ? `<div class="gd-stages">${bars}</div>` : ""}
  </header>`;
}

function viewGuide() {
  if (guide.ready) return viewGuideReady();
  const st = guideState();
  let body;
  if (!st || st.stage < 0) body = [0, 1, 2].map(() => rowSkeleton("rf-row")).join("");
  else {
    const films = st.next.map((id) => guide.cache[id]).filter(Boolean);
    if (guide.error) {
      body = `<div class="done quiet"><b>Can't load movies</b><span>${esc(guide.error)}</span><button class="btn" data-act="guide-retry">Try again</button></div>`;
    } else if (!st.next.length || films.length < st.next.length) {
      if (!guide.loading) queueMicrotask(() => (st.next.length ? guideLoad(st.next) : guidePick(st)));
      body = [0, 1, 2, 3].map(() => rowSkeleton("rf-row")).join("");
    } else {
      const l = st.langs[st.stage];
      const from = st.counts[st.stage] + 1;
      const last = st.counts[st.stage] + films.length >= l.per;
      const after = st.langs.slice(st.stage + 1).find((x, j) => st.counts[st.stage + 1 + j] < x.per && !guide.short[x.name]);
      const label = !last ? "Next 10" : after ? `On to ${after.name}` : "Finish";
      body = `<h2 class="gd-title">${esc(l.name)} · ${from}–${from + films.length - 1}</h2>${films.map(guideRow).join("")}<button class="btn big gd-next" data-act="guide-next">${esc(label)}</button>`;
      if (after && last) {
        const pre = after.seed.filter((id) => !guideAnswered(id) && !guide.cache[id]).slice(0, 10);
        if (pre.length && !guide.loading) queueMicrotask(() => guideLoad(pre));
      }
    }
  }
  const welcome = !readLocal(lk("welcomed"), "") || guide.dropping;
  return `<main class="screen rf-list gd">
    ${guideHead(st)}
    <div class="rf-rows">${body}</div>
  </main>${welcome ? `<div class="gd-wrap ${guide.dropping ? "drop" : ""}"><div class="gd-scrim"></div><div class="gd-sheet" role="dialog" aria-modal="true" aria-labelledby="gd-hi">
    <div class="grip"></div>
    <img class="gd-logo" src="icon-512.png" alt="">
    <h2 id="gd-hi">Hi ${esc(P.nick || P.name)}!</h2>
    <p>${esc(P.welcome || "")}</p>
    <button class="btn big" data-act="guide-ok">Okay</button>
  </div></div>` : ""}`;
}

function guideSave(st) {
  const now = isoNow();
  const lang = st.langs[st.stage].name;
  for (const id of st.next) {
    const f = guide.cache[id];
    if (!f) continue;
    const s = guide.scores[String(id)];
    if (s) store.put(LOG, String(id), { ...logRecord(f, s, ""), source: "guide", guide: lang });
    else store.put(UNSEEN, String(id), { tmdb: f.tmdb, kind: kindOf(f), title: f.title || "", year: f.year ?? null, at: now, updated: now, source: "guide", guide: lang });
  }
  guide.scores = {};
}

function guideFinish() {
  const now = isoNow();
  store.put(GUIDE, "done", { at: now, updated: now });
  guide.ready = true;
  render();
  guideTaste();
}

async function guideNext() {
  const st = guideState();
  if (!st || st.stage < 0) return;
  guideSave(st);
  guide.batch = null;
  window.scrollTo(0, 0);
  const after = guideState();
  if (after && after.stage < 0) return guideFinish();
  render();
}

function guideRated() {
  const langs = guideList() || [];
  const logs = store.all(LOG).filter((d) => d && d.guide);
  return langs.map((l) => ({ name: l.name, ids: logs.filter((d) => d.guide === l.name).map((d) => d.tmdb) }));
}

async function guideTaste() {
  guide.tasteLoading = true;
  guide.tasteError = "";
  render();
  try {
    await store.pushNow();
    const fresh = guideRated().flatMap((l) => l.ids);
    const res = await store.fn("fabula-ai", { action: "taste", who: P.who, fresh });
    guide.taste = (res && res.taste) || {};
  } catch (e) {
    guide.tasteError = e.message || "Can't read your taste yet";
  }
  guide.tasteLoading = false;
  render();
}

function viewGuideReady() {
  const rated = guideRated();
  const total = rated.reduce((a, l) => a + l.ids.length, 0);
  const t = guide.taste || {};
  const more = (Array.isArray(t.more) ? t.more : []).map(label).filter(Boolean);
  const tasteBox = guide.tasteLoading || (!guide.taste && !guide.tasteError)
    ? `<div class="tcard skeleton"><span class="bar w80"></span><span class="bar w60"></span></div>`
    : guide.tasteError
    ? ""
    : `${t.summary ? `<div class="tcard wash"><span class="tsum">${esc(t.summary)}</span></div>` : ""}${more.length ? `<div class="gd-chips">${more.map((m) => `<span class="chip on">${esc(m)}</span>`).join("")}</div>` : ""}`;
  return `<main class="screen gd-ready">
    <img class="gd-logo big" src="icon-512.png" alt="">
    <h1>Got it, ${esc(P.nick || P.name)}!</h1>
    <span class="muted">${total} movies rated</span>
    <div class="gd-counts">${rated.map((l) => `<div><b>${l.ids.length}</b><span>${esc(l.name)}</span></div>`).join("")}</div>
    ${tasteBox}
    <div class="grow"></div>
    <button class="btn big" data-act="guide-go">Start swiping</button>
  </main>`;
}

function guideScore(el) {
  const id = el.dataset.v;
  const v = Number(el.value);
  guide.scores[id] = v;
  el.classList.remove("untouched");
  const lab = el.nextElementSibling;
  if (lab) {
    lab.textContent = `${v} / 10`;
    lab.classList.add("on");
  }
}

function render() {
  const app = $("#app");
  if (!store.signedIn()) {
    app.innerHTML = viewConnect();
    return;
  }
  if (ui.dragging) {
    ui.stale = true;
    return;
  }
  ui.stale = false;
  if (guideGated()) {
    let gh = viewGuide();
    if (ui.toast) gh += `<div class="toast">${esc(ui.toast)}</div>`;
    app.innerHTML = gh;
    return;
  }
  const views = { recommend: viewRecommend, watchlist: viewWatchlist, log: viewLog, match: viewMatch, refiner: viewRefiner, ai: viewAi };
  let html = views[ui.view]();
  if (ui.sheet) {
    const t = ui.sheet.type;
    html += t === "filter" ? filterSheet() : t === "rate" ? rateSheet() : t === "wl-film" ? wlFilmSheet() : t === "add" ? addSheet() : t === "sort" ? sortSheet() : "";
  }
  lastSheet = ui.sheet;
  if (ui.pick) html += pickView(ui.pick !== lastPick);
  lastPick = ui.pick;
  const slide = ui.nav !== lastNav;
  html += `<div class="navwrap ${(slide ? lastNav : ui.nav) ? "open" : ""}">${sidebar()}</div>`;
  lastNav = ui.nav;
  if (ui.toast) html += `<div class="toast">${esc(ui.toast)}</div>`;
  const active = document.activeElement;
  const keep = active && active.dataset && active.dataset.input ? { key: active.dataset.input, v: active.dataset.v, start: active.selectionStart, end: active.selectionEnd } : null;
  app.innerHTML = html;
  if (keep) {
    const el = $(`[data-input="${keep.key}"]${keep.v ? `[data-v="${CSS.escape(keep.v)}"]` : ""}`);
    if (el) {
      el.focus({ preventScroll: true });
      try {
        if (keep.start != null) el.setSelectionRange(keep.start, keep.end);
      } catch (e) {}
    }
  }
  if (slide) {
    const wrap = $(".navwrap");
    wrap.getBoundingClientRect();
    requestAnimationFrame(() => wrap.classList.toggle("open", ui.nav));
  }
  bind();
}

function bind() {
  const top = $(".rec .card.top");
  if (top && top.classList.contains("open")) {
    const hook = top.querySelector(".hook");
    if (hook) {
      hook.style.transition = "none";
      hookFit(top, hook);
      hook.getBoundingClientRect();
      hook.style.transition = "";
    }
  }
  if (top) {
    if (ui.enter && !reduceMotion()) top.classList.add("enter");
    ui.enter = false;
    attach(top, {
      up: true,
      onStart: () => (ui.dragging = true),
      onHold: () => {
        ui.dragging = false;
        superlike(top);
      },
      onRelease: (dir) => {
        ui.dragging = false;
        if (dir) commit(dir, top);
        else if (ui.stale) setTimeout(render, 260);
      },
    });
  }
  if (ui.view === "match") bindSwipe($("#app"), room);
  if (ui.sheet && ui.sheet.type === "add" && !ui.sheet.focused) {
    const q = $('[data-input="add-q"]');
    if (q) {
      ui.sheet.focused = true;
      q.focus();
    }
  }
  if (ui.view === "match" && ui.askName && !room.code) {
    const n = $('[data-input="name"]');
    if (n && document.activeElement !== n) n.focus();
  }
}

function hookFit(card, hook) {
  if (!card.classList.contains("open")) {
    hook.style.maxHeight = "";
    return;
  }
  const face = card.querySelector(".face");
  const title = card.querySelector(".ctitle");
  const info = card.querySelector(".info");
  const room = face.clientHeight - title.offsetHeight - (info.offsetHeight - hook.offsetHeight) - 64;
  hook.style.maxHeight = `${Math.max(64, Math.min(hook.scrollHeight, room))}px`;
}

function toggleHook(hook) {
  const card = hook.closest(".card.top");
  if (!card) return;
  const open = !card.classList.contains("open");
  if (!open) hook.style.maxHeight = `${hook.offsetHeight}px`;
  hook.getBoundingClientRect();
  card.classList.toggle("open", open);
  hook.setAttribute("aria-expanded", String(open));
  ui.hookOpen = open ? Number(card.dataset.card) : null;
  if (open) hookFit(card, hook);
  else hook.style.maxHeight = "";
}

function toast(text) {
  ui.toast = text;
  render();
  clearTimeout(toast.t);
  toast.t = setTimeout(() => {
    ui.toast = "";
    render();
  }, 1600);
}

function openFilter(key) {
  if (key === "kind") {
    ui.sheet = { type: "filter", key, draft: ui.kind };
    return;
  }
  const draft = key === "langs" ? [...ui.langs] : key === "genres" ? [...ui.genres] : key === "lang" ? [...ui.wlLang] : key === "genre" ? [...ui.wlGenre] : ui.wlAdded;
  ui.sheet = { type: "filter", key, draft };
}

function applyFilter() {
  const s = ui.sheet;
  ui.sheet = null;
  if (s.key === "kind") setKind(s.draft);
  else if (s.key === "langs" || s.key === "genres") {
    const before = JSON.stringify([ui.langs, ui.genres]);
    if (s.key === "langs") ui.langs = s.draft;
    else ui.genres = s.draft;
    writeLocal(filterKey("langs", ui.kind), JSON.stringify(ui.langs));
    writeLocal(filterKey("genres", ui.kind), JSON.stringify(ui.genres));
    if (JSON.stringify([ui.langs, ui.genres]) !== before) resetDeck();
  } else if (s.key === "lang") ui.wlLang = s.draft;
  else if (s.key === "genre") ui.wlGenre = s.draft;
  else ui.wlAdded = s.draft;
}

function saveRating() {
  const s = ui.sheet;
  if (!s || !s.rating) return;
  const f = s.film;
  store.put(LOG, String(f.tmdb), logRecord(f, Number(s.rating), s.comment.trim()));
  if (s.mode !== "edit") {
    putSwipe(f, "seen");
    const h = ui.history[ui.history.length - 1];
    if (s.mode === "seen" && h && h.film.tmdb === f.tmdb) h.logged = true;
  }
  ui.sheet = null;
  toast(s.mode === "edit" ? "Saved" : "Saved to Log");
}

function skipRating() {
  const s = ui.sheet;
  ui.sheet = null;
  if (s && (s.mode === "add" || s.mode === "wl")) putSwipe(s.film, "seen");
}

let searchTimer = null;
function searchFilms(q) {
  clearTimeout(searchTimer);
  const s = ui.sheet;
  s.q = q;
  s.error = "";
  if (q.trim().length < (ui.kind === "anime" ? 3 : 2)) {
    s.results = [];
    s.loading = false;
    updateResults();
    return;
  }
  searchTimer = setTimeout(async () => {
    const mine = (s.seq = (s.seq || 0) + 1);
    s.loading = true;
    updateResults();
    try {
      const res = ui.kind === "anime" ? await store.fn("fabula-anime", { action: "search", q: q.trim() }) : await store.fn("fabula-tmdb", { action: "search", q: q.trim(), kind: ui.kind });
      if (mine !== s.seq || ui.sheet !== s) return;
      s.results = (res && res.results) || [];
    } catch (e) {
      if (mine !== s.seq || ui.sheet !== s) return;
      s.error = e.message;
    }
    s.loading = false;
    updateResults();
  }, 300);
}

function updateResults() {
  const el = $("#add-results");
  if (el) el.innerHTML = addResults();
}

async function pickResult(id) {
  const s = ui.sheet;
  if (!s || s.adding) return;
  s.adding = true;
  const r = s.results.find((x) => String(x.tmdb) === String(id));
  try {
    const res = await store.fn(kindOf({ tmdb: id }) === "anime" ? "fabula-anime" : "fabula-tmdb", { action: "add", tmdb: Number(id) });
    const raw = (res && res.movie) || r;
    const film = raw.mal_score != null && raw.mal == null ? { ...raw, mal: raw.mal_score } : raw;
    const old = store.get(LOG, String(film.tmdb));
    ui.sheet = { type: "rate", mode: old ? "edit" : "add", film: old ? { ...film, ...old } : film, rating: old ? old.rating : null, comment: old ? old.comment || "" : "" };
  } catch (e) {
    s.adding = false;
    s.error = e.message;
    updateResults();
    return;
  }
  render();
}

function shareRoom() {
  const link = shareLink();
  if (navigator.share) {
    navigator.share({ title: P.name, url: link }).catch(() => {});
    return;
  }
  copyRoom();
}

function copyRoom() {
  const link = shareLink();
  const done = () => toast("Copied");
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(link).then(done, () => toast(link));
  else toast(link);
}

function watchMatched() {
  const f = room.state && room.state.matched;
  if (!f) return;
  if (!store.get(LOG, String(f.tmdb))) putSwipe(f, "super");
  writeLocal(lk("tonight"), JSON.stringify({ tmdb: f.tmdb, at: isoNow() }));
  room.leave();
  go("watchlist");
}

function refStart() {
  ui.ref = { ...freshRef(ui.ref.langs, ui.ref.genres, ui.ref.kind), step: "list" };
  refLoad();
}

async function refLoad() {
  const r = ui.ref;
  const seq = ++r.seq;
  r.loading = true;
  r.error = "";
  r.films = [];
  r.scores = {};
  render();
  window.scrollTo(0, 0);
  let films = [];
  let error = "";
  try {
    await store.pushNow();
    const rows = await store.rpc("fabula_refine", {
      p_who: P.who,
      p_kind: r.kind,
      p_langs: r.langs.length && r.kind !== "anime" ? r.langs : null,
      p_genres: r.genres.length ? r.genres : null,
      p_limit: 10,
      p_exclude: r.shown,
    });
    const have = new Set(r.shown);
    films = (Array.isArray(rows) ? rows : []).filter((f) => f && f.tmdb && !have.has(f.tmdb)).slice(0, 10);
  } catch (e) {
    error = e.message || `Can't load ${noun(r.kind, 2)}`;
  }
  if (ui.ref !== r || seq !== r.seq) return;
  r.films = films;
  r.shown.push(...films.map((f) => f.tmdb));
  r.error = error;
  r.loading = false;
  render();
}

function refSave(touchedOnly = false) {
  const r = ui.ref;
  const now = isoNow();
  for (const f of r.films) {
    const id = String(f.tmdb);
    const s = r.scores[id];
    if (s) {
      store.put(LOG, id, { ...logRecord(f, s, ""), source: "refiner" });
      r.rated++;
      r.fresh.push(f.tmdb);
    } else if (!touchedOnly) {
      store.put(UNSEEN, id, { tmdb: f.tmdb, kind: kindOf(f), title: f.title || "", year: f.year ?? null, at: now, updated: now });
      r.unseen++;
    }
  }
  r.films = [];
  r.scores = {};
}

function refStop() {
  const r = ui.ref;
  r.seq++;
  r.loading = false;
  refSave();
  r.step = "done";
  if (r.fresh.length) refTaste();
  else render();
  window.scrollTo(0, 0);
}

async function refTaste() {
  const r = ui.ref;
  r.tasteLoading = true;
  r.tasteError = "";
  render();
  let taste = null;
  let error = "";
  try {
    await store.pushNow();
    const res = await store.fn("fabula-ai", { action: "taste", who: P.who, fresh: r.fresh });
    taste = (res && res.taste) || {};
  } catch (e) {
    error = e.message || "Can't update your taste";
  }
  if (ui.ref !== r) return;
  r.taste = taste;
  r.tasteError = error;
  r.tasteLoading = false;
  render();
}

function refScore(el) {
  const r = ui.ref;
  const id = el.dataset.v;
  if (!r.films.some((f) => String(f.tmdb) === id)) return;
  const v = Number(el.value);
  r.scores[id] = v;
  el.classList.remove("untouched");
  const lab = el.nextElementSibling;
  if (lab) {
    lab.textContent = `${v} / 10`;
    lab.classList.add("on");
  }
  const count = $("#ref-count");
  if (count) count.textContent = `${refRated(r)} rated`;
}

function aiFind() {
  const text = ui.ai.draft.trim();
  if (text.length < 2) return;
  ui.ai = { ...freshAi(ui.ai.draft), step: "results", kind: ui.kind, mood: text, thread: [text] };
  aiRound();
}

async function aiRound(entry = "", note = "") {
  const a = ui.ai;
  const seq = ++a.seq;
  const before = a.films;
  if (entry) a.thread.push(entry);
  if (note) a.notes.push(note);
  a.round++;
  a.loading = true;
  a.error = "";
  a.chosen = null;
  a.films = [];
  render();
  window.scrollTo(0, 0);
  let films = null;
  let error = "";
  try {
    const res = await store.fn("fabula-ai", { action: "mood", who: P.who, kind: a.kind, text: a.mood, notes: a.notes, shown: a.shown });
    films = (res && Array.isArray(res.films) ? res.films : []).filter((f) => f && f.tmdb).slice(0, 4);
  } catch (e) {
    error = e.message || `Can't find ${noun(a.kind, 2)}`;
  }
  if (ui.ai !== a || seq !== a.seq) return;
  if (films) {
    a.films = films;
    for (const f of films) if (!a.shown.includes(f.tmdb)) a.shown.push(f.tmdb);
  } else {
    a.films = before;
    a.round--;
    a.error = error;
    if (entry) a.thread.pop();
    if (note) {
      a.notes.pop();
      a.note = note;
    }
  }
  a.loading = false;
  render();
  const err = $(".ai-err");
  if (err) err.scrollIntoView({ block: "nearest" });
}

function aiNote(text) {
  const a = ui.ai;
  const note = String(text || "").trim();
  if (!note || a.loading) return;
  a.note = "";
  aiRound(note, note);
}

function aiWatch() {
  const a = ui.ai;
  const film = a.films.find((f) => Number(f.tmdb) === a.chosen);
  if (!film) return;
  putSwipe(film, "super");
  ui.swiped.add(film.tmdb);
  ui.queue = ui.queue.filter((f) => f.tmdb !== film.tmdb);
  ui.pick = film;
  render();
}

document.addEventListener("click", (e) => {
  if (e.target.dataset && e.target.dataset.input === "ref-score") return refScore(e.target);
  if (e.target.dataset && e.target.dataset.input === "guide-score") return guideScore(e.target);
  const el = e.target.closest("[data-act]");
  if (!el) return;
  if (el.classList.contains("sheet") && e.target.closest("[data-stop]")) return;
  const v = el.dataset.v;
  switch (el.dataset.act) {
    case "guide-ok":
      writeLocal(lk("welcomed"), "1");
      guide.dropping = true;
      render();
      setTimeout(() => {
        guide.dropping = false;
        render();
      }, reduceMotion() ? 0 : 420);
      return;
    case "guide-next":
      return guideNext();
    case "guide-retry":
      guide.error = "";
      guide.loading = false;
      break;
    case "guide-go":
      guide.ready = false;
      resetDeck();
      return go("recommend");
    case "nav":
      ui.nav = true;
      break;
    case "nav-close":
      ui.nav = false;
      break;
    case "go":
      return go(v);
    case "undo":
      return undo();
    case "hook":
      return toggleHook(el);
    case "retry":
      ui.deckError = "";
      return refill();
    case "clear-all":
      ui.langs = [];
      ui.genres = [];
      writeLocal(filterKey("langs", ui.kind), "[]");
      writeLocal(filterKey("genres", ui.kind), "[]");
      resetDeck();
      break;
    case "filter":
    case "wfilter":
      openFilter(v);
      break;
    case "kind":
      setKind(v);
      break;
    case "opt": {
      const s = ui.sheet;
      if (s.key === "kind") s.draft = KINDS.find((k) => KIND_NAMES[k] === v) || s.draft;
      else if (s.key === "added") s.draft = v;
      else s.draft = s.draft.includes(v) ? s.draft.filter((x) => x !== v) : [...s.draft, v];
      break;
    }
    case "opt-clear":
      ui.sheet.draft = ui.sheet.key === "added" ? "Any time" : [];
      break;
    case "opt-done":
      applyFilter();
      break;
    case "close-sheet":
      ui.sheet = null;
      break;
    case "score":
      ui.sheet.rating = Number(v);
      ui.sheet.comment = ($('[data-input="comment"]') || {}).value ?? ui.sheet.comment;
      break;
    case "rate-save":
      ui.sheet.comment = ($('[data-input="comment"]') || {}).value ?? ui.sheet.comment;
      return saveRating();
    case "rate-skip":
      skipRating();
      break;
    case "log-open": {
      const l = store.get(LOG, v);
      if (l) ui.sheet = { type: "rate", mode: "edit", film: l, rating: l.rating, comment: l.comment || "" };
      break;
    }
    case "log-delete":
      store.remove(LOG, String(ui.sheet.film.tmdb));
      ui.sheet = null;
      break;
    case "add-open":
      ui.sheet = { type: "add", q: "", results: [], loading: false, error: "" };
      break;
    case "add-pick":
      return pickResult(v);
    case "sort-open":
      ui.sheet = { type: "sort" };
      break;
    case "sort":
      ui.logSort = v;
      writeLocal(lk("sort"), v);
      ui.sheet = null;
      break;
    case "wl-open": {
      const f = store.get(SWIPE, v);
      if (f) ui.sheet = { type: "wl-film", film: f };
      break;
    }
    case "wl-remove":
      store.remove(SWIPE, String(ui.sheet.film.tmdb));
      if (tonight() === Number(ui.sheet.film.tmdb)) writeLocal(lk("tonight"), null);
      ui.sheet = null;
      break;
    case "wl-seen":
      ui.sheet = { type: "rate", mode: "wl", film: ui.sheet.film, rating: null, comment: "" };
      break;
    case "pick-watch":
      writeLocal(lk("tonight"), JSON.stringify({ tmdb: ui.pick.tmdb, at: isoNow() }));
      ui.pick = null;
      break;
    case "pick-keep":
      ui.pick = null;
      break;
    case "match-share":
      return shareRoom();
    case "match-copy":
      return copyRoom();
    case "match-start":
      return room.start();
    case "match-leave":
      room.leave();
      return go("recommend");
    case "match-new":
      room.leave();
      if (ui.name) createRoom_();
      else ui.askName = true;
      break;
    case "match-watch":
      return watchMatched();
    case "ref-kind": {
      const k = KINDS.find((x) => KIND_NAMES[x] === v);
      if (k && k !== ui.ref.kind) ui.ref = freshRef([], [], k);
      break;
    }
    case "ref-lang":
    case "ref-genre": {
      const key = el.dataset.act === "ref-lang" ? "langs" : "genres";
      const cur = ui.ref[key];
      ui.ref[key] = v === "Any" ? [] : cur.includes(v) ? cur.filter((x) => x !== v) : [...cur, v];
      break;
    }
    case "ref-start":
      return refStart();
    case "ref-retry":
      return refLoad();
    case "ref-more":
      refSave();
      return refLoad();
    case "ref-stop":
      return refStop();
    case "ref-back":
      ui.ref.seq++;
      refSave(true);
      ui.ref = freshRef(ui.ref.langs, ui.ref.genres, ui.ref.kind);
      window.scrollTo(0, 0);
      break;
    case "ref-taste":
      return refTaste();
    case "ref-home":
      ui.ref = freshRef(ui.ref.langs, ui.ref.genres, ui.ref.kind);
      resetDeck();
      return go("recommend");
    case "ref-again":
      ui.ref = freshRef(ui.ref.langs, ui.ref.genres, ui.ref.kind);
      window.scrollTo(0, 0);
      break;
    case "ai-idea":
      ui.ai.draft = v;
      break;
    case "ai-choose": {
      const id = Number(v);
      ui.ai.chosen = ui.ai.chosen === id ? null : id;
      break;
    }
    case "ai-none":
      if (ui.ai.loading) return;
      return aiRound("None of these");
    case "ai-watch":
      return aiWatch();
    case "ai-back":
      ui.ai.seq++;
      ui.ai = freshAi(ui.ai.mood || ui.ai.draft);
      window.scrollTo(0, 0);
      break;
    default:
      return;
  }
  render();
});

document.addEventListener("input", (e) => {
  const t = e.target;
  const kind = t.dataset && t.dataset.input;
  if (kind === "comment" && ui.sheet) ui.sheet.comment = t.value;
  if (kind === "ref-score") refScore(t);
  if (kind === "guide-score") guideScore(t);
  if (kind === "ai-note") ui.ai.note = t.value;
  if (kind === "ai-mood") {
    ui.ai.draft = t.value;
    const b = t.form && t.form.querySelector(".ai-find");
    if (b) b.disabled = t.value.trim().length < 2;
  }
  if (kind === "add-q" && ui.sheet && ui.sheet.type === "add") searchFilms(t.value);
  if (kind === "log-q") {
    ui.logQuery = t.value;
    const rows = $("#log-rows");
    if (rows) rows.innerHTML = logRows();
  }
  if (kind === "name") {
    ui.nameDraft = t.value;
    const b = t.form && t.form.querySelector("button[type=submit]");
    if (b) b.disabled = !t.value.trim() || room.busy;
  }
});

document.addEventListener("focusout", () => {
  setTimeout(() => {
    const a = document.activeElement;
    if (ui.stale && !(a && a.matches && a.matches("input, textarea"))) render();
  }, 0);
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const form = e.target;
  if (form.dataset.form === "mood") return aiFind();
  if (form.dataset.form === "tune") {
    const f = form.querySelector('[data-input="ai-note"]');
    return aiNote(f ? f.value : ui.ai.note);
  }
  if (form.dataset.form === "name") {
    const name = String(new FormData(form).get("name") || "").trim().slice(0, 20);
    if (!name) return;
    ui.name = name;
    writeLocal(lk("name"), name);
    createRoom_();
    return render();
  }
  if (form.dataset.form !== "connect") return;
  const found = parseLink(new FormData(form).get("link") || "");
  if (!found) {
    ui.setupError = "Not a setup link";
    return render();
  }
  ui.setupError = "";
  store.configure(found.url, found.key);
  resetDeck();
});

let spaceTimer = null;
document.addEventListener("keydown", (e) => {
  if (e.target.matches && e.target.matches("input, textarea")) {
    if (e.key === "Escape") e.target.blur();
    return;
  }
  if (e.key === "Escape") {
    if (ui.pick) ui.pick = null;
    else if (ui.sheet) ui.sheet = null;
    else if (ui.nav) ui.nav = false;
    else return;
    return render();
  }
  if ((e.metaKey || e.ctrlKey) && (e.key === "z" || e.key === "Z") && ui.view === "recommend") {
    e.preventDefault();
    return undo();
  }
  if (ui.sheet || ui.pick || ui.nav) return;
  if (ui.view === "match") {
    const go2 = { ArrowRight: "match-yes", ArrowLeft: "match-no" }[e.key];
    const b = go2 && $(`[data-act="${go2}"]`);
    if (b) {
      e.preventDefault();
      b.click();
    }
    return;
  }
  if (ui.view !== "recommend") return;
  const top = $(".rec .card.top");
  if (!top) return;
  const dir = { ArrowRight: "right", ArrowLeft: "left", ArrowUp: "up" }[e.key];
  if (dir) {
    e.preventDefault();
    return commit(dir, top);
  }
  if (e.key === " " && !e.repeat) {
    e.preventDefault();
    clearTimeout(spaceTimer);
    spaceTimer = setTimeout(() => superlike(top), 600);
  }
});

document.addEventListener("keyup", (e) => {
  if (e.key === " ") clearTimeout(spaceTimer);
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

function onStore() {
  const active = document.activeElement;
  if (active && active.matches && active.matches("input, textarea")) {
    ui.stale = true;
    return;
  }
  render();
}

readSetupLink();
store.subscribe(onStore);
if (store.signedIn()) {
  store.syncNow();
  refill();
}
enterView();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
