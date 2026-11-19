import * as store from "./store.js";
import { THEMES, apply, theme } from "./themes.js";

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const pad = (n) => String(n).padStart(2, "0");
const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const parseDay = (k) => {
  const [y, m, d] = k.split("-").map(Number);
  return new Date(y, m - 1, d);
};
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes());
const units = (minutes) => Math.round((minutes / 25) * 10) / 10;
const fmtUnits = (u) => (Number.isInteger(u) ? String(u) : u.toFixed(1));
const fmtTime = (d) => d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
const WEEK = [2, 3, 4, 5, 6, 7, 1];
const SHORT = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const ICONS = {
  focus: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2.5M9.5 2.5h5"/></svg>',
  todo: '<svg viewBox="0 0 24 24"><path d="M4 6.5l1.8 1.8L9 5M4 13.5l1.8 1.8L9 12M12 7h8M12 14h8M12 19.5h8M4.5 19.5h3"/></svg>',
  schedule: '<svg viewBox="0 0 24 24"><path d="M12 3a9 9 0 1 0 9 9"/><path d="M12 7v5l3 2"/><path d="M17 3.5l1 2.5 2.5 1-2.5 1-1 2.5-1-2.5-2.5-1 2.5-1z"/></svg>',
  calendar: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
  settings: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
  plus: '<svg viewBox="0 0 24 24"><path d="M12 5v14M5 12h14"/></svg>',
  check: '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
  close: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  left: '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>',
  right: '<svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7"/></svg>',
  sun: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/></svg>',
  moon: '<svg viewBox="0 0 24 24"><path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/></svg>',
  trash: '<svg viewBox="0 0 24 24"><path d="M5 7h14M10 7V4.5h4V7M7 7l1 13h8l1-13"/></svg>',
};

const ui = {
  tab: localStorage.getItem("pocket.tab") || "focus",
  setupEmail: "",
  setupStep: "server",
  setupError: "",
  busy: false,
  slot: null,
  scheduleDay: null,
  calMonth: null,
  calDay: dayKey(new Date()),
  editing: null,
  showDone: true,
  toast: "",
};

function prefs() {
  return { theme: "sage", focusMinutes: 25, breakMinutes: 5, longMinutes: 15, longEvery: 4, ...(store.get("settings.prefs", "prefs") || {}) };
}

function savePrefs(patch) {
  store.put("settings.prefs", "prefs", { ...prefs(), ...patch });
}

function timer() {
  return store.get("pomodoro.timer", "current") || { phase: "idle", running: false, cycle: 0 };
}

function projects() {
  return store.all("board.project").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
}

function sessions() {
  return store.all("board.session").sort((a, b) => b.ended - a.ended);
}

async function advanceTimer() {
  let t = timer();
  if (!t.running || !t.endsAt || Date.now() < t.endsAt) return;
  const p = prefs();
  let guard = 0;
  while (t.running && Date.now() >= t.endsAt && guard++ < 6) {
    if (t.phase === "focus") {
      const id = await store.stableUuid(`${t.runId}:${t.cycle}`);
      if (!store.get("board.session", id)) {
        const s = { id, ended: store.time.toBoard(new Date(t.endsAt)), minutes: t.focusMinutes, project: t.project || null };
        if (!s.project) delete s.project;
        store.put("board.session", id, s);
        notify("Focus done", `${t.focusMinutes} minutes logged${t.project ? " to " + projectName(t.project) : ""}. Time for a break.`);
      }
      const long = t.cycle % (p.longEvery || 4) === 0;
      t = { ...t, phase: long ? "long" : "rest", endsAt: t.endsAt + (long ? t.longMinutes : t.breakMinutes) * 60000 };
    } else {
      const startsLate = Date.now() - t.endsAt > 90000;
      if (startsLate) {
        t = { ...t, phase: "idle", running: false, endsAt: null, remaining: null };
        break;
      }
      notify("Break over", "Next focus is starting.");
      t = { ...t, phase: "focus", cycle: t.cycle + 1, endsAt: t.endsAt + t.focusMinutes * 60000 };
    }
  }
  store.put("pomodoro.timer", "current", { ...t, device: store.snapshot().device });
}

function projectName(id) {
  const p = store.get("board.project", id);
  return p && p.name ? p.name : "Untitled";
}

function timerAction(action) {
  const t = timer();
  const p = prefs();
  const device = store.snapshot().device;
  if (action === "start") {
    if (t.phase === "idle") {
      const project = ui.project ?? t.project ?? null;
      store.put("pomodoro.timer", "current", {
        runId: store.uuid(),
        phase: "focus",
        running: true,
        cycle: (t.cycle || 0) + 1,
        endsAt: Date.now() + p.focusMinutes * 60000,
        focusMinutes: p.focusMinutes,
        breakMinutes: p.breakMinutes,
        longMinutes: p.longMinutes,
        project,
        device,
      });
    } else if (!t.running) {
      store.put("pomodoro.timer", "current", { ...t, running: true, endsAt: Date.now() + (t.remaining || 0) * 1000, remaining: null, device });
    }
  } else if (action === "pause" && t.running) {
    store.put("pomodoro.timer", "current", { ...t, running: false, remaining: Math.max(0, Math.round((t.endsAt - Date.now()) / 1000)), endsAt: null, device });
  } else if (action === "stop") {
    store.put("pomodoro.timer", "current", { phase: "idle", running: false, cycle: t.cycle || 0, project: t.project ?? null, device });
  }
}

function remaining(t) {
  if (t.phase === "idle") return prefs().focusMinutes * 60;
  if (t.running) return Math.max(0, Math.round((t.endsAt - Date.now()) / 1000));
  return t.remaining || 0;
}

function phaseLength(t) {
  if (t.phase === "focus") return t.focusMinutes * 60;
  if (t.phase === "rest") return t.breakMinutes * 60;
  if (t.phase === "long") return t.longMinutes * 60;
  return prefs().focusMinutes * 60;
}

function tintFor(project) {
  return project ? `var(--tint-${(project.hue ?? 0) % 8})` : "var(--faint)";
}

function viewFocus() {
  const t = timer();
  const left = remaining(t);
  const total = phaseLength(t) || 1;
  const frac = t.phase === "idle" ? 0 : 1 - left / total;
  const r = 104;
  const c = 2 * Math.PI * r;
  const label = { idle: "Ready", focus: "Focus", rest: "Break", long: "Long break" }[t.phase];
  const projs = projects();
  const selected = t.phase === "idle" ? ui.project ?? t.project ?? null : t.project ?? null;
  const all = sessions();
  const today = dayKey(new Date());
  const todayMin = all.filter((s) => dayKey(store.time.fromBoard(s.ended)) === today).reduce((a, s) => a + s.minutes, 0);
  const weekStart = addDays(new Date(), -((new Date().getDay() + 6) % 7));
  const weekMin = all.filter((s) => store.time.fromBoard(s.ended) >= new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate())).reduce((a, s) => a + s.minutes, 0);
  const allMin = all.reduce((a, s) => a + s.minutes, 0);
  const byProject = new Map();
  for (const s of all) byProject.set(s.project || "", (byProject.get(s.project || "") || 0) + s.minutes);
  const rows = projs
    .map((p) => ({ p, minutes: byProject.get(p.id) || 0 }))
    .concat(byProject.get("") ? [{ p: null, minutes: byProject.get("") }] : [])
    .sort((a, b) => b.minutes - a.minutes);
  const p = prefs();
  const where = t.device && t.phase !== "idle" ? `<div class="where">Running from ${esc(t.device)}</div>` : "";
  return `
  <section class="focus">
    <div class="timer-card card">
      <div class="ring ${t.phase}">
        <svg viewBox="0 0 240 240">
          <circle cx="120" cy="120" r="${r}" class="track"/>
          <circle cx="120" cy="120" r="${r}" class="fill" style="stroke-dasharray:${c};stroke-dashoffset:${c * (1 - frac)}"/>
        </svg>
        <div class="ring-text">
          <div class="phase">${label}${t.phase !== "idle" && !t.running ? " · paused" : ""}</div>
          <div class="clock" data-clock>${pad(Math.floor(left / 60))}:${pad(left % 60)}</div>
          <div class="cycle">${t.phase === "idle" ? `${p.focusMinutes} / ${p.breakMinutes} min` : `Session ${t.cycle}`}</div>
        </div>
      </div>
      ${where}
      <div class="chips">
        <button class="chip ${selected == null ? "on" : ""}" data-project="">Unassigned</button>
        ${projs
          .map((pr) => `<button class="chip ${selected === pr.id ? "on" : ""}" data-project="${pr.id}"><i style="background:${tintFor(pr)}"></i>${esc(pr.name || "Untitled")}</button>`)
          .join("")}
      </div>
      <div class="controls">
        ${t.phase === "idle" ? `<button class="primary" data-timer="start">Start focus</button>` : t.running ? `<button class="primary" data-timer="pause">Pause</button>` : `<button class="primary" data-timer="start">Resume</button>`}
        ${t.phase !== "idle" ? `<button class="ghost" data-timer="stop">Stop</button>` : ""}
      </div>
    </div>
    <div class="side-col">
    <div class="stats">
      <div class="stat card"><b>${fmtUnits(units(todayMin))}</b><span>today</span><em>${todayMin} min</em></div>
      <div class="stat card"><b>${fmtUnits(units(weekMin))}</b><span>this week</span><em>${weekMin} min</em></div>
      <div class="stat card"><b>${fmtUnits(units(allMin))}</b><span>all time</span><em>${Math.round(allMin / 60)} h</em></div>
    </div>
    <div class="card list">
      <h3>Projects</h3>
      ${
        rows.length
          ? rows
              .map(
                ({ p, minutes }) => `<div class="row"><i class="dot" style="background:${tintFor(p)}"></i><span class="grow">${esc(p ? p.name || "Untitled" : "Unassigned")}</span><span class="num">${fmtUnits(units(minutes))}</span><span class="sub">${minutes} min</span></div>`
              )
              .join("")
          : `<div class="empty">Finished sessions show up here.</div>`
      }
    </div>
    <div class="card list">
      <h3>Recent sessions</h3>
      ${
        all.length
          ? all
              .slice(0, 8)
              .map((s) => {
                const d = store.time.fromBoard(s.ended);
                const pr = s.project ? store.get("board.project", s.project) : null;
                return `<div class="row"><i class="dot" style="background:${tintFor(pr)}"></i><span class="grow">${esc(pr ? pr.name || "Untitled" : "Unassigned")}${s.declared ? ' <small>declared</small>' : ""}</span><span class="sub">${d.toLocaleDateString([], { month: "short", day: "numeric" })} · ${fmtTime(d)}</span><span class="num">${s.minutes}m</span></div>`;
              })
              .join("")
          : `<div class="empty">No sessions yet.</div>`
      }
    </div>
    </div>
  </section>`;
}

function todos() {
  return store.all("todo").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
}

function viewTodo() {
  const list = todos();
  const open = list.filter((t) => !t.done);
  const done = list.filter((t) => t.done);
  const item = (t) => `
    <div class="row todo ${t.done ? "done" : ""}">
      <button class="tick ${t.done ? "on" : ""}" data-todo-toggle="${t.id}" aria-label="Toggle">${t.done ? ICONS.check : ""}</button>
      <span class="grow" data-todo-edit="${t.id}">${esc(t.title)}</span>
      <button class="icon quiet" data-todo-remove="${t.id}" aria-label="Delete">${ICONS.trash}</button>
    </div>`;
  return `
  <section class="todo-view">
    <form class="card add" data-form="todo">
      <input name="title" placeholder="Add a to-do" autocomplete="off" enterkeyhint="done">
      <button class="icon accent" aria-label="Add">${ICONS.plus}</button>
    </form>
    <div class="card list">
      <h3>To do <span class="count">${open.length}</span></h3>
      ${open.length ? open.map(item).join("") : `<div class="empty">Nothing left. Nice.</div>`}
    </div>
    ${
      done.length
        ? `<div class="card list">
      <h3><button class="link" data-toggle-done>${ui.showDone ? "Hide" : "Show"} done</button> <span class="count">${done.length}</span><button class="link right" data-clear-done>Clear</button></h3>
      ${ui.showDone ? done.map(item).join("") : ""}
    </div>`
        : ""
    }
  </section>`;
}

function scheduleBook() {
  const settings = store.get("schedule.settings", "book") || {};
  return {
    nightFrom: settings.nightFrom ?? 16,
    dayFrom: settings.dayFrom ?? 4,
    routines: store.all("schedule.routine").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0)),
    checks: new Set(store.all("schedule.check").map((c) => c.id)),
  };
}

function scheduleToday(book) {
  const shifted = new Date(Date.now() - book.dayFrom * 3600000);
  return dayKey(shifted);
}

function scheduleSlotNow(book) {
  const h = new Date().getHours();
  return h >= book.nightFrom || h < book.dayFrom ? "night" : "morning";
}

function scheduleItems(book, day, slot) {
  const weekday = parseDay(day).getDay() + 1;
  return book.routines
    .filter((r) => r.starts <= day)
    .flatMap((r) =>
      (r.plan?.[`${weekday}-${slot}`] || []).map((step) => {
        const id = `${r.id}|${day}|${slot}|${step.id}`;
        return { id, routine: r, step, slot, day, done: book.checks.has(id) };
      })
    );
}

function dayStatus(book, day, today) {
  const items = ["morning", "night"].flatMap((s) => scheduleItems(book, day, s));
  if (!book.routines.some((r) => r.starts <= day)) return "before";
  if (!items.length) return "rest";
  const done = items.filter((i) => i.done).length;
  if (done === items.length) return "done";
  if (day >= today) return day === today ? "open" : "upcoming";
  return done ? "partial" : "missed";
}

function viewSchedule() {
  const book = scheduleBook();
  const today = scheduleToday(book);
  const day = ui.scheduleDay || today;
  const slot = ui.slot || scheduleSlotNow(book);
  const d = parseDay(day);
  const monday = addDays(d, -((d.getDay() + 6) % 7));
  const strip = WEEK.map((_, i) => {
    const k = dayKey(addDays(monday, i));
    const st = dayStatus(book, k, today);
    return `<button class="day ${k === day ? "on" : ""} ${k === today ? "today" : ""}" data-sched-day="${k}"><span>${SHORT[WEEK[i]]}</span><b>${parseDay(k).getDate()}</b><i class="st ${st}"></i></button>`;
  }).join("");
  const items = scheduleItems(book, day, slot);
  const groups = new Map();
  for (const it of items) {
    if (!groups.has(it.routine.id)) groups.set(it.routine.id, { routine: it.routine, items: [] });
    groups.get(it.routine.id).items.push(it);
  }
  const done = items.filter((i) => i.done).length;
  const title = day === today ? "Today" : d.toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" });
  return `
  <section class="schedule">
    <div class="card week">
      <div class="week-head">
        <button class="icon quiet" data-sched-week="-7">${ICONS.left}</button>
        <h3>${title}</h3>
        <button class="icon quiet" data-sched-week="7">${ICONS.right}</button>
      </div>
      <div class="strip">${strip}</div>
    </div>
    <div class="seg">
      <button class="${slot === "morning" ? "on" : ""}" data-slot="morning">${ICONS.sun}Morning</button>
      <button class="${slot === "night" ? "on" : ""}" data-slot="night">${ICONS.moon}Night</button>
    </div>
    ${
      items.length
        ? [...groups.values()]
            .map(
              ({ routine, items }) => `
      <div class="card list">
        <h3><i class="dot" style="background:var(--tint-${(routine.hue ?? 0) % 8})"></i>${esc(routine.name)}<span class="count">${items.filter((i) => i.done).length}/${items.length}</span></h3>
        ${items
          .map(
            (it) => `
          <div class="row step ${it.done ? "done" : ""}">
            <button class="tick ${it.done ? "on" : ""}" data-check="${esc(it.id)}">${it.done ? ICONS.check : ""}</button>
            <div class="grow"><div>${esc(it.step.title)}</div>${it.step.tip ? `<div class="tip">${esc(it.step.tip)}</div>` : ""}</div>
          </div>`
          )
          .join("")}
      </div>`
            )
            .join("") + `<div class="foot">${done} of ${items.length} done</div>`
        : `<div class="card empty big">${book.routines.length ? `Nothing planned for this ${slot}.` : "No routines yet. Make them in Pocket on your Mac and they appear here."}</div>`
    }
  </section>`;
}

function events() {
  return store.all("calendar.event");
}

function occursOn(ev, day) {
  const start = new Date(ev.start);
  const end = new Date(ev.end || ev.start);
  const startDay = dayKey(start);
  if (day < startDay) return false;
  if (ev.until && day > dayKey(new Date(ev.until))) return false;
  const rule = ev.repeats || "never";
  if (rule === "never") {
    const lastDay = ev.allDay ? dayKey(new Date(end.getTime() - 1)) : dayKey(end);
    return day <= lastDay;
  }
  const d = parseDay(day);
  if (rule === "daily") return true;
  if (rule === "weekdays") return d.getDay() >= 1 && d.getDay() <= 5;
  if (rule === "weekly") return d.getDay() === start.getDay();
  if (rule === "monthly") return d.getDate() === start.getDate();
  if (rule === "yearly") return d.getDate() === start.getDate() && d.getMonth() === start.getMonth();
  return false;
}

function eventsOn(day) {
  return events()
    .filter((e) => occursOn(e, day))
    .sort((a, b) => (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0) || new Date(a.start).getHours() * 60 + new Date(a.start).getMinutes() - (new Date(b.start).getHours() * 60 + new Date(b.start).getMinutes()));
}

function viewCalendar() {
  const sel = parseDay(ui.calDay);
  const month = ui.calMonth ? parseDay(ui.calMonth) : new Date(sel.getFullYear(), sel.getMonth(), 1);
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const gridStart = addDays(first, -((first.getDay() + 6) % 7));
  const today = dayKey(new Date());
  const cells = [];
  for (let i = 0; i < 42; i++) {
    const d = addDays(gridStart, i);
    const k = dayKey(d);
    const evs = eventsOn(k);
    cells.push(`<button class="cell ${d.getMonth() !== month.getMonth() ? "out" : ""} ${k === today ? "today" : ""} ${k === ui.calDay ? "on" : ""}" data-cal-day="${k}">
      <b>${d.getDate()}</b><span class="dots">${evs
        .slice(0, 3)
        .map((e) => `<i style="background:var(--tint-${(e.hue ?? 0) % 8})"></i>`)
        .join("")}</span></button>`);
    if (i === 34 && addDays(gridStart, 35).getMonth() !== month.getMonth()) break;
  }
  const agenda = eventsOn(ui.calDay);
  return `
  <section class="calendar">
    <div class="card month">
      <div class="week-head">
        <button class="icon quiet" data-cal-month="-1">${ICONS.left}</button>
        <h3>${month.toLocaleDateString([], { month: "long", year: "numeric" })}</h3>
        <button class="icon quiet" data-cal-month="1">${ICONS.right}</button>
      </div>
      <div class="dow">${WEEK.map((w) => `<span>${SHORT[w].slice(0, 2)}</span>`).join("")}</div>
      <div class="grid">${cells.join("")}</div>
    </div>
    <div class="card list">
      <h3>${sel.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}<button class="icon accent right" data-event-new aria-label="Add event">${ICONS.plus}</button></h3>
      ${
        agenda.length
          ? agenda
              .map((e) => {
                const s = new Date(e.start);
                const en = new Date(e.end || e.start);
                const when = e.allDay ? "All day" : `${fmtTime(s)} – ${fmtTime(en)}`;
                return `<button class="row event" data-event="${e.id}"><i class="bar" style="background:var(--tint-${(e.hue ?? 0) % 8})"></i><div class="grow"><div>${esc(e.title || "Untitled")}</div><div class="tip">${when}${e.location ? " · " + esc(e.location) : ""}${e.repeats && e.repeats !== "never" ? " · repeats " + e.repeats : ""}</div></div>${e.alert != null ? '<span class="bell" title="Alert">●</span>' : ""}</button>`;
              })
              .join("")
          : `<div class="empty">No events. Tap + to add one.</div>`
      }
    </div>
  </section>
  ${ui.editing ? viewEventSheet() : ""}`;
}

function toLocalInput(d) {
  return `${dayKey(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function viewEventSheet() {
  const e = ui.editing;
  const s = new Date(e.start);
  const en = new Date(e.end);
  const alerts = e.allDay
    ? [[null, "None"], [0, "9 AM on the day"], [1440, "9 AM the day before"]]
    : [[null, "None"], [0, "At start"], [5, "5 min before"], [10, "10 min before"], [30, "30 min before"], [60, "1 hour before"], [1440, "1 day before"]];
  return `
  <div class="sheet-back" data-sheet-close></div>
  <form class="sheet card" data-form="event">
    <div class="sheet-head"><h3>${e.isNew ? "New event" : "Edit event"}</h3><button type="button" class="icon quiet" data-sheet-close>${ICONS.close}</button></div>
    <input name="title" placeholder="Title" value="${esc(e.title)}" required>
    <input name="location" placeholder="Location" value="${esc(e.location || "")}">
    <label class="toggle"><input type="checkbox" name="allDay" ${e.allDay ? "checked" : ""} data-allday> All day</label>
    ${
      e.allDay
        ? `<div class="two dates"><label>From<input type="date" name="startDay" value="${dayKey(s)}"></label><label>To<input type="date" name="endDay" value="${dayKey(new Date(en.getTime() - 1))}"></label></div>`
        : `<div class="two dates"><label>Starts<input type="datetime-local" name="start" value="${toLocalInput(s)}"></label><label>Ends<input type="datetime-local" name="end" value="${toLocalInput(en)}"></label></div>`
    }
    <div class="two">
      <label>Alert<select name="alert">${alerts.map(([v, l]) => `<option value="${v ?? ""}" ${(e.alert ?? null) === v ? "selected" : ""}>${l}</option>`).join("")}</select></label>
      <label>Repeats<select name="repeats">${["never", "daily", "weekdays", "weekly", "monthly", "yearly"].map((r) => `<option ${(e.repeats || "never") === r ? "selected" : ""}>${r}</option>`).join("")}</select></label>
    </div>
    <div class="hues">${[0, 1, 2, 3, 4, 5, 6, 7].map((h) => `<label><input type="radio" name="hue" value="${h}" ${(e.hue ?? 0) === h ? "checked" : ""}><i style="background:var(--tint-${h})"></i></label>`).join("")}</div>
    <textarea name="notes" placeholder="Notes" rows="3">${esc(e.notes || "")}</textarea>
    <div class="controls">
      <button class="primary">Save</button>
      ${e.isNew ? "" : `<button type="button" class="ghost danger" data-event-delete>Delete</button>`}
    </div>
  </form>`;
}

function viewSettings() {
  const st = store.snapshot();
  const p = prefs();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  const perm = "Notification" in window ? Notification.permission : "unsupported";
  return `
  <section class="settings">
    <div class="card list">
      <h3>Theme</h3>
      <div class="themes">
        ${THEMES.map((t) => `<button class="swatch ${p.theme === t.id ? "on" : ""}" data-theme="${t.id}" style="--sw:${t.dark ? t.accent : t.swatch};--ring:${t.swatchRing};--bg:${t.backdrop}"><i></i><span>${t.name}</span></button>`).join("")}
      </div>
    </div>
    <div class="card list">
      <h3>Focus</h3>
      ${[
        ["focusMinutes", "Focus", 1, 240],
        ["breakMinutes", "Break", 1, 90],
        ["longMinutes", "Long break", 1, 120],
        ["longEvery", "Long break every", 2, 12],
      ]
        .map(
          ([k, l, min, max]) => `<div class="row"><span class="grow">${l}</span><div class="stepper"><button data-step="${k}" data-by="-1" data-min="${min}" data-max="${max}">−</button><b>${p[k]}${k === "longEvery" ? "" : " min"}</b><button data-step="${k}" data-by="1" data-min="${min}" data-max="${max}">+</button></div></div>`
        )
        .join("")}
    </div>
    <div class="card list">
      <h3>Sync</h3>
      <div class="row"><span class="grow">Account</span><span class="sub">${esc(st.session?.user?.email || "—")}</span></div>
      <div class="row"><span class="grow">This device</span><input class="inline" data-device value="${esc(st.device)}"></div>
      <div class="row"><span class="grow">Last synced</span><span class="sub">${last ? last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" }) : "never"}</span></div>
      <div class="row"><span class="grow">Waiting to upload</span><span class="sub">${store.pendingCount()}</span></div>
      ${st.problem ? `<div class="row warn">${esc(st.problem)}</div>` : ""}
      <div class="controls left"><button class="ghost" data-sync>Sync now</button><button class="ghost" data-export>Download a copy</button><button class="ghost danger" data-signout>Sign out</button></div>
    </div>
    <div class="card list">
      <h3>Notifications</h3>
      <div class="row"><span class="grow">Calendar alerts and focus/break changes</span><span class="sub">${perm === "granted" ? "On" : perm === "denied" ? "Blocked in browser settings" : perm === "unsupported" ? "Add to Home Screen first" : "Off"}</span></div>
      ${perm === "default" ? `<div class="controls left"><button class="ghost" data-notify-ask>Turn on</button></div>` : ""}
    </div>
  </section>`;
}

function viewSetup() {
  const st = store.snapshot();
  const step = !st.config ? "server" : ui.setupStep === "code" ? "code" : "email";
  return `
  <div class="setup">
    <div class="card setup-card">
      <div class="brand"><span class="logo"></span><h1>Pocket</h1></div>
      ${
        step === "server"
          ? `<p>Connect this device to your Pocket database. Use the link from Pocket's setup guide, or paste the two values from Supabase → Project Settings → API.</p>
        <form data-form="server">
          <input name="url" placeholder="Project URL (https://xxxx.supabase.co)" required autocomplete="off">
          <input name="key" placeholder="Anon public key" required autocomplete="off">
          <button class="primary wide">Continue</button>
        </form>`
          : step === "email"
          ? `<p>Sign in with your email. We'll send a 6-digit code.</p>
        <form data-form="email">
          <input name="email" type="email" placeholder="you@example.com" value="${esc(ui.setupEmail)}" required autocomplete="email">
          <button class="primary wide" ${ui.busy ? "disabled" : ""}>${ui.busy ? "Sending…" : "Send code"}</button>
        </form>
        <button class="link" data-reset-server>Use a different database</button>`
          : `<p>Enter the code sent to <b>${esc(ui.setupEmail)}</b>.</p>
        <form data-form="code">
          <input name="code" inputmode="numeric" autocomplete="one-time-code" placeholder="123456" required maxlength="10">
          <button class="primary wide" ${ui.busy ? "disabled" : ""}>${ui.busy ? "Checking…" : "Sign in"}</button>
        </form>
        <button class="link" data-back-email>Use a different email</button>`
      }
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </div>
  </div>`;
}

const TABS = [
  ["focus", "Focus"],
  ["todo", "To-do"],
  ["schedule", "Schedule"],
  ["calendar", "Calendar"],
  ["settings", "Settings"],
];

function render() {
  const app = $("#app");
  const st = store.snapshot();
  apply(prefs().theme);
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  const active = document.activeElement;
  const keep = active && active.name && active.closest("form") ? { form: active.closest("form").dataset.form, name: active.name, value: active.value, pos: active.selectionStart } : null;
  const views = { focus: viewFocus, todo: viewTodo, schedule: viewSchedule, calendar: viewCalendar, settings: viewSettings };
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
  if (keep) {
    const el = $(`form[data-form="${keep.form}"] [name="${keep.name}"]`);
    if (el && el.type !== "checkbox" && el.type !== "radio") {
      el.value = keep.value;
      el.focus();
      try {
        el.setSelectionRange(keep.pos, keep.pos);
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

async function notify(title, body, tag) {
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg) reg.showNotification(title, { body, tag, icon: "icon-192.png", badge: "icon-192.png" });
    else new Notification(title, { body, tag });
  } catch (e) {}
}

function alertTimes(ev, day) {
  if (ev.alert == null) return null;
  const start = new Date(ev.start);
  if (ev.allDay) {
    const d = parseDay(day);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() - (ev.alert >= 1440 ? 1 : 0), 9, 0);
  }
  const d = parseDay(day);
  const occ = new Date(d.getFullYear(), d.getMonth(), d.getDate(), start.getHours(), start.getMinutes());
  return new Date(occ.getTime() - ev.alert * 60000);
}

function checkAlerts() {
  let fired = {};
  try {
    fired = JSON.parse(localStorage.getItem("pocket.fired") || "{}");
  } catch (e) {}
  const now = Date.now();
  const days = [dayKey(new Date()), dayKey(addDays(new Date(), 1))];
  for (const ev of events()) {
    for (const day of days) {
      if (!occursOn(ev, day)) continue;
      const at = alertTimes(ev, day);
      if (!at) continue;
      const key = `${ev.id}|${day}`;
      if (fired[key]) continue;
      if (at.getTime() <= now && now - at.getTime() < 10 * 60000) {
        fired[key] = now;
        const s = new Date(ev.start);
        notify(ev.title || "Event", ev.allDay ? "Today" : `${fmtTime(s)}${ev.location ? " · " + ev.location : ""}`, key);
      }
    }
  }
  for (const k in fired) if (now - fired[k] > 3 * 86400000) delete fired[k];
  try {
    localStorage.setItem("pocket.fired", JSON.stringify(fired));
  } catch (e) {}
}

function nextPos(list) {
  return list.reduce((m, x) => Math.max(m, x._pos ?? 0), 0) + 1;
}

document.addEventListener("click", async (e) => {
  const t = e.target.closest("button, [data-sheet-close], [data-todo-edit]");
  if (!t) return;
  const d = t.dataset;
  if (d.tab) {
    ui.tab = d.tab;
    ui.editing = null;
    localStorage.setItem("pocket.tab", d.tab);
    render();
    window.scrollTo(0, 0);
  } else if (d.timer) {
    timerAction(d.timer);
  } else if (d.project !== undefined) {
    const id = d.project || null;
    const tm = timer();
    if (tm.phase === "idle") {
      ui.project = id;
      render();
    } else store.put("pomodoro.timer", "current", { ...tm, project: id });
  } else if (d.todoToggle) {
    const item = store.get("todo", d.todoToggle);
    store.put("todo", item.id, { ...item, done: !item.done, _pos: nextPos(todos()) });
  } else if (d.todoRemove) {
    store.remove("todo", d.todoRemove);
  } else if (d.todoEdit) {
    const item = store.get("todo", d.todoEdit);
    const title = prompt("Rename", item.title);
    if (title && title.trim()) store.put("todo", item.id, { ...item, title: title.trim() });
  } else if (d.toggleDone !== undefined) {
    ui.showDone = !ui.showDone;
    render();
  } else if (d.clearDone !== undefined) {
    todos()
      .filter((x) => x.done)
      .forEach((x) => store.remove("todo", x.id));
  } else if (d.schedDay) {
    ui.scheduleDay = d.schedDay;
    render();
  } else if (d.schedWeek) {
    const book = scheduleBook();
    ui.scheduleDay = dayKey(addDays(parseDay(ui.scheduleDay || scheduleToday(book)), Number(d.schedWeek)));
    render();
  } else if (d.slot) {
    ui.slot = d.slot;
    render();
  } else if (d.check) {
    const [routine, day, slot, step] = d.check.split("|");
    if (store.get("schedule.check", d.check)) store.remove("schedule.check", d.check);
    else store.put("schedule.check", d.check, { id: d.check, routine, day, slot, step, done: new Date().toISOString().replace(/\.\d{3}Z$/, "Z") });
  } else if (d.calDay) {
    ui.calDay = d.calDay;
    const k = parseDay(d.calDay);
    ui.calMonth = dayKey(new Date(k.getFullYear(), k.getMonth(), 1));
    render();
  } else if (d.calMonth) {
    const base = ui.calMonth ? parseDay(ui.calMonth) : new Date(parseDay(ui.calDay).getFullYear(), parseDay(ui.calDay).getMonth(), 1);
    ui.calMonth = dayKey(new Date(base.getFullYear(), base.getMonth() + Number(d.calMonth), 1));
    render();
  } else if (d.eventNew !== undefined) {
    const base = parseDay(ui.calDay);
    const s = new Date(base.getFullYear(), base.getMonth(), base.getDate(), Math.min(new Date().getHours() + 1, 22), 0);
    ui.editing = { isNew: true, id: store.uuid(), title: "", start: s.toISOString(), end: new Date(s.getTime() + 3600000).toISOString(), allDay: false, alert: 10, hue: 0, repeats: "never", notes: "", location: "" };
    render();
  } else if (d.event) {
    ui.editing = { ...store.get("calendar.event", d.event) };
    render();
  } else if (d.sheetClose !== undefined) {
    ui.editing = null;
    render();
  } else if (d.eventDelete !== undefined) {
    store.remove("calendar.event", ui.editing.id);
    ui.editing = null;
    render();
  } else if (d.theme) {
    savePrefs({ theme: d.theme });
  } else if (d.step) {
    const p = prefs();
    savePrefs({ [d.step]: Math.min(Number(d.max), Math.max(Number(d.min), p[d.step] + Number(d.by))) });
  } else if (d.sync !== undefined) {
    await store.syncNow();
    toast(store.snapshot().problem || "Synced");
  } else if (d.export !== undefined) {
    const blob = new Blob([JSON.stringify(store.exportDocuments(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `pocket-${dayKey(new Date())}.json`;
    a.click();
  } else if (d.signout !== undefined) {
    if (confirm("Sign out on this device? Changes not yet uploaded will be lost.")) await store.signOut();
  } else if (d.notifyAsk !== undefined) {
    await Notification.requestPermission();
    render();
  } else if (d.resetServer !== undefined) {
    store.clearConfig();
  } else if (d.backEmail !== undefined) {
    ui.setupStep = "email";
    ui.setupError = "";
    render();
  }
});

document.addEventListener("change", (e) => {
  if (e.target.matches("[data-allday]") && ui.editing) {
    const form = e.target.closest("form");
    readEventForm(form);
    ui.editing.allDay = e.target.checked;
    const s = new Date(ui.editing.start);
    if (ui.editing.allDay) {
      const day = new Date(s.getFullYear(), s.getMonth(), s.getDate());
      ui.editing.start = day.toISOString();
      ui.editing.end = addDays(day, 1).toISOString();
      ui.editing.alert = ui.editing.alert == null ? null : 0;
    } else {
      const st = new Date(s.getFullYear(), s.getMonth(), s.getDate(), 9, 0);
      ui.editing.start = st.toISOString();
      ui.editing.end = new Date(st.getTime() + 3600000).toISOString();
      ui.editing.alert = ui.editing.alert == null ? null : 10;
    }
    render();
  } else if (e.target.matches("[data-device]")) {
    store.setDevice(e.target.value);
  }
});

function readEventForm(form) {
  const f = new FormData(form);
  const ev = ui.editing;
  ev.title = (f.get("title") || "").trim();
  ev.location = (f.get("location") || "").trim();
  ev.notes = f.get("notes") || "";
  ev.hue = Number(f.get("hue") ?? ev.hue ?? 0);
  ev.repeats = f.get("repeats") || "never";
  const alert = f.get("alert");
  ev.alert = alert === "" || alert == null ? null : Number(alert);
  if (ev.allDay && f.get("startDay")) {
    const s = parseDay(f.get("startDay"));
    const last = parseDay(f.get("endDay") || f.get("startDay"));
    ev.start = s.toISOString();
    ev.end = addDays(last < s ? s : last, 1).toISOString();
  } else if (!ev.allDay && f.get("start")) {
    const s = new Date(f.get("start"));
    let en = new Date(f.get("end") || f.get("start"));
    if (en <= s) en = new Date(s.getTime() + 3600000);
    ev.start = s.toISOString();
    ev.end = en.toISOString();
  }
}

document.addEventListener("submit", async (e) => {
  e.preventDefault();
  const form = e.target;
  const kind = form.dataset.form;
  const f = new FormData(form);
  if (kind === "todo") {
    const title = (f.get("title") || "").trim();
    if (!title) return;
    const id = store.uuid();
    const open = todos().filter((t) => !t.done);
    const firstDone = todos().find((t) => t.done);
    const pos = firstDone ? (open.length ? (open[open.length - 1]._pos + firstDone._pos) / 2 : firstDone._pos - 1) : nextPos(todos());
    store.put("todo", id, { id, title, done: false, created: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"), _pos: pos });
    form.reset();
    $('form[data-form="todo"] input')?.focus();
  } else if (kind === "event") {
    readEventForm(form);
    const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const { isNew, ...ev } = ui.editing;
    const clean = (iso) => new Date(iso).toISOString().replace(/\.\d{3}Z$/, "Z");
    const out = { ...ev, start: clean(ev.start), end: clean(ev.end), updated: now, created: ev.created || now };
    if (out.alert == null) delete out.alert;
    if (!ev.title) return;
    store.put("calendar.event", ev.id, out);
    ui.calDay = dayKey(new Date(ev.start));
    ui.editing = null;
    render();
  } else if (kind === "server") {
    store.configure(f.get("url"), f.get("key"));
    ui.setupError = "";
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

function tick() {
  const el = $("[data-clock]");
  if (el && ui.tab === "focus") {
    const t = timer();
    const left = remaining(t);
    el.textContent = `${pad(Math.floor(left / 60))}:${pad(left % 60)}`;
    const fill = $(".ring .fill");
    if (fill && t.phase !== "idle") {
      const c = 2 * Math.PI * 104;
      fill.style.strokeDashoffset = c * (left / (phaseLength(t) || 1));
    }
  }
  if (store.signedIn()) advanceTimer();
}

readSetupLink();
store.subscribe(render);
render();
setInterval(tick, 1000);
setInterval(checkAlerts, 20000);
setTimeout(checkAlerts, 1500);
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
