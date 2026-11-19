import * as store from "./store.js";
import { esc, dayKey, parseDay, shiftDay, weekday, weekStart, monthStart, monthShift, WEEK, SHORT, LONG, ICONS, isoNow, dayTitle, readLocal, writeLocal } from "./util.js";

const START_DAY = "2026-11-19";
const SLOTS = ["morning", "night"];

export const ui = {
  mode: readLocal("orario.master.mode", "day"),
  day: null,
  month: null,
  tips: new Set(),
  fold: false,
  filter: readLocal("orario.master.filter", null),
  editor: null,
  confirm: null,
};

function settings() {
  const s = store.get("schedule.settings", "book") || {};
  return { nightFrom: s.nightFrom ?? 16, dayFrom: s.dayFrom ?? 4 };
}

export function routines() {
  return store.all("schedule.routine").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
}

function checks() {
  const map = new Map();
  for (const c of store.all("schedule.check")) map.set(c.id, c);
  return map;
}

function shown() {
  const all = routines();
  if (ui.filter && all.some((r) => r.id === ui.filter)) return all.filter((r) => r.id === ui.filter);
  return all;
}

export function today() {
  const { dayFrom } = settings();
  return dayKey(new Date(Date.now() - dayFrom * 3600000));
}

export function slotNow() {
  const { nightFrom, dayFrom } = settings();
  const h = new Date().getHours();
  return h >= nightFrom || h < dayFrom ? "night" : "morning";
}

function firstDay() {
  const all = routines();
  return all.length ? all.map((r) => r.starts).sort()[0] : START_DAY;
}

function items(day, slot, pool, done) {
  const wd = weekday(day);
  return pool
    .filter((r) => r.starts <= day)
    .flatMap((r) =>
      ((r.plan && r.plan[`${wd}-${slot}`]) || []).map((step) => {
        const id = `${r.id}|${day}|${slot}|${step.id}`;
        return { id, routine: r, step, slot, day, done: done.has(id) };
      })
    );
}

function status(day, slot, pool, done, now) {
  if (!pool.some((r) => r.starts <= day)) return "before";
  const list = (slot ? [slot] : SLOTS).flatMap((s) => items(day, s, pool, done));
  if (!list.length) return "rest";
  const n = list.filter((i) => i.done).length;
  if (n === list.length) return "done";
  if (day > now.today) return "upcoming";
  if (day === now.today) {
    const lapsed = slot === "morning" && now.slot === "night";
    if (!lapsed) return "open";
  }
  return n ? "partial" : "missed";
}

function tally(from, through, pool, done, now) {
  let start = from > firstDay() ? from : firstDay();
  const end = through < now.today ? through : now.today;
  let d = 0;
  let m = 0;
  for (let k = start; k <= end; k = shiftDay(k, 1)) {
    const s = status(k, null, pool, done, now);
    if (s === "done") d++;
    else if (s === "missed" || s === "partial") m++;
  }
  return { done: d, missed: m };
}

function context() {
  const done = checks();
  return { done, pool: shown(), now: { today: today(), slot: slotNow() } };
}

function setCheck(item, on) {
  if (on) {
    store.put("schedule.check", item.id, { id: item.id, routine: item.routine.id, day: item.day, slot: item.slot, step: item.step.id, done: isoNow() });
  } else {
    store.remove("schedule.check", item.id);
  }
}

function putRoutine(r) {
  store.put("schedule.routine", r.id, {
    id: r.id,
    name: r.name ?? "",
    hue: r.hue ?? 0,
    starts: r.starts || today(),
    plan: r.plan || {},
    notes: r.notes ?? "",
    _pos: r._pos ?? 0,
  });
}

function updateRoutine(id, change) {
  const r = store.get("schedule.routine", id);
  if (!r) return;
  const copy = JSON.parse(JSON.stringify(r));
  change(copy);
  if (JSON.stringify(copy) !== JSON.stringify(r)) putRoutine(copy);
}

function statusDot(s) {
  return `<i class="st ${s}"></i>`;
}

function hourLabel(h) {
  const d = new Date(2000, 0, 1, h);
  return d.toLocaleTimeString([], { hour: "numeric" });
}

function filterControl() {
  const all = routines();
  if (all.length < 2) return "";
  return `<label class="select"><span class="sr">Routine</span><select data-orario-filter>
    <option value="">All routines</option>
    ${all.map((r) => `<option value="${r.id}" ${ui.filter === r.id ? "selected" : ""}>${esc(r.name || "Untitled")}</option>`).join("")}
  </select>${ICONS.down}</label>`;
}

function weekLimits() {
  const lo = weekStart(firstDay());
  const lastNext = shiftDay(monthShift(today(), 2), -1);
  return { lo, hi: weekStart(lastNext) };
}

function weekStrip(ctx, day) {
  const start = weekStart(day);
  const { lo, hi } = weekLimits();
  return `<div class="card week">
    <div class="week-head">
      <button class="icon quiet" data-orario-week="-7" ${start <= lo ? "disabled" : ""} aria-label="Previous week">${ICONS.left}</button>
      <h3>${dayTitle(start, { day: "numeric", month: "short" })} – ${dayTitle(shiftDay(start, 6), { day: "numeric", month: "short" })}</h3>
      <button class="icon quiet" data-orario-week="7" ${start >= hi ? "disabled" : ""} aria-label="Next week">${ICONS.right}</button>
    </div>
    <div class="strip">${WEEK.map((w, i) => {
      const k = shiftDay(start, i);
      return `<button class="day ${k === day ? "on" : ""} ${k === ctx.now.today ? "today" : ""}" data-orario-day="${k}"><span>${SHORT[w]}</span><b>${parseDay(k).getDate()}</b>${statusDot(status(k, null, ctx.pool, ctx.done, ctx.now))}</button>`;
    }).join("")}</div>
  </div>`;
}

function slotCard(ctx, day, slot, folded) {
  const list = items(day, slot, ctx.pool, ctx.done);
  const n = list.filter((i) => i.done).length;
  const isToday = day === ctx.now.today;
  const future = day > ctx.now.today;
  const heading = isToday ? (slot === "morning" ? "This morning" : "Tonight") : slot === "morning" ? "Morning" : "Night";
  const tags = !ui.filter && routines().length > 1;
  if (folded) {
    return `<button class="card fold" data-orario-fold>
      ${slot === "morning" ? ICONS.sun : ICONS.moon}<span class="grow">${heading}</span>
      <span class="sub">${list.length ? (n ? `${n} of ${list.length} done` : `${list.length} step${list.length === 1 ? "" : "s"}`) : "nothing planned"}</span>${ICONS.down}
    </button>`;
  }
  const pct = list.length ? Math.round((n / list.length) * 100) : 0;
  return `<div class="card slot ${slot}">
    <div class="slot-head">
      ${slot === "morning" ? ICONS.sun : ICONS.moon}<h3>${heading}</h3>
      <span class="sub right">${list.length ? `${n} of ${list.length} done` : ""}</span>
    </div>
    ${list.length ? `<div class="bar"><i style="width:${pct}%"></i></div>` : ""}
    ${
      list.length
        ? list
            .map((it) => {
              const open = ui.tips.has(it.id);
              return `<div class="row step ${it.done ? "done" : ""}">
          <button class="tick ${it.done ? "on" : ""}" data-orario-check="${esc(it.id)}" ${future ? "disabled" : ""} aria-label="${it.done ? "Uncheck" : "Check"}">${it.done ? ICONS.check : ""}</button>
          <div class="grow">
            <button class="step-title" data-orario-check="${esc(it.id)}" ${future ? "disabled" : ""}>${stepLabel(it.step.title)}</button>
            ${tags ? `<span class="tag" style="--t:var(--tint-${(it.routine.hue ?? 0) % 8})">${esc(it.routine.name)}</span>` : ""}
            ${it.step.tip && open ? `<div class="tip">${esc(it.step.tip)}</div>` : ""}
          </div>
          ${it.step.tip ? `<button class="icon quiet chev ${open ? "open" : ""}" data-orario-tip="${esc(it.id)}" aria-label="${open ? "Hide tip" : "Show tip"}">${ICONS.down}</button>` : ""}
        </div>`;
            })
            .join("") +
          (future ? "" : `<div class="slot-foot"><button class="link" data-orario-all="${day}|${slot}|${n === list.length ? "0" : "1"}">${n === list.length ? "All done · Undo all" : "Mark all done"}</button></div>`)
        : `<div class="empty">Nothing planned ${slot === "morning" ? "this morning" : "tonight"}.</div>`
    }
  </div>`;
}

function stepLabel(title) {
  const [name, ...rest] = String(title || "").split("|");
  const amount = rest.join("|").trim();
  return amount ? `${esc(name.trim())} <span class="amount">${esc(amount)}</span>` : esc(name.trim());
}

function productsCard(ctx) {
  const found = new Map();
  for (const r of ctx.pool) {
    for (const w of WEEK) {
      for (const slot of SLOTS) {
        for (const step of (r.plan && r.plan[`${w}-${slot}`]) || []) {
          const title = (step.title || "").trim();
          if (!title) continue;
          const key = title.toLowerCase();
          if (!found.has(key)) found.set(key, { title, days: new Set(), slots: new Set(), times: 0 });
          const p = found.get(key);
          p.days.add(w);
          p.slots.add(slot);
          p.times++;
        }
      }
    }
  }
  if (!found.size) return "";
  const list = [...found.values()].sort((a, b) => a.times - b.times || a.title.localeCompare(b.title));
  return `<div class="card list products">
    <h3>Each week</h3>
    ${list
      .map((p) => {
        const days = p.days.size === 7 ? "Every day" : WEEK.filter((w) => p.days.has(w)).map((w) => SHORT[w]).join(", ");
        const when = p.slots.size === 2 ? " · morning and night" : p.slots.has("morning") ? " · morning" : " · night";
        return `<div class="row product"><div class="grow"><b>${stepLabel(p.title)}</b><span class="sub">${days}${when}</span></div><span class="times">${p.times}×</span></div>`;
      })
      .join("")}
  </div>`;
}

function dayView(ctx) {
  const day = ui.day || ctx.now.today;
  const isToday = day === ctx.now.today;
  let cards;
  if (isToday) {
    const current = ctx.now.slot;
    const other = current === "morning" ? "night" : "morning";
    const main = slotCard(ctx, day, current, false);
    const side = slotCard(ctx, day, other, !ui.fold);
    cards = current === "morning" ? main + side : side + main;
  } else {
    cards = slotCard(ctx, day, "morning", false) + slotCard(ctx, day, "night", false);
  }
  return `
    ${weekStrip(ctx, day)}
    <div class="title-row"><h3>${isToday ? "Today" : dayTitle(day)}</h3>${isToday ? "" : `<button class="link" data-orario-day="${ctx.now.today}">Back to today</button>`}</div>
    ${cards}`;
}

function weekView(ctx) {
  const day = ui.day || ctx.now.today;
  const start = weekStart(day);
  const { lo, hi } = weekLimits();
  const rows = WEEK.map((w, i) => {
    const k = shiftDay(start, i);
    const blocks = SLOTS.map((slot) => {
      const list = items(k, slot, ctx.pool, ctx.done);
      if (!list.length) return "";
      const st = status(k, slot, ctx.pool, ctx.done, ctx.now);
      const late = st === "missed" || st === "partial";
      return `<div class="wslot">${slot === "morning" ? ICONS.sun : ICONS.moon}<div class="chips-left">${list
        .map((it) => `<span class="wstep ${it.done ? "ok" : late ? "late" : ""}">${stepLabel(it.step.title)}</span>`)
        .join("")}</div></div>`;
    }).join("");
    return `<div class="card wday ${k === ctx.now.today ? "today" : ""}">
      <button class="wday-head" data-orario-open="${k}">${statusDot(status(k, null, ctx.pool, ctx.done, ctx.now))}<b>${SHORT[w]} ${parseDay(k).getDate()}</b><span class="sub">${dayTitle(k, { month: "short" })}</span>${ICONS.right}</button>
      ${blocks || `<div class="empty small">Rest</div>`}
    </div>`;
  }).join("");
  return `
    <div class="title-row">
      <button class="icon quiet" data-orario-week="-7" ${start <= lo ? "disabled" : ""} aria-label="Previous week">${ICONS.left}</button>
      <h3 class="grow center">${weekStart(ctx.now.today) === start ? "This week" : `${dayTitle(start, { day: "numeric", month: "short" })} – ${dayTitle(shiftDay(start, 6), { day: "numeric", month: "short" })}`}</h3>
      <button class="icon quiet" data-orario-week="7" ${start >= hi ? "disabled" : ""} aria-label="Next week">${ICONS.right}</button>
    </div>
    ${rows}
    ${productsCard(ctx)}`;
}

function monthView(ctx) {
  const month = ui.month || monthStart(ctx.now.today);
  const lo = monthStart(firstDay());
  const hi = monthShift(ctx.now.today, 1);
  const last = shiftDay(monthShift(month, 1), -1);
  const t = tally(month, last, ctx.pool, ctx.done, ctx.now);
  const gridStart = weekStart(month);
  const cells = [];
  for (let k = gridStart; k <= last || cells.length % 7; k = shiftDay(k, 1)) {
    const inMonth = k.slice(0, 7) === month.slice(0, 7);
    let mark = "";
    if (inMonth && k <= ctx.now.today) {
      const m = status(k, "morning", ctx.pool, ctx.done, ctx.now);
      const n = status(k, "night", ctx.pool, ctx.done, ctx.now);
      if (m !== "before" || n !== "before") mark = `<span class="split"><i class="st ${m}"></i><i class="st ${n}"></i></span>`;
    }
    cells.push(`<button class="cell ${inMonth ? "" : "out"} ${k === ctx.now.today ? "today" : ""}" data-orario-open="${k}" ${inMonth ? "" : "disabled"}><b>${parseDay(k).getDate()}</b>${mark}</button>`);
  }
  return `<div class="card month">
    <div class="week-head">
      <button class="icon quiet" data-orario-month="-1" ${month <= lo ? "disabled" : ""} aria-label="Previous month">${ICONS.left}</button>
      <h3>${parseDay(month).toLocaleDateString([], { month: "long", year: "numeric" })}</h3>
      <button class="icon quiet" data-orario-month="1" ${month >= hi ? "disabled" : ""} aria-label="Next month">${ICONS.right}</button>
    </div>
    <div class="month-line"><span>${t.done} done · ${t.missed} missed</span>${month !== monthStart(ctx.now.today) ? `<button class="link" data-orario-thismonth>This month</button>` : ""}</div>
    <div class="dow">${WEEK.map((w) => `<span>${SHORT[w].slice(0, 2)}</span>`).join("")}</div>
    <div class="grid">${cells.join("")}</div>
  </div>`;
}

export function view() {
  const ctx = context();
  const all = routines();
  const body = !all.length
    ? `<div class="card empty big">No routines yet.<br><button class="primary" data-orario-edit>Make your first routine</button></div>`
    : ui.mode === "week"
    ? weekView(ctx)
    : ui.mode === "month"
    ? monthView(ctx)
    : dayView(ctx);
  return `<section class="orario">
    <div class="toolbar">
      <div class="seg three">
        ${[["day", "Day"], ["week", "Week"], ["month", "Month"]].map(([k, l]) => `<button class="${ui.mode === k ? "on" : ""}" data-orario-mode="${k}">${l}</button>`).join("")}
      </div>
      <button class="icon pill-btn" data-orario-edit aria-label="Change the schedule">${ICONS.pencil}</button>
    </div>
    ${filterControl()}
    ${body}
  </section>
  ${ui.editor ? editorView() : ""}`;
}

function editorRoutine() {
  const all = routines();
  if (!all.length) return null;
  const id = ui.editor.routine && all.some((r) => r.id === ui.editor.routine) ? ui.editor.routine : ui.filter && all.some((r) => r.id === ui.filter) ? ui.filter : all[0].id;
  ui.editor.routine = id;
  return all.find((r) => r.id === id);
}

function editorView() {
  const ed = ui.editor;
  const all = routines();
  const r = editorRoutine();
  const wd = ed.weekday;
  const todayWd = weekday(today());
  const pills = all
    .map((x) =>
      ed.renaming === x.id
        ? `<form class="pill-form" data-form="rename"><input name="name" value="${esc(x.name)}" aria-label="Routine name" autocomplete="off" enterkeyhint="done"></form>`
        : `<button class="rpill ${x.id === r?.id ? "on" : ""}" data-ed-routine="${x.id}"><i style="background:var(--tint-${(x.hue ?? 0) % 8})"></i>${esc(x.name || "Untitled")}</button>`
    )
    .join("");
  const adding = ed.newRoutine ? `<form class="pill-form" data-form="new-routine"><input name="name" placeholder="Routine name" autocomplete="off" enterkeyhint="done"></form>` : `<button class="rpill add" data-ed-new-routine aria-label="New routine">${ICONS.plus}</button>`;
  let body = "";
  if (r) {
    const checkCount = store.all("schedule.check").filter((c) => c.routine === r.id).length;
    const slotBlock = (slot) => {
      const steps = (r.plan && r.plan[`${wd}-${slot}`]) || [];
      return `<div class="card list ed-slot">
        <h3>${slot === "morning" ? ICONS.sun : ICONS.moon}${slot === "morning" ? "Morning" : "Night"}<span class="count">${steps.length || ""}</span></h3>
        ${steps
          .map(
            (s) => `<button class="row ed-step" data-ed-step="${slot}|${s.id}"><div class="grow"><div>${esc(s.title)}</div>${s.tip ? `<div class="tip one">${esc(s.tip)}</div>` : ""}</div>${ICONS.right}</button>`
          )
          .join("")}
        <form class="row add-step" data-form="add-${slot}"><span class="plus">${ICONS.plus}</span><input name="title" placeholder="Add a step" autocomplete="off" enterkeyhint="done"></form>
      </div>`;
    };
    body = `
      <div class="ed-actions">
        <button class="link" data-ed-rename="${r.id}">Rename</button>
        <button class="link danger" data-ed-delete="${r.id}">Delete…</button>
      </div>
      ${
        ui.confirm === r.id
          ? `<div class="card confirm"><p>Delete <b>${esc(r.name || "Untitled")}</b>${checkCount ? ` and its ${checkCount} check-off${checkCount === 1 ? "" : "s"}` : ""}? Other devices lose it too.</p><div class="controls left"><button class="ghost danger" data-ed-delete-yes="${r.id}">Delete</button><button class="ghost" data-ed-delete-no>Cancel</button></div></div>`
          : ""
      }
      <div class="wdays">${WEEK.map((w) => `<button class="wd ${w === wd ? "on" : ""} ${w === todayWd ? "today" : ""}" data-ed-weekday="${w}"><span>${SHORT[w]}</span><i>${["morning", "night"].reduce((a, s) => a + (((r.plan && r.plan[`${w}-${s}`]) || []).length), 0) || ""}</i></button>`).join("")}</div>
      <div class="ed-day">${LONG[wd]}</div>
      ${slotBlock("morning")}
      ${slotBlock("night")}
      <p class="hint">Weeks repeat; put a step on each day you want it.</p>`;
  } else {
    body = `<div class="card empty big">Add a routine with + above.</div>`;
  }
  return `<div class="overlay" role="dialog" aria-label="Change the schedule">
    <div class="overlay-bar"><h2>Change the schedule</h2><button class="primary small" data-ed-close>Done</button></div>
    <div class="overlay-body" data-keep-scroll="editor">
      <div class="pills">${pills}${adding}</div>
      ${body}
    </div>
    ${ed.step ? stepSheet(r) : ""}
  </div>`;
}

function stepSheet(r) {
  const { slot, id } = ui.editor.step;
  const key = `${ui.editor.weekday}-${slot}`;
  const steps = (r && r.plan && r.plan[key]) || [];
  const index = steps.findIndex((s) => s.id === id);
  if (index < 0) return "";
  const s = steps[index];
  return `<div class="sheet-back" data-ed-step-close></div>
  <form class="sheet card" data-form="step">
    <div class="sheet-head"><h3>${LONG[ui.editor.weekday]} ${slot}</h3><button type="button" class="icon quiet" data-ed-step-close aria-label="Close">${ICONS.close}</button></div>
    <label>Step<input name="title" value="${esc(s.title)}" required autocomplete="off"></label>
    <label>How to do it<textarea name="tip" rows="5">${esc(s.tip || "")}</textarea></label>
    <div class="sheet-tools">
      <button type="button" class="icon pill-btn" data-ed-move="-1" ${index === 0 ? "disabled" : ""} aria-label="Move up">${ICONS.up}</button>
      <button type="button" class="icon pill-btn" data-ed-move="1" ${index === steps.length - 1 ? "disabled" : ""} aria-label="Move down">${ICONS.down}</button>
      <button type="button" class="icon pill-btn danger" data-ed-step-delete aria-label="Delete step">${ICONS.trash}</button>
      <button class="primary right">Done</button>
    </div>
  </form>`;
}

function saveStepForm(form) {
  if (!form || !ui.editor?.step) return;
  const f = new FormData(form);
  const title = String(f.get("title") || "").trim();
  const tip = String(f.get("tip") || "").trim();
  const { slot, id } = ui.editor.step;
  const key = `${ui.editor.weekday}-${slot}`;
  updateRoutine(ui.editor.routine, (r) => {
    const s = (r.plan[key] || []).find((x) => x.id === id);
    if (s && title) {
      s.title = title;
      s.tip = tip;
    }
  });
}

export function onChange(e) {
  const t = e.target;
  if (t.matches("[data-orario-filter]")) {
    ui.filter = t.value || null;
    writeLocal("orario.master.filter", ui.filter);
    return "render";
  }
  return false;
}

export function onFocusOut(e) {
  const form = e.target.closest && e.target.closest("form");
  if (!form) return;
  const kind = form.dataset.form;
  if (kind === "rename" && !form.contains(e.relatedTarget)) submitRename(form);
  if (kind === "new-routine" && !form.contains(e.relatedTarget)) submitNewRoutine(form);
  if ((kind === "add-morning" || kind === "add-night") && !form.contains(e.relatedTarget)) {
    const input = form.querySelector("input");
    if (input.value.trim()) submitStep(form, kind.slice(4), false);
  }
}

function submitRename(form) {
  if (!ui.editor || !ui.editor.renaming) return;
  const id = ui.editor.renaming;
  const name = String(new FormData(form).get("name") || "").trim();
  ui.editor.renaming = null;
  if (name) updateRoutine(id, (r) => (r.name = name));
  return "render";
}

function submitNewRoutine(form) {
  if (!ui.editor || !ui.editor.newRoutine) return;
  ui.editor.newRoutine = false;
  const name = String(new FormData(form).get("name") || "").trim();
  if (!name) return "render";
  const all = routines();
  const id = store.uuid();
  const hue = all.reduce((m, r) => Math.max(m, r.hue ?? 0), -1) + 1;
  putRoutine({ id, name, hue, starts: today(), plan: {}, notes: "", _pos: all.reduce((m, r) => Math.max(m, r._pos ?? 0), 0) + 1 });
  ui.editor.routine = id;
  return "render";
}

function submitStep(form, slot, keepFocus) {
  const input = form.querySelector("input");
  const title = input.value.trim();
  if (!title) return;
  const key = `${ui.editor.weekday}-${slot}`;
  input.value = "";
  updateRoutine(ui.editor.routine, (r) => {
    r.plan = r.plan || {};
    r.plan[key] = [...(r.plan[key] || []), { id: store.uuid(), title, tip: "" }];
  });
  if (keepFocus) ui.editor.refocus = `add-${slot}`;
}

export function onSubmit(kind, form) {
  if (kind === "rename") return submitRename(form) || true;
  if (kind === "new-routine") return submitNewRoutine(form) || true;
  if (kind === "add-morning" || kind === "add-night") {
    submitStep(form, kind.slice(4), true);
    return true;
  }
  if (kind === "step") {
    saveStepForm(form);
    ui.editor.step = null;
    return "render";
  }
  return false;
}

export function afterRender() {
  if (ui.editor && ui.editor.refocus) {
    const el = document.querySelector(`form[data-form="${ui.editor.refocus}"] input`);
    ui.editor.refocus = null;
    if (el) el.focus();
  }
  if (ui.editor && (ui.editor.renaming || ui.editor.newRoutine) && !document.activeElement?.closest?.(".pill-form")) {
    const el = document.querySelector(".pill-form input");
    if (el) {
      el.focus();
      el.select();
    }
  }
}

export function onClick(d) {
  if (d.orarioMode) {
    ui.mode = d.orarioMode;
    writeLocal("orario.master.mode", ui.mode);
    return "render";
  }
  if (d.orarioDay) {
    ui.day = d.orarioDay === today() ? null : d.orarioDay;
    return "render";
  }
  if (d.orarioOpen) {
    ui.day = d.orarioOpen === today() ? null : d.orarioOpen;
    ui.mode = "day";
    writeLocal("orario.master.mode", "day");
    return "render";
  }
  if (d.orarioWeek) {
    const { lo, hi } = weekLimits();
    let next = shiftDay(ui.day || today(), Number(d.orarioWeek));
    if (weekStart(next) < lo || weekStart(next) > hi) return false;
    ui.day = next === today() ? null : next;
    return "render";
  }
  if (d.orarioMonth) {
    ui.month = monthShift(ui.month || monthStart(today()), Number(d.orarioMonth));
    return "render";
  }
  if (d.orarioThismonth !== undefined) {
    ui.month = null;
    return "render";
  }
  if (d.orarioFold !== undefined) {
    ui.fold = !ui.fold;
    return "render";
  }
  if (d.orarioTip) {
    if (ui.tips.has(d.orarioTip)) ui.tips.delete(d.orarioTip);
    else ui.tips.add(d.orarioTip);
    return "render";
  }
  if (d.orarioCheck) {
    const [routine, day, slot, step] = d.orarioCheck.split("|");
    if (day > today()) return false;
    const r = store.get("schedule.routine", routine);
    if (!r) return false;
    const on = !store.get("schedule.check", d.orarioCheck);
    setCheck({ id: d.orarioCheck, routine: r, day, slot, step: { id: step } }, on);
    return true;
  }
  if (d.orarioAll) {
    const [day, slot, flag] = d.orarioAll.split("|");
    const ctx = context();
    const on = flag === "1";
    for (const it of items(day, slot, ctx.pool, ctx.done)) if (it.done !== on) setCheck(it, on);
    return true;
  }
  if (d.orarioEdit !== undefined) {
    ui.editor = { routine: null, weekday: weekday(ui.day || today()), step: null, renaming: null, newRoutine: !routines().length };
    ui.confirm = null;
    return "render";
  }
  if (d.edClose !== undefined) {
    ui.editor = null;
    ui.confirm = null;
    return "render";
  }
  if (d.edRoutine) {
    if (ui.editor.routine === d.edRoutine && !ui.editor.renaming) ui.editor.renaming = d.edRoutine;
    else ui.editor.routine = d.edRoutine;
    ui.confirm = null;
    return "render";
  }
  if (d.edNewRoutine !== undefined) {
    ui.editor.newRoutine = true;
    return "render";
  }
  if (d.edRename) {
    ui.editor.renaming = d.edRename;
    return "render";
  }
  if (d.edDelete) {
    ui.confirm = d.edDelete;
    return "render";
  }
  if (d.edDeleteNo !== undefined) {
    ui.confirm = null;
    return "render";
  }
  if (d.edDeleteYes) {
    const id = d.edDeleteYes;
    for (const c of store.all("schedule.check")) if (c.routine === id) store.remove("schedule.check", c.id);
    store.remove("schedule.routine", id);
    if (ui.filter === id) {
      ui.filter = null;
      writeLocal("orario.master.filter", null);
    }
    ui.confirm = null;
    ui.editor.routine = null;
    return "render";
  }
  if (d.edWeekday) {
    ui.editor.weekday = Number(d.edWeekday);
    return "render";
  }
  if (d.edStep) {
    const [slot, id] = d.edStep.split("|");
    ui.editor.step = { slot, id };
    return "render";
  }
  if (d.edStepClose !== undefined) {
    saveStepForm(document.querySelector('form[data-form="step"]'));
    ui.editor.step = null;
    return "render";
  }
  if (d.edMove) {
    saveStepForm(document.querySelector('form[data-form="step"]'));
    const { slot, id } = ui.editor.step;
    const key = `${ui.editor.weekday}-${slot}`;
    updateRoutine(ui.editor.routine, (r) => {
      const list = r.plan[key] || [];
      const i = list.findIndex((s) => s.id === id);
      const j = i + Number(d.edMove);
      if (i < 0 || j < 0 || j >= list.length) return;
      [list[i], list[j]] = [list[j], list[i]];
    });
    return "render";
  }
  if (d.edStepDelete !== undefined) {
    const { slot, id } = ui.editor.step;
    const key = `${ui.editor.weekday}-${slot}`;
    updateRoutine(ui.editor.routine, (r) => {
      r.plan[key] = (r.plan[key] || []).filter((s) => s.id !== id);
      if (!r.plan[key].length) delete r.plan[key];
    });
    ui.editor.step = null;
    return "render";
  }
  return false;
}

export function nightFrom() {
  return settings().nightFrom;
}

export function setNightFrom(by) {
  const s = settings();
  const next = Math.min(23, Math.max(s.dayFrom + 1, s.nightFrom + by));
  if (next !== s.nightFrom) store.put("schedule.settings", "book", { ...(store.get("schedule.settings", "book") || {}), nightFrom: next, dayFrom: s.dayFrom });
}

export { hourLabel };
