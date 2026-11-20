import * as store from "./store.js";
import BUNDLED from "./cards.js";

const LADDER = [1, 3, 7, 14, 30];
const REQUEUE = 5;
const HOLD_MS = 550;
const SWIPE_PX = 90;

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const pad = (n) => String(n).padStart(2, "0");
const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const today = () => dayKey(new Date());
const addDays = (k, n) => {
  const [y, m, d] = k.split("-").map(Number);
  return dayKey(new Date(y, m - 1, d + n));
};
const readLocal = (k, f) => {
  try {
    const v = localStorage.getItem(k);
    return v == null ? f : v;
  } catch (e) {
    return f;
  }
};
const writeLocal = (k, v) => {
  try {
    localStorage.setItem(k, v);
  } catch (e) {}
};

const ICON = {
  menu: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h10"/></svg>',
  close: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  shuffle: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 3h5v5M4 20L21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/></svg>',
  chev: '<svg class="chev" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg>',
  sun: '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/></svg>',
};

const ui = {
  exam: readLocal("sol.exam", "CAT"),
  pick: readLocal("sol.pick", "all"),
  open: -1,
  menu: false,
  sheet: null,
  setupError: "",
  run: null,
};

function cards() {
  const byId = new Map(BUNDLED.map((c) => [c.id, c]));
  for (const c of store.all("sol.card")) if (c && c.id && c.ask) byId.set(c.id, c);
  const list = [...byId.values()];
  const order = new Map(BUNDLED.map((c, i) => [c.id, i]));
  return list.slice().sort((a, b) => (order.get(a.id) ?? 1e6) - (order.get(b.id) ?? 1e6) || String(a.id).localeCompare(String(b.id)));
}

function exams() {
  return [...new Set(cards().map((c) => c.exam))];
}

function examCards() {
  const all = cards();
  const mine = all.filter((c) => c.exam === ui.exam);
  if (mine.length) return mine;
  ui.exam = all[0]?.exam || "CAT";
  return all.filter((c) => c.exam === ui.exam);
}

function mark(id) {
  return store.get("sol.mark", id) || null;
}

function setMark(id, patch) {
  const prev = mark(id) || {};
  store.put("sol.mark", id, { ...prev, ...patch, id, updated: new Date().toISOString() });
}

function sections() {
  const out = [];
  for (const c of examCards()) {
    let s = out.find((x) => x.name === c.section);
    if (!s) out.push((s = { name: c.section, topics: [] }));
    let t = s.topics.find((x) => x.name === c.topic);
    if (!t) s.topics.push((t = { name: c.topic, cards: [] }));
    t.cards.push(c);
  }
  return out;
}

const live = (c) => !mark(c.id)?.mastered;
const shaky = (c) => {
  const m = mark(c.id);
  return m && !m.mastered && m.box === 0;
};

function pool(pick) {
  const list = examCards();
  if (pick === "all") return list.filter(live);
  if (pick === "shaky") return list.filter(shaky);
  if (pick.startsWith("sec:")) return list.filter((c) => c.section === pick.slice(4) && live(c));
  if (pick.startsWith("top:")) {
    const [sec, top] = pick.slice(4).split("|");
    return list.filter((c) => c.section === sec && c.topic === top && live(c));
  }
  return list.filter(live);
}

function title(pick) {
  if (pick === "all") return "Shuffle all";
  if (pick === "shaky") return "Not yet";
  if (pick.startsWith("sec:")) return pick.slice(4);
  if (pick.startsWith("top:")) return pick.slice(4).split("|")[1];
  return "Shuffle all";
}

function shuffle(list) {
  const a = list.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function startRun(pick) {
  ui.pick = pick;
  writeLocal("sol.pick", pick);
  const now = today();
  const list = pool(pick);
  const due = list.filter((c) => {
    const m = mark(c.id);
    return !m || !m.due || m.due <= now;
  });
  const later = list.filter((c) => !due.includes(c));
  ui.run = { deck: [...shuffle(due), ...shuffle(later)].map((c) => ({ id: c.id, retry: false })), i: 0, flipped: false, tagged: false, conf: 0, not: new Set(), mastered: 0 };
}

function current() {
  const r = ui.run;
  if (!r || r.i >= r.deck.length) return null;
  const slot = r.deck[r.i];
  const c = cards().find((x) => x.id === slot.id);
  return c ? { ...c, retry: slot.retry } : null;
}

function decide(confident) {
  const r = ui.run;
  const c = current();
  if (!c) return;
  const now = today();
  if (r.tagged) {
    setMark(c.id, { mastered: true, box: 5, due: null });
    r.mastered++;
    r.not.delete(c.id);
    r.deck = r.deck.filter((s, k) => k <= r.i || s.id !== c.id);
  } else if (confident) {
    if (!c.retry) {
      const m = mark(c.id) || { box: 0 };
      const box = Math.min(5, (m.box || 0) + 1);
      setMark(c.id, { box, due: addDays(now, LADDER[box - 1]), mastered: false });
      r.conf++;
    }
  } else {
    setMark(c.id, { box: 0, due: addDays(now, 1), mastered: false });
    r.not.add(c.id);
    if (!c.retry) r.deck.splice(Math.min(r.deck.length, r.i + 1 + REQUEUE), 0, { id: c.id, retry: true });
  }
  r.i++;
  r.flipped = false;
  r.tagged = false;
  render();
}

function cardHtml(c) {
  const r = ui.run;
  const guide = r.i === 0 && !r.tagged && readLocal("sol.guided", "") !== "1";
  const size = c.answer.length > 60 ? "sm" : c.answer.length > 32 ? "md" : "lg";
  const face = r.flipped
    ? `<span class="back"><span class="ask-small">${esc(c.ask)}</span><span class="formula ${size}">${esc(c.answer)}</span>${c.example ? `<span class="example">${esc(c.example)}</span>` : ""}</span>`
    : `<span class="front"><span class="situation">${esc(c.situation)}</span><span class="ask">${esc(c.ask)}</span></span>`;
  const hint = r.tagged ? "Swipe away to hide it for good" : r.flipped ? "" : "Tap to flip";
  return `<div class="stage">
    <div class="under u2"></div><div class="under u1"></div>
    <div class="card${r.flipped ? " flipped" : ""}${r.tagged ? " tagged" : ""}" id="card">
      <button type="button" class="face" id="face" aria-label="${esc(r.flipped ? c.ask + " " + c.answer : c.situation + " " + c.ask + ". Enter flips, left arrow confident, right arrow not yet, M mastered")}">
        <span class="topic"${r.tagged ? ' style="visibility:hidden"' : ""}>${esc(c.section)} · ${esc(c.topic)}${c.retry ? " · again" : ""}</span>
        ${face}
        <span class="hint">${hint}</span>
      </button>
      <div class="stamp yes" id="stamp-yes">Confident</div>
      <div class="stamp no" id="stamp-no">Not yet</div>
      ${r.tagged ? `<div class="tag"><span class="pill">${ICON.sun}Mastered</span><button type="button" class="undo" data-act="undo">Undo</button></div>` : ""}
    </div>
  </div>
  ${guide ? `<div class="guide"><span>← confident</span><span>hold · mastered</span><span>not yet →</span></div>` : ""}`;
}

function doneHtml() {
  const r = ui.run;
  const bits = [`${r.conf} confident`];
  if (r.not.size) bits.push(`${r.not.size} not yet`);
  if (r.mastered) bits.push(`${r.mastered} mastered`);
  const empty = r.deck.length === 0;
  return `<div class="done">
    <img src="icon-512.png" alt="" class="done-logo">
    <h2>${empty ? "Nothing here" : "Done"}</h2>
    <p>${empty ? (ui.pick === "shaky" ? "No cards are marked not yet." : "Every card here is mastered.") : bits.join(" · ")}</p>
    <div class="done-actions">
      ${r.not.size ? `<button type="button" class="primary" data-act="again">Go again on the ${r.not.size} not yet</button>` : ""}
      <button type="button" class="${r.not.size ? "quiet" : "primary"}" data-act="all">Shuffle all formulas</button>
    </div>
  </div>`;
}

function menuHtml() {
  const secs = sections();
  const allCount = examCards().filter(live).length;
  const shakyCount = examCards().filter(shaky).length;
  const masteredCount = examCards().filter((c) => !live(c)).length;
  const examList = exams();
  const s = store.snapshot();
  const sync = !store.signedIn() ? `<button type="button" class="link" data-act="setup">Sync across devices</button>` : `<span class="sync-line">${s.problem ? esc(s.problem) : "Synced with Pocket"}</span>`;
  return `<div class="scrim-wrap"><nav class="menu" aria-label="Choose what to revise">
    <div class="menu-head">
      <img src="icon-192.png" alt="" class="menu-logo"><span class="menu-name">Sol</span>
      ${examList.length > 1 ? `<select class="exam" data-act="exam" aria-label="Exam">${examList.map((e) => `<option${e === ui.exam ? " selected" : ""}>${esc(e)}</option>`).join("")}</select>` : `<span class="exam">${esc(ui.exam)}</span>`}
      <button type="button" class="icon" data-act="close" aria-label="Close">${ICON.close}</button>
    </div>
    <button type="button" class="big${ui.pick === "all" ? " on" : ""}" data-pick="all">${ICON.shuffle}<span><span>Shuffle all formulas</span><small>${allCount} cards, every section</small></span></button>
    ${shakyCount ? `<button type="button" class="row-card${ui.pick === "shaky" ? " on" : ""}" data-pick="shaky"><span>Not yet</span><b>${shakyCount}</b></button>` : ""}
    <div class="by">
      <span class="label">By topic</span>
      ${secs
        .map((sec, k) => {
          const open = ui.open === k;
          const n = sec.topics.reduce((a, t) => a + t.cards.filter(live).length, 0);
          return `<div class="sec">
          <button type="button" class="sec-head${open ? " open" : ""}" data-sec="${k}" aria-expanded="${open}"><span>${esc(sec.name)}</span><span class="n">${n}${ICON.chev}</span></button>
          ${open ? `<div class="topics">${[{ pick: "sec:" + sec.name, name: "All of " + sec.name, n }, ...sec.topics.map((t) => ({ pick: "top:" + sec.name + "|" + t.name, name: t.name, n: t.cards.filter(live).length }))].map((t) => `<button type="button" class="topic-row${ui.pick === t.pick ? " on" : ""}" data-pick="${esc(t.pick)}"><span>${esc(t.name)}</span><span class="n">${t.n}</span></button>`).join("")}</div>` : ""}
        </div>`;
        })
        .join("")}
    </div>
    <div class="menu-foot">
      <button type="button" class="link" data-act="mastered">Mastered · ${masteredCount} hidden</button>
      ${sync}
    </div>
  </nav><button type="button" class="scrim" data-act="close" aria-label="Close the menu"></button></div>`;
}

function sheetHtml() {
  if (ui.sheet === "mastered") {
    const list = examCards().filter((c) => !live(c));
    return `<div class="sheet-wrap"><div class="sheet" role="dialog" aria-label="Mastered cards">
      <div class="sheet-head"><h2>Mastered</h2><button type="button" class="icon" data-act="sheet-close" aria-label="Close">${ICON.close}</button></div>
      ${list.length ? `<p class="sheet-sub">These never come up. Bring one back if you want it again.</p><ul class="mlist">${list.map((c) => `<li><span><b>${esc(c.ask)}</b><small>${esc(c.topic)}</small></span><button type="button" data-restore="${esc(c.id)}">Bring back</button></li>`).join("")}</ul>` : `<p class="sheet-sub">Nothing mastered yet. Hold a card to mark it.</p>`}
    </div><button type="button" class="scrim" data-act="sheet-close" aria-label="Close"></button></div>`;
  }
  if (ui.sheet === "setup") {
    return `<div class="sheet-wrap"><div class="sheet" role="dialog" aria-label="Sync">
      <div class="sheet-head"><h2>Sync</h2><button type="button" class="icon" data-act="sheet-close" aria-label="Close">${ICON.close}</button></div>
      <p class="sheet-sub">Paste your Pocket setup link to keep progress the same on every device.</p>
      <form data-form="setup"><input name="link" placeholder="Setup link" autocomplete="off" aria-label="Setup link">${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}<button type="submit" class="primary">Connect</button></form>
    </div><button type="button" class="scrim" data-act="sheet-close" aria-label="Close"></button></div>`;
  }
  return "";
}

function render() {
  if (!ui.run) startRun(ui.pick);
  const r = ui.run;
  const c = current();
  const total = r.deck.length;
  const pct = total ? Math.round((Math.min(r.i, total) / total) * 100) : 100;
  document.getElementById("app").innerHTML = `<div class="shell">
    <header class="top">
      <button type="button" class="menu-btn" data-act="menu" aria-label="Open the menu">${ICON.menu}<span>${esc(title(ui.pick))}</span></button>
      <span class="counter">${c ? `${r.i + 1} / ${total}` : ""}</span>
    </header>
    <div class="bar"><i style="width:${pct}%"></i></div>
    <main class="main">${c ? cardHtml(c) : doneHtml()}</main>
    ${ui.menu ? menuHtml() : ""}
    ${sheetHtml()}
  </div>`;
  wireCard();
}

let drag = null;
let holdTimer = null;

function setStamps(dx) {
  const yes = document.getElementById("stamp-yes");
  const no = document.getElementById("stamp-no");
  if (!yes || !no) return;
  const t = ui.run.tagged;
  yes.style.opacity = t || dx >= 0 ? 0 : Math.min(1, -dx / SWIPE_PX);
  no.style.opacity = t || dx <= 0 ? 0 : Math.min(1, dx / SWIPE_PX);
}

function fly(confident) {
  const el = document.getElementById("card");
  if (!el) return decide(confident);
  el.style.transition = "transform .26s ease, opacity .26s ease";
  el.style.transform = `translateX(${confident ? -150 : 150}%) rotate(${confident ? -16 : 16}deg)`;
  el.style.opacity = "0";
  writeLocal("sol.guided", "1");
  setTimeout(() => decide(confident), 240);
}

function shake() {
  const el = document.getElementById("card");
  if (!el) return;
  el.classList.remove("shake");
  void el.offsetWidth;
  el.classList.add("shake");
  if (navigator.vibrate) navigator.vibrate(30);
}

function wireCard() {
  const el = document.getElementById("card");
  const face = document.getElementById("face");
  if (!el || !face) return;
  el.addEventListener("pointerdown", (e) => {
    if (e.target.closest(".undo")) return;
    drag = { x: e.clientX, y: e.clientY, dx: 0, moved: false, longed: false, id: e.pointerId };
    el.setPointerCapture(e.pointerId);
    el.style.transition = "none";
    clearTimeout(holdTimer);
    holdTimer = setTimeout(() => {
      if (drag && !drag.moved) {
        drag.longed = true;
        ui.run.tagged = true;
        render();
        shake();
        const again = document.getElementById("card");
        if (again && drag) again.setPointerCapture?.(drag.id);
      }
    }, HOLD_MS);
  });
  el.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x;
    if (!drag.moved && Math.abs(dx) < 8 && Math.abs(e.clientY - drag.y) < 8) return;
    drag.moved = true;
    clearTimeout(holdTimer);
    drag.dx = dx;
    const live = document.getElementById("card");
    live.style.transition = "none";
    live.style.transform = `translateX(${dx}px) rotate(${dx / 12}deg)`;
    setStamps(dx);
  });
  const end = () => {
    clearTimeout(holdTimer);
    if (!drag) return;
    const d = drag;
    drag = null;
    const live = document.getElementById("card");
    if (d.dx < -SWIPE_PX) return fly(true);
    if (d.dx > SWIPE_PX) return fly(false);
    if (live) {
      live.style.transition = "transform .2s ease";
      live.style.transform = "";
    }
    setStamps(0);
    if (!d.moved && !d.longed && !ui.run.tagged) {
      ui.run.flipped = !ui.run.flipped;
      render();
    }
  };
  el.addEventListener("pointerup", end);
  el.addEventListener("pointercancel", () => {
    clearTimeout(holdTimer);
    drag = null;
    const live = document.getElementById("card");
    if (live) live.style.transform = "";
    setStamps(0);
  });
  el.addEventListener("contextmenu", (e) => e.preventDefault());
  face.addEventListener("click", (e) => {
    if (e.detail === 0) {
      ui.run.flipped = !ui.run.flipped;
      render();
      document.getElementById("face")?.focus();
    }
  });
  face.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft") fly(true);
    else if (e.key === "ArrowRight") fly(false);
    else if (e.key === "m" || e.key === "M") {
      ui.run.tagged = !ui.run.tagged;
      render();
      if (ui.run.tagged) shake();
      document.getElementById("face")?.focus();
    }
  });
}

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

document.addEventListener("click", (e) => {
  const t = e.target.closest("[data-act], [data-pick], [data-sec], [data-restore]");
  if (!t) return;
  if (t.dataset.pick) {
    ui.menu = false;
    startRun(t.dataset.pick);
    return render();
  }
  if (t.dataset.sec) {
    const k = Number(t.dataset.sec);
    ui.open = ui.open === k ? -1 : k;
    return render();
  }
  if (t.dataset.restore) {
    setMark(t.dataset.restore, { mastered: false, box: 0, due: today() });
    return render();
  }
  const act = t.dataset.act;
  if (act === "menu") ui.menu = true;
  else if (act === "close") ui.menu = false;
  else if (act === "undo") {
    ui.run.tagged = false;
  } else if (act === "again") {
    const ids = [...ui.run.not];
    ui.run = { deck: shuffle(ids).map((id) => ({ id, retry: false })), i: 0, flipped: false, tagged: false, conf: 0, not: new Set(), mastered: 0 };
  } else if (act === "all") {
    startRun("all");
  } else if (act === "mastered") {
    ui.menu = false;
    ui.sheet = "mastered";
  } else if (act === "setup") {
    ui.menu = false;
    ui.sheet = "setup";
  } else if (act === "sheet-close") ui.sheet = null;
  else return;
  render();
});

document.addEventListener("change", (e) => {
  if (e.target.matches("[data-act=exam]")) {
    ui.exam = e.target.value;
    writeLocal("sol.exam", ui.exam);
    ui.open = -1;
    startRun("all");
    render();
  }
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
  const found = parseLink(f.get("link") || "");
  if (!found) {
    ui.setupError = "Paste the whole setup link.";
    return render();
  }
  ui.setupError = "";
  ui.sheet = null;
  store.configure(found.url, found.key);
  render();
});

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && (ui.menu || ui.sheet)) {
    ui.menu = false;
    ui.sheet = null;
    render();
  }
});

function readSetupLink() {
  const found = parseLink(location.hash);
  if (!found) return;
  store.configure(found.url, found.key);
  history.replaceState(null, "", location.pathname + location.search);
}

let lastCards = "";
store.subscribe(() => {
  if (drag) return;
  const sig = store.all("sol.card").length + ":" + examCards().length;
  if (sig !== lastCards && ui.run && ui.run.i === 0 && !ui.run.flipped) {
    lastCards = sig;
    startRun(ui.pick);
  }
  if (ui.menu || ui.sheet || !current()) render();
});

readSetupLink();
lastCards = store.all("sol.card").length + ":" + examCards().length;
render();
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
