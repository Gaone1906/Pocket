import { esc, ICONS } from "./util.js";
import { posterStyle, runtime } from "./films.js";
import { askAI } from "./fabulaai.js";

const IDEAS = ["Cosy and clever", "Edge of my seat", "Make me cry", "Something weird"];

function fresh() {
  return { step: "mood", mood: "", notes: [], films: [], shown: new Set(), chosen: null, round: 0, loading: false, draft: "" };
}

export function createAI(ctx) {
  let a = fresh();

  async function run(note, restart) {
    if (a.loading) return;
    if (restart) {
      a.notes = [];
      a.shown = new Set();
      a.films = [];
      a.round = 0;
      a.chosen = null;
    }
    const text = a.mood.trim();
    if (!text) return;
    const notes = note ? [...a.notes, note] : a.notes;
    a.step = "results";
    a.loading = true;
    ctx.render();
    try {
      const res = await askAI({ action: "mood", text, notes, exclude: [...a.shown] });
      const films = ((res && res.films) || []).filter((f) => f && f.tmdb);
      if (!films.length) throw new Error("No films found. Try different words.");
      films.forEach((f) => a.shown.add(f.tmdb));
      a.notes = notes;
      a.films = films;
      a.chosen = null;
      a.round += 1;
      if (note) a.draft = "";
      window.scrollTo(0, 0);
    } catch (e) {
      if (!a.films.length) a.step = "mood";
      ctx.toast(e.message || "Couldn't find films");
    } finally {
      a.loading = false;
      ctx.render();
    }
  }

  function moodView() {
    return `<main class="screen ai ai-mood">
      <header class="head sub"><button class="round" data-act="go" data-v="recommend" aria-label="Back to Recommend">${ICONS.back}</button><h1>AI Mode</h1></header>
      <div class="ai-grow"></div>
      <div class="ai-hero"><span class="ai-badge">${ICONS.sparkle}</span><h2>What are you in the mood for?</h2><p>Say it however you like. I'll pick from films you haven't seen.</p></div>
      <div class="ai-ideas">${IDEAS.map((t) => `<button class="idea" data-act="ai-idea" data-v="${esc(t)}">${esc(t)}</button>`).join("")}</div>
      <div class="ai-grow"></div>
      <div class="ai-box">
        <label for="ai-mood" class="section">Your mood</label>
        <textarea id="ai-mood" rows="4" data-input="ai-mood" placeholder="Rainy Sunday, want something cosy but not dumb, under 2 hours">${esc(a.mood)}</textarea>
        <button class="btn ai-go" data-act="ai-find" ${a.mood.trim() ? "" : "disabled"}>Find films${ICONS.arrow}</button>
      </div>
    </main>`;
  }

  function card(f) {
    const on = a.chosen === f.tmdb;
    const meta = [f.year, runtime(f.runtime), f.director].filter(Boolean).join(" · ");
    const line = f.why || f.overview || "";
    return `<article class="ai-card ${on ? "on" : ""}">
      <div class="ai-poster" style="${posterStyle(f, "w185")}"></div>
      <div class="ai-body">
        <h3 class="rf-name">${esc(f.title)}</h3>
        ${meta ? `<span class="rf-sub">${esc(meta)}</span>` : ""}
        ${line ? `<p class="ai-why">${esc(line)}</p>` : ""}
        <button class="ai-choose ${on ? "on" : ""}" data-act="ai-choose" data-v="${esc(f.tmdb)}" aria-pressed="${on}">${on ? "Chosen" : "This one"}</button>
      </div>
    </article>`;
  }

  function resultsView() {
    const thread = [a.mood.trim(), ...a.notes].slice(-2);
    const chosen = a.films.find((f) => f.tmdb === a.chosen);
    const body = a.loading
      ? `<div class="ai-wait" role="status"><div class="spin"></div><span class="muted">Thinking…</span></div>`
      : a.films.map(card).join("");
    return `<main class="screen ai ai-res">
      <header class="ai-top">
        <div class="ai-row"><button class="round" data-act="ai-edit" aria-label="Change mood">${ICONS.back}</button><h1>AI Mode</h1><span class="faint ai-round">Round ${Math.max(a.round, 1)}</span></div>
        <div class="ai-thread">${thread.map((t) => `<span class="bubble">${esc(t)}</span>`).join("")}</div>
      </header>
      <div class="ai-list" aria-busy="${a.loading}">${body}</div>
      <div class="ai-foot">
        ${chosen && !a.loading ? `<button class="btn gold ai-watch" data-act="ai-watch">Watch ${esc(chosen.title)} tonight</button>` : ""}
        <form class="ai-tune" data-form="ai-note">
          <label for="ai-tune" class="sr">Fine-tune these picks</label>
          <input id="ai-tune" class="field" type="text" data-input="ai-draft" placeholder="Less animation, more like Knives Out" value="${esc(a.draft)}" autocomplete="off" maxlength="200">
          <button class="ai-send" type="submit" aria-label="Send fine-tune note" ${a.draft.trim() && !a.loading ? "" : "disabled"}>${ICONS.arrow}</button>
        </form>
        <button class="btn ghost ai-retry" data-act="ai-retry" ${a.loading ? "disabled" : ""}>None of these, try again</button>
      </div>
    </main>`;
  }

  function view() {
    return a.step === "results" ? resultsView() : moodView();
  }

  function act(name, v) {
    switch (name) {
      case "ai-idea":
        a.mood = v;
        break;
      case "ai-find":
        run(null, true);
        return true;
      case "ai-edit":
        a.step = "mood";
        break;
      case "ai-choose":
        a.chosen = a.chosen === Number(v) ? null : Number(v);
        break;
      case "ai-retry":
        run(null, false);
        return true;
      case "ai-watch": {
        const film = a.films.find((f) => f.tmdb === a.chosen);
        if (!film) return true;
        ctx.superlike(film);
        a = fresh();
        return true;
      }
      default:
        return false;
    }
    ctx.render();
    return true;
  }

  function input(el) {
    const kind = el.dataset.input;
    if (kind === "ai-mood") {
      a.mood = el.value;
      const b = document.querySelector('[data-act="ai-find"]');
      if (b) b.disabled = !a.mood.trim();
      return true;
    }
    if (kind === "ai-draft") {
      a.draft = el.value;
      const b = el.form && el.form.querySelector(".ai-send");
      if (b) b.disabled = !a.draft.trim() || a.loading;
      return true;
    }
    return false;
  }

  function submit(form) {
    if (form.dataset.form !== "ai-note") return false;
    const note = a.draft.trim();
    if (note) run(note, false);
    return true;
  }

  return { view, act, input, submit };
}
