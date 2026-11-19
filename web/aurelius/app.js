import * as store from "./store.js";
import { THEMES, apply } from "./themes.js";

const PALETTE = ["hsl(145 40% 44%)", "hsl(28 78% 56%)", "hsl(212 62% 56%)", "hsl(275 45% 62%)", "hsl(340 62% 62%)", "hsl(182 48% 40%)", "hsl(45 80% 48%)", "hsl(4 64% 58%)"];
const NONE = "none";
const FROM = 6 * 60;
const SPAN = 16 * 60;
const TICKS = ["6a", "8a", "10a", "12p", "2p", "4p", "6p", "8p", "10p"];

const ui = {
  project: readLocal("aurelius.web.project", "all"),
  period: readLocal("aurelius.web.period", "day"),
  offset: { day: 0, week: 0, month: 0 },
  closed: readLocal("aurelius.web.closed", "0") === "1",
  menu: false,
  settings: false,
  setupError: "",
  toast: "",
};

function readLocal(key, fallback) {
  try {
    const v = localStorage.getItem(key) ?? localStorage.getItem(key.replace("aurelius.", "pomodoro."));
    return v == null ? fallback : v;
  } catch (e) {
    return fallback;
  }
}

function writeLocal(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch (e) {}
}

const $ = (sel) => document.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const r2 = (n) => Math.round(n * 100) / 100;
const units = (m) => {
  const u = Math.round((m / 25) * 10) / 10;
  return Number.isInteger(u) ? String(u) : u.toFixed(1);
};
const dur = (m) => {
  m = Math.round(m);
  const h = Math.floor(m / 60);
  const mm = m % 60;
  return h ? (mm ? `${h}h ${mm}m` : `${h}h`) : `${mm}m`;
};
const sessionsLabel = (m) => `${units(m)} ${units(m) === "1" ? "session" : "sessions"}`;
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const mondayOf = (d) => addDays(startOfDay(d), -((d.getDay() + 6) % 7));
const monthOf = (d) => new Date(d.getFullYear(), d.getMonth(), 1);
const addMonths = (d, n) => new Date(d.getFullYear(), d.getMonth() + n, 1);
const dayKey = (d) => `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
const minutesOf = (list) => list.reduce((a, s) => a + s.minutes, 0);

function theme() {
  const id = readLocal("aurelius.web.theme", "rose");
  return THEMES.some((t) => t.id === id) ? id : "rose";
}

function projects() {
  const list = store
    .all("board.project")
    .sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0))
    .map((p) => ({ id: p.id, name: p.name || "Untitled", short: shortName(p.name || "Untitled"), tint: PALETTE[(p.hue ?? 0) % PALETTE.length] }));
  return list;
}

function shortName(name) {
  return name.replace(/\s+question bank$/i, "").trim() || name;
}

function allSessions(byId) {
  return store.all("board.session").map((s) => {
    const end = store.time.fromBoard(s.ended);
    const minutes = Math.max(1, Math.round(s.minutes || 0));
    const start = s.started != null ? store.time.fromBoard(s.started) : new Date(end.getTime() - minutes * 60000);
    const project = s.project && byId.has(s.project) ? s.project : NONE;
    return { start, end, minutes, project };
  });
}

function unassigned() {
  return { id: NONE, name: "Unassigned", short: "Unassigned", tint: "var(--faint)" };
}

function model() {
  const list = projects();
  const byId = new Map(list.map((p) => [p.id, p]));
  const every = allSessions(byId);
  if (every.some((s) => s.project === NONE)) byId.set(NONE, unassigned());
  if (ui.project !== "all" && !byId.has(ui.project)) ui.project = "all";
  const sessions = ui.project === "all" ? every : every.filter((s) => s.project === ui.project);
  return { list: [...byId.values()], byId, every, sessions };
}

function range(period, offset, now = new Date()) {
  if (period === "day") {
    const start = addDays(startOfDay(now), offset);
    return { start, end: addDays(start, 1) };
  }
  if (period === "week") {
    const start = addDays(mondayOf(now), offset * 7);
    return { start, end: addDays(start, 7) };
  }
  const start = addMonths(monthOf(now), offset);
  return { start, end: addMonths(start, 1) };
}

const within = (list, r) => list.filter((s) => s.start >= r.start && s.start < r.end);

function earliestOffset(sessions, period) {
  if (!sessions.length) return 0;
  const first = sessions.reduce((a, s) => (s.start < a ? s.start : a), sessions[0].start);
  const now = new Date();
  if (period === "day") return Math.min(0, Math.round((startOfDay(first) - startOfDay(now)) / 86400000));
  if (period === "week") return Math.min(0, Math.round((mondayOf(first) - mondayOf(now)) / (7 * 86400000)));
  return Math.min(0, (first.getFullYear() - now.getFullYear()) * 12 + first.getMonth() - now.getMonth());
}

function title(period, r, offset) {
  if (period === "day") {
    const label = r.start.toLocaleDateString([], { weekday: "long", day: "numeric", month: "short" });
    if (offset === 0) return "Today, " + r.start.toLocaleDateString([], { day: "numeric", month: "short" });
    if (offset === -1) return "Yesterday, " + r.start.toLocaleDateString([], { day: "numeric", month: "short" });
    return label;
  }
  if (period === "week") {
    const last = addDays(r.end, -1);
    const mon = (d) => d.toLocaleDateString([], { month: "short" });
    return r.start.getMonth() === last.getMonth() ? `${r.start.getDate()} – ${last.getDate()} ${mon(last)}` : `${r.start.getDate()} ${mon(r.start)} – ${last.getDate()} ${mon(last)}`;
  }
  return r.start.toLocaleDateString([], { month: "long", year: "numeric" });
}

function comparison(m) {
  const now = new Date();
  const s = m.sessions;
  if (ui.period === "day") {
    const today = minutesOf(within(s, range("day", 0)));
    const monday = mondayOf(now);
    const studied = [];
    for (let d = monday; d < startOfDay(now); d = addDays(d, 1)) {
      const mins = minutesOf(within(s, { start: d, end: addDays(d, 1) }));
      if (mins > 0) studied.push(mins);
    }
    const avg = studied.length ? minutesOf(studied.map((minutes) => ({ minutes }))) / studied.length : 0;
    return {
      leftLabel: "Today",
      left: dur(today),
      leftSub: sessionsLabel(today),
      rightLabel: "Daily average",
      right: studied.length ? dur(avg) : "–",
      rightSub: studied.length ? `${sessionsLabel(avg)} · days you studied this week` : "no study days earlier this week",
      value: today,
      avg: studied.length ? avg : null,
      note: studied.length ? (today >= avg ? `Above your average by ${dur(today - avg)}` : `${dur(avg - today)} to reach your average`) : "Your average starts after the first day you study this week",
    };
  }
  const period = ui.period;
  const word = period === "week" ? "week" : "month";
  const current = minutesOf(within(s, range(period, 0)));
  const first = earliestOffset(m.sessions, period);
  const others = [];
  for (let o = first; o < 0; o++) {
    const mins = minutesOf(within(s, range(period, o)));
    if (mins > 0) others.push(mins);
  }
  const avg = others.length ? others.reduce((a, b) => a + b, 0) / others.length : 0;
  return {
    leftLabel: `This ${word}`,
    left: sessionsLabel(current),
    leftSub: dur(current),
    rightLabel: `Other ${word}s, average`,
    right: others.length ? sessionsLabel(avg) : "–",
    rightSub: others.length ? dur(avg) : `no earlier ${word}s yet`,
    value: current,
    avg: others.length ? avg : null,
    note: others.length
      ? current >= avg
        ? `Ahead of your usual ${word} by ${units(current - avg)} sessions`
        : `${units(avg - current)} sessions to reach your usual ${word}`
      : `This is your first tracked ${word}, so there is nothing to compare yet`,
  };
}

function viewCompare(m) {
  const c = comparison(m);
  const scale = Math.max(c.avg != null ? c.avg * 1.25 : 0, c.value, 1);
  const fill = r2((c.value / scale) * 100);
  const mark = c.avg != null ? `<i class="mark" style="left:${r2((c.avg / scale) * 100)}%"></i>` : "";
  return `<section class="card compare" aria-label="${esc(c.leftLabel)} against your average">
    <div class="compare-top">
      <div><span class="label">${esc(c.leftLabel)}</span><b class="big">${esc(c.left)}</b><span class="sub">${esc(c.leftSub)}</span></div>
      <div class="end"><span class="label">${esc(c.rightLabel)}</span><b class="mid">${esc(c.right)}</b><span class="sub">${esc(c.rightSub)}</span></div>
    </div>
    <div class="meter"><i class="fill" style="width:${fill}%"></i>${mark}</div>
    <span class="sub">${esc(c.note)}</span>
  </section>`;
}

function viewProjects(m, inRange) {
  const totals = new Map();
  for (const s of m.every.filter((s) => s.start >= inRange.start && s.start < inRange.end)) totals.set(s.project, (totals.get(s.project) || 0) + s.minutes);
  const rows = m.list.map((p) => ({ p, minutes: totals.get(p.id) || 0 })).sort((a, b) => b.minutes - a.minutes);
  const label = { day: "this day", week: "this week", month: "this month" }[ui.period];
  return `<section class="card list">
    <h3><span>Projects</span><span class="sub">${label}</span></h3>
    ${
      rows.length
        ? rows
            .map(
              ({ p, minutes }) => `<button class="row ${ui.project !== "all" && ui.project !== p.id ? "dim" : ""}" data-pick="${esc(p.id)}">
          <i class="dot" style="background:${p.tint}"></i><span class="grow">${esc(p.name)}</span><b>${units(minutes)}</b><span class="sub num">${dur(minutes)}</span>
        </button>`
            )
            .join("")
        : `<div class="empty">Sessions from Pocket on your Mac show up here.</div>`
    }
  </section>`;
}

function viewBars(m, r) {
  const days = [];
  for (let i = 0; i < 7; i++) {
    const d = addDays(r.start, i);
    const list = within(m.sessions, { start: d, end: addDays(d, 1) });
    days.push({ d, list, minutes: minutesOf(list) });
  }
  const max = Math.max(25, ...days.map((x) => x.minutes));
  const today = dayKey(new Date());
  return `<section class="card bars" aria-label="Focus by day">
    ${days
      .map((x) => {
        const per = new Map();
        for (const s of x.list) per.set(s.project, (per.get(s.project) || 0) + s.minutes);
        const segs = [...per.entries()]
          .map(([id, mins]) => {
            const p = m.byId.get(id);
            return `<i style="height:${r2((mins / max) * 100)}%;background:${p.tint}" title="${esc(p.short)} · ${dur(mins)}"></i>`;
          })
          .join("");
        return `<div class="barcol ${dayKey(x.d) === today ? "today" : ""}"><span class="val">${x.minutes ? units(x.minutes) : ""}</span><div class="track">${segs}</div><span class="lbl">${x.d.toLocaleDateString([], { weekday: "narrow" })}</span></div>`;
      })
      .join("")}
  </section>`;
}

function strip(m, list, small) {
  const ticks = TICKS.map((_, i) => `<i class="tick" style="left:${r2((i / 8) * 100)}%"></i>`).join("");
  const blocks = list
    .map((s) => {
      const start = s.start.getHours() * 60 + s.start.getMinutes();
      const a = Math.max(FROM, start);
      const b = Math.min(FROM + SPAN, start + s.minutes);
      if (b <= a) return "";
      const p = m.byId.get(s.project);
      const at = s.start.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      return `<i class="block" style="left:${r2(((a - FROM) / SPAN) * 100)}%;width:${r2(((b - a) / SPAN) * 100)}%;background:${p.tint}" title="${esc(p.short)} · ${at} · ${s.minutes} min"></i>`;
    })
    .join("");
  return `<div class="strip ${small ? "small" : ""}">${ticks}${blocks}</div>`;
}

function axis(indent) {
  return `<div class="axis ${indent ? "indent" : ""}"><div>${TICKS.map((t, i) => `<span style="left:${r2((i / 8) * 100)}%;transform:translateX(${i === 0 ? 0 : i === 8 ? -100 : -50}%)">${t}</span>`).join("")}</div></div>`;
}

function legend(m, list) {
  const per = new Map();
  for (const s of list) per.set(s.project, (per.get(s.project) || 0) + s.minutes);
  if (!per.size) return "";
  return `<div class="legend">${[...per.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([id, mins]) => {
      const p = m.byId.get(id);
      return `<span><i style="background:${p.tint}"></i>${esc(p.short)} · ${dur(mins)}</span>`;
    })
    .join("")}</div>`;
}

function viewMonthGraph(list, r) {
  const now = new Date();
  const last = r.end > now ? startOfDay(now) : addDays(r.end, -1);
  const totalDays = Math.round((addDays(r.end, -1) - r.start) / 86400000) + 1;
  const per = [];
  for (let d = r.start; d <= last; d = addDays(d, 1)) per.push(minutesOf(within(list, { start: d, end: addDays(d, 1) })));
  const peak = Math.max(60, ...per);
  const top = Math.ceil(peak / 60) * 60;
  const x = (i) => r2((i / Math.max(1, totalDays - 1)) * 300);
  const y = (mins) => r2(140 - (mins / top) * 140);
  const pts = per.map((mins, i) => `${x(i)},${y(mins)}`).join(" ");
  const avg = per.length ? per.reduce((a, b) => a + b, 0) / per.length : 0;
  const marks = [1, 8, 15, 22, totalDays];
  return `<div class="graph-head"><span>Focus per day</span><span>Daily average <b>${dur(avg)}</b></span></div>
    <div class="graph">
      <div class="yaxis"><span>${dur(top)}</span><span>0</span></div>
      <svg viewBox="0 0 300 140" preserveAspectRatio="none" role="img" aria-label="Focus time per day, daily average ${dur(avg)}">
        <line x1="0" y1="140" x2="300" y2="140" class="base"></line>
        <line x1="0" y1="70" x2="300" y2="70" class="grid"></line>
        ${per.length > 1 ? `<polygon points="0,140 ${pts} ${x(per.length - 1)},140" class="area"></polygon>` : ""}
        ${per.length ? `<polyline points="${pts}" class="line"></polyline>` : ""}
        <line x1="0" y1="${y(avg)}" x2="300" y2="${y(avg)}" class="avg"></line>
      </svg>
    </div>
    <div class="xaxis"><div>${marks.map((d, i) => `<span style="left:${x(d - 1) / 3}%;transform:translateX(${i === 0 ? 0 : i === marks.length - 1 ? -100 : -50}%)">${d}</span>`).join("")}</div></div>
    <div class="legend"><span><i class="ln"></i>Each day</span><span><i class="ln dash"></i>Average so far</span></div>`;
}

function viewPeriod(m, r) {
  const offset = ui.offset[ui.period];
  const list = within(m.sessions, r);
  const total = minutesOf(list);
  const first = Math.min(earliestOffset(m.every, ui.period), offset);
  const word = { day: "day", week: "week", month: "month" }[ui.period];
  let body = "";
  if (ui.period === "day") {
    body = strip(m, list) + axis(false) + (legend(m, list) || `<div class="legend"><span>No focus this ${word}</span></div>`);
  } else if (ui.period === "week") {
    const rows = [];
    for (let i = 0; i < 7; i++) {
      const d = addDays(r.start, i);
      rows.push(`<div class="weekrow"><span>${d.toLocaleDateString([], { weekday: "short" })}</span>${strip(m, within(list, { start: d, end: addDays(d, 1) }), true)}</div>`);
    }
    body = rows.join("") + axis(true) + (legend(m, list) || `<div class="legend"><span>No focus this ${word}</span></div>`);
  } else {
    body = viewMonthGraph(list, r);
  }
  return `<section class="card period" data-swipe>
    <div class="period-head">
      <button class="toggle" data-collapse aria-expanded="${!ui.closed}">
        <svg class="chev ${ui.closed ? "" : "open"}" viewBox="0 0 12 12" aria-hidden="true"><path d="M4 2.5L7.5 6 4 9.5"/></svg>
        <span class="grow">${esc(title(ui.period, r, offset))}</span>
        <span class="sum">${total ? `${units(total)} · ${dur(total)}` : "0"}</span>
      </button>
      <button class="arrow" data-step="-1" aria-label="Previous ${word}" ${offset <= first ? "disabled" : ""}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3L5 8l5 5"/></svg></button>
      <button class="arrow" data-step="1" aria-label="Next ${word}" ${offset >= 0 ? "disabled" : ""}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M6 3l5 5-5 5"/></svg></button>
    </div>
    ${ui.closed ? "" : `<div class="period-body">${body}</div>`}
  </section>`;
}

function viewHeader(m) {
  const current = ui.project === "all" ? null : m.byId.get(ui.project);
  const st = store.snapshot();
  const sync = st.problem ? "warn" : store.pendingCount() ? "pending" : "ok";
  const options = [{ id: "all", name: "All projects", tint: "var(--faint)", minutes: minutesOf(m.every) }, ...m.list.map((p) => ({ ...p, minutes: minutesOf(m.every.filter((s) => s.project === p.id)) }))];
  return `<header>
    <button class="picker" data-menu aria-haspopup="listbox" aria-expanded="${ui.menu}">
      ${current ? `<i class="dot big" style="background:${current.tint}"></i>` : ""}
      <span>${esc(current ? current.name : "All projects")}</span>
      <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4 6l4 4 4-4"/></svg>
    </button>
    <button class="gear" data-settings aria-label="Settings"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg><i class="sync ${sync}"></i></button>
    ${
      ui.menu
        ? `<div class="menu" role="listbox" aria-label="Project">${options
            .map((o) => `<button role="option" aria-selected="${ui.project === o.id}" class="${ui.project === o.id ? "on" : ""}" data-pick="${esc(o.id)}"><i class="dot" style="background:${o.tint}"></i><span class="grow">${esc(o.name)}</span><span class="sub">${units(o.minutes)}</span></button>`)
            .join("")}</div>`
        : ""
    }
  </header>`;
}

function viewTabs() {
  return `<div class="segments" role="tablist" aria-label="Period">${[
    ["day", "Daily"],
    ["week", "Weekly"],
    ["month", "Monthly"],
  ]
    .map(([k, l]) => `<button role="tab" aria-selected="${ui.period === k}" class="${ui.period === k ? "on" : ""}" data-period="${k}">${l}</button>`)
    .join("")}</div>`;
}

function viewSettings() {
  const st = store.snapshot();
  const current = theme();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  const swatches = (list) =>
    list.map((t) => `<button class="swatch ${current === t.id ? "on" : ""}" data-theme="${t.id}" style="--sw:${t.dark ? t.accent : t.swatch};--ring:${t.swatchRing};--bg:${t.backdrop}" aria-label="${esc(t.name)}"><i></i><span>${esc(t.name)}</span></button>`).join("");
  return `<div class="sheet-wrap" data-close-settings>
    <section class="sheet" role="dialog" aria-label="Settings">
      <div class="sheet-head"><h2>Settings</h2><button class="gear" data-close-settings aria-label="Close settings"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <div class="card list">
        <h3><span>Theme</span></h3>
        <div class="themes">${swatches(THEMES.filter((t) => !t.dark))}</div>
        <div class="themes">${swatches(THEMES.filter((t) => t.dark))}</div>
      </div>
      <div class="card list">
        <h3><span>Sync</span></h3>
        <div class="row static"><span class="grow">Last synced</span><span class="sub">${last ? esc(last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" })) : "never"}</span></div>
        ${st.problem ? `<div class="row static warn">${esc(st.problem)}</div>` : ""}
        <div class="controls"><button class="ghost" data-sync>Sync now</button><button class="ghost danger" data-signout>Disconnect</button></div>
      </div>
      <p class="sub foot">Sessions come from Pocket on your Mac. This app only shows them.</p>
    </section>
  </div>`;
}

function viewSetup() {
  return `<div class="setup">
    <div class="card setup-card">
      <div class="brand"><img src="icon.svg" alt="" width="40" height="40"><h1>Aurelius</h1></div>
      <p>Your focus sessions from Pocket. Paste your Pocket setup link.</p>
      <form data-form="server">
        <input name="link" placeholder="https://gaone1906.github.io/Pocket/#connect=…" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
        <details class="manual"><summary>Or enter the Supabase values</summary>
          <input name="url" placeholder="Project URL (https://xxxx.supabase.co)" autocomplete="off" autocapitalize="off" aria-label="Project URL">
          <input name="key" placeholder="Anon public key" autocomplete="off" autocapitalize="off" aria-label="Anon public key">
        </details>
        <button class="primary">Continue</button>
      </form>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </div>
  </div>`;
}

function render() {
  const app = $("#app");
  apply(theme());
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  const m = model();
  const r = range(ui.period, ui.offset[ui.period]);
  app.innerHTML = `<main>
    ${viewHeader(m)}
    ${viewTabs()}
    ${viewCompare(m)}
    ${viewProjects(m, r)}
    ${ui.period === "week" ? viewBars(m, r) : ""}
    ${viewPeriod(m, r)}
  </main>
  ${ui.settings ? viewSettings() : ""}
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

function step(n) {
  const m = model();
  const first = earliestOffset(m.every, ui.period);
  const next = Math.min(0, Math.max(Math.min(first, ui.offset[ui.period]), ui.offset[ui.period] + n));
  if (next === ui.offset[ui.period]) return;
  ui.offset[ui.period] = next;
  render();
}

document.addEventListener("click", async (e) => {
  const t = e.target.closest("button, [data-close-settings]");
  if (ui.menu && !(t && (t.dataset.menu !== undefined || t.dataset.pick !== undefined))) {
    ui.menu = false;
    render();
    return;
  }
  if (!t || t.disabled) return;
  const d = t.dataset;
  if (d.closeSettings !== undefined) {
    if (t.matches(".sheet-wrap") && e.target.closest(".sheet")) return;
    ui.settings = false;
    render();
  } else if (d.menu !== undefined) {
    ui.menu = !ui.menu;
    render();
  } else if (d.pick) {
    ui.project = ui.menu || ui.project !== d.pick ? d.pick : "all";
    ui.menu = false;
    writeLocal("aurelius.web.project", ui.project);
    render();
  } else if (d.period) {
    ui.period = d.period;
    writeLocal("aurelius.web.period", d.period);
    render();
  } else if (d.step) {
    step(Number(d.step));
  } else if (d.collapse !== undefined) {
    ui.closed = !ui.closed;
    writeLocal("aurelius.web.closed", ui.closed ? "1" : "0");
    render();
  } else if (d.settings !== undefined) {
    ui.settings = true;
    render();
  } else if (d.theme) {
    writeLocal("aurelius.web.theme", d.theme);
    render();
  } else if (d.sync !== undefined) {
    await store.syncNow();
    toast(store.snapshot().problem || "Synced");
  } else if (d.signout !== undefined) {
    if (confirm("Disconnect this device? You can paste the setup link again any time.")) {
      ui.settings = false;
      store.disconnect();
    }
  }
});

let touch = null;
document.addEventListener(
  "touchstart",
  (e) => {
    const card = e.target.closest("[data-swipe]");
    touch = card && e.touches.length === 1 ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : null;
  },
  { passive: true }
);
document.addEventListener(
  "touchend",
  (e) => {
    if (!touch) return;
    const dx = e.changedTouches[0].clientX - touch.x;
    const dy = e.changedTouches[0].clientY - touch.y;
    touch = null;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) step(dx < 0 ? 1 : -1);
  },
  { passive: true }
);

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && (ui.menu || ui.settings)) {
    ui.menu = false;
    ui.settings = false;
    render();
  }
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const f = new FormData(e.target);
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
  const found = String(text).match(/connect=([^&\s]+)/);
  if (!found) return null;
  try {
    const { url, key } = JSON.parse(atob(decodeURIComponent(found[1])));
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

let lastDay = dayKey(new Date());
setInterval(() => {
  const now = dayKey(new Date());
  if (now !== lastDay) {
    lastDay = now;
    render();
  }
}, 60000);

readSetupLink();
store.subscribe(() => {
  if (!document.activeElement || !document.activeElement.closest("form")) render();
});
render();
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
