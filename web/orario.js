import * as store from "./store.js";
import { esc, dayKey, parseDay, shiftDay, weekday, weekStart, monthStart, monthShift, WEEK, SHORT, ICONS, dayTitle, readLocal, writeLocal } from "./util.js";

const START_DAY = "2026-11-19";
const SLOTS = ["morning", "night"];

export const ui = {
  mode: readLocal("orario.mode", "day"),
  day: null,
  month: null,
  tips: new Set(),
  fold: false,
};

function settings() {
  const s = store.get("schedule.settings", "book") || {};
  return { nightFrom: s.nightFrom ?? 16, dayFrom: s.dayFrom ?? 4 };
}

export function routines() {
  return store
    .all("schedule.routine")
    .filter((r) => /hair/i.test(r.name || ""))
    .sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
}

function checks() {
  const map = new Map();
  for (const c of store.all("schedule.check")) map.set(c.id, c);
  return map;
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

function runsOn(r, day) {
  return r.starts <= day && (!r.ends || day <= r.ends);
}

function stepsOn(r, day, slot) {
  const dated = r.dated && r.dated[`${day}-${slot}`];
  return dated || (r.plan && r.plan[`${weekday(day)}-${slot}`]) || [];
}

function items(day, slot, pool, done) {
  return pool
    .filter((r) => runsOn(r, day))
    .flatMap((r) =>
      stepsOn(r, day, slot).map((step) => {
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
  return { done, pool: routines(), now: { today: today(), slot: slotNow() } };
}

function statusDot(s) {
  return `<i class="st ${s}"></i>`;
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
  const heading = isToday ? (slot === "morning" ? "This morning" : "Tonight") : slot === "morning" ? "Morning" : "Night";
  const tags = routines().length > 1;
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
          <span class="tick ${it.done ? "on" : ""}" role="img" aria-label="${it.done ? "Done" : "Not done"}">${it.done ? ICONS.check : ""}</span>
          <div class="grow">
            <div class="step-title">${stepLabel(it.step.title)}</div>
            ${tags ? `<span class="tag" style="--t:var(--tint-${(it.routine.hue ?? 0) % 8})">${esc(it.routine.name)}</span>` : ""}
            ${it.step.tip && open ? `<div class="tip">${esc(it.step.tip)}</div>` : ""}
          </div>
          ${it.step.tip ? `<button class="icon quiet chev ${open ? "open" : ""}" data-orario-tip="${esc(it.id)}" aria-label="${open ? "Hide tip" : "Show tip"}">${ICONS.down}</button>` : ""}
        </div>`;
            })
            .join("")
        : `<div class="empty">Nothing planned ${slot === "morning" ? "this morning" : "tonight"}.</div>`
    }
  </div>`;
}

function stepLabel(title) {
  const [name, ...rest] = String(title || "").split("|");
  const amount = rest.join("|").trim();
  return amount ? `${esc(name.trim())} <span class="amount">${esc(amount)}</span>` : esc(name.trim());
}

function productsCard(ctx, start) {
  const found = new Map();
  for (const r of ctx.pool) {
    for (const [i, w] of WEEK.entries()) {
      const day = shiftDay(start, i);
      if (!runsOn(r, day)) continue;
      for (const slot of SLOTS) {
        for (const step of stepsOn(r, day, slot)) {
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
    ${productsCard(ctx, start)}`;
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

export function view(tools = "") {
  const ctx = context();
  const all = routines();
  const body = !all.length
    ? `<div class="card empty big">The routine hasn't synced yet.</div>`
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
      ${tools}
    </div>
    ${body}
  </section>`;
}

export function onClick(d) {
  if (d.orarioMode) {
    ui.mode = d.orarioMode;
    writeLocal("orario.mode", ui.mode);
    return "render";
  }
  if (d.orarioDay) {
    ui.day = d.orarioDay === today() ? null : d.orarioDay;
    return "render";
  }
  if (d.orarioOpen) {
    ui.day = d.orarioOpen === today() ? null : d.orarioOpen;
    ui.mode = "day";
    writeLocal("orario.mode", "day");
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
  return false;
}

