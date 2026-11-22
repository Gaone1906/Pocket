import { esc, ICONS } from "./util.js";
import { posterStyle } from "./films.js";
import { askAI } from "./fabulaai.js";

const LANGS = ["English", "Hindi", "Telugu", "Tamil", "Malayalam", "Korean", "Japanese", "Spanish"];
const GENRES = ["Action", "Animation", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Thriller", "War"];

function fresh(keep) {
  return {
    step: "pick",
    langs: keep ? keep.langs : [],
    genres: keep ? keep.genres : [],
    films: [],
    batch: new Map(),
    rated: new Map(),
    unseen: new Set(),
    shown: new Set(),
    loading: false,
    taking: false,
    result: null,
    tally: { rated: 0, unseen: 0 },
  };
}

function toggle(list, name) {
  return list.includes(name) ? list.filter((x) => x !== name) : [...list, name];
}

export function createRefiner(ctx) {
  let s = fresh();

  const ratedCount = () => new Set([...s.rated.keys(), ...s.batch.keys()]).size;

  function finishBatch() {
    for (const f of s.films) {
      if (s.batch.has(f.tmdb)) {
        const rating = s.batch.get(f.tmdb);
        ctx.saveLog(f, rating);
        s.rated.set(f.tmdb, rating);
      } else if (!s.rated.has(f.tmdb)) {
        s.unseen.add(f.tmdb);
      }
    }
  }

  async function loadBatch() {
    s.loading = true;
    ctx.render();
    try {
      const res = await askAI({ action: "refine", langs: s.langs, genres: s.genres, exclude: [...s.shown] });
      const films = ((res && res.films) || []).filter((f) => f && f.tmdb && !s.shown.has(f.tmdb));
      if (!films.length) throw new Error("No more films match. Try other choices.");
      films.forEach((f) => s.shown.add(f.tmdb));
      s.films = films;
      s.batch = new Map();
      s.step = "list";
      window.scrollTo(0, 0);
    } catch (e) {
      ctx.toast(e.message || "Couldn't load films");
    } finally {
      s.loading = false;
      ctx.render();
    }
  }

  async function stop() {
    finishBatch();
    s.taking = true;
    ctx.render();
    try {
      const rated = [...s.rated].map(([tmdb, rating]) => ({ tmdb, rating }));
      const res = await askAI({ action: "taste", rated, unseen: [...s.unseen] });
      s.result = {
        summary: (res && res.summary) || "",
        changes: Array.isArray(res && res.changes) ? res.changes : [],
      };
      s.tally = { rated: s.rated.size, unseen: s.unseen.size };
      s.step = "done";
      window.scrollTo(0, 0);
    } catch (e) {
      ctx.toast(e.message || "Couldn't update your taste");
    } finally {
      s.taking = false;
      ctx.render();
    }
  }

  function chipGroup(label, names, chosen, act) {
    const any = chosen.length === 0;
    const chip = (n, on, v) =>
      `<button class="chip ${on ? "on" : ""}" data-act="${act}" data-v="${esc(v)}" aria-pressed="${on}">${esc(n)}</button>`;
    return `<div class="rf-group" role="group" aria-label="${label}"><span class="section">${label}</span><div class="chips">${chip("Any", any, "Any")}${names
      .map((n) => chip(n, chosen.includes(n), n))
      .join("")}</div></div>`;
  }

  function pickView() {
    return `<main class="screen rf">
      <header class="head sub"><button class="round" data-act="go" data-v="recommend" aria-label="Back to Recommend">${ICONS.back}</button><h1>Refiner</h1></header>
      <h2 class="rf-ask">What would you like to refine?</h2>
      ${chipGroup("Language", LANGS, s.langs, "rf-lang")}
      ${chipGroup("Genre", GENRES, s.genres, "rf-genre")}
      <button class="btn big rf-start" data-act="rf-start" ${s.loading ? "disabled" : ""}>${s.loading ? "Finding films…" : "Start refining"}</button>
    </main>`;
  }

  function label(rating) {
    return rating == null ? "Not seen" : `${rating} / 10`;
  }

  function row(f) {
    const rating = s.batch.get(f.tmdb);
    const touched = rating != null;
    const sub = [f.year, f.director].filter(Boolean).join(" · ");
    return `<article class="rf-row" data-rf="${esc(f.tmdb)}">
      <div class="rf-poster" style="${posterStyle(f, "w185")}"></div>
      <div class="rf-body">
        <h3 class="rf-name">${esc(f.title)}</h3>
        ${sub ? `<span class="rf-sub">${esc(sub)}</span>` : ""}
        ${f.overview ? `<p class="rf-blurb">${esc(f.overview)}</p>` : ""}
        <div class="rf-rate">
          <input type="range" min="1" max="10" step="1" value="${touched ? rating : 5}" class="fabula-range ${touched ? "" : "untouched"}" data-input="rf-rate" data-v="${esc(f.tmdb)}" aria-label="Rate ${esc(f.title)}" aria-valuetext="${label(rating)}">
          <span class="rf-val ${touched ? "on" : ""}">${label(rating)}</span>
        </div>
      </div>
    </article>`;
  }

  function listView() {
    const langs = s.langs.length ? s.langs.join(", ") : "Any language";
    const genres = s.genres.length ? s.genres.join(", ") : "Any genre";
    const busy = s.loading || s.taking;
    return `<main class="screen rf rf-list">
      <header class="rf-bar">
        <button class="round" data-act="rf-back" aria-label="Change what to refine">${ICONS.back}</button>
        <div class="rf-titles"><h1>Refiner</h1><span class="rf-filter">${esc(langs)} · ${esc(genres)}</span></div>
        <span class="rf-count" id="rf-count" aria-live="polite">${ratedCount()} rated</span>
      </header>
      <div class="rf-rows">
        ${s.films.map(row).join("")}
        <div class="rf-foot">
          <button class="btn ghost" data-act="rf-stop" ${busy ? "disabled" : ""}>${s.taking ? "Updating…" : "Stop"}</button>
          <button class="btn wide" data-act="rf-more" ${busy ? "disabled" : ""}>${s.loading ? "Finding films…" : "Continue: 10 more"}</button>
        </div>
      </div>
    </main>`;
  }

  function doneView() {
    const r = s.result;
    const changes = r.changes
      .map(
        (c) =>
          `<li class="rf-change"><span>${esc(c.label)}</span><span class="${c.dir === "down" ? "down" : "up"}">${c.dir === "down" ? "↓" : "↑"} ${esc(c.strength)}</span></li>`
      )
      .join("");
    return `<main class="screen rf rf-done">
      <div class="rf-hero"><span class="rf-check">${ICONS.check}</span><h1>Taste updated</h1>
        <p>${s.tally.rated} ${s.tally.rated === 1 ? "film" : "films"} rated, ${s.tally.unseen} not seen. Recommend uses this from your next card.</p></div>
      ${changes ? `<section class="rf-card"><span class="section">What changed</span><ul class="rf-changes">${changes}</ul></section>` : ""}
      ${r.summary ? `<section class="rf-card wash"><span class="section">Your taste, in a line</span><p class="rf-summary">${esc(r.summary)}</p></section>` : ""}
      <div class="rf-grow"></div>
      <button class="btn big rf-start" data-act="rf-recommend">Back to Recommend</button>
      <button class="link rf-else" data-act="rf-else">Refine something else</button>
    </main>`;
  }

  function view() {
    if (s.step === "list") return listView();
    if (s.step === "done" && s.result) return doneView();
    return pickView();
  }

  function act(name, v) {
    switch (name) {
      case "rf-lang":
        s.langs = v === "Any" ? [] : toggle(s.langs, v);
        break;
      case "rf-genre":
        s.genres = v === "Any" ? [] : toggle(s.genres, v);
        break;
      case "rf-start":
        if (!s.loading) loadBatch();
        return true;
      case "rf-more":
        if (s.loading || s.taking) return true;
        finishBatch();
        loadBatch();
        return true;
      case "rf-stop":
        if (s.loading || s.taking) return true;
        stop();
        return true;
      case "rf-back":
        finishBatch();
        s.films = [];
        s.batch = new Map();
        s.step = "pick";
        break;
      case "rf-recommend":
        ctx.resetDeck();
        ctx.go("recommend");
        s = fresh(s);
        return true;
      case "rf-else":
        s = fresh(s);
        break;
      default:
        return false;
    }
    ctx.render();
    return true;
  }

  function setRating(id, value, input) {
    const n = Number(value);
    if (!Number.isFinite(n) || n < 1 || n > 10) return;
    s.batch.set(Number(id), n);
    input.classList.remove("untouched");
    input.setAttribute("aria-valuetext", label(n));
    const val = input.parentElement.querySelector(".rf-val");
    if (val) {
      val.textContent = label(n);
      val.classList.add("on");
    }
    const count = document.getElementById("rf-count");
    if (count) count.textContent = `${ratedCount()} rated`;
  }

  function input(el) {
    if (el.dataset.input !== "rf-rate") return false;
    setRating(el.dataset.v, el.value, el);
    return true;
  }

  function tap(el) {
    if (!el.matches || !el.matches('input[data-input="rf-rate"].untouched')) return false;
    setRating(el.dataset.v, el.value, el);
    return true;
  }

  return { view, act, input, tap };
}
