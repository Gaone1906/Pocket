import * as store from "./store.js";
import { $, esc, ICONS, readLocal, writeLocal, shiftDay, parseDay, monthShift, isoNow } from "./util.js";
import * as P from "./plan.js";

const SLOT_LABEL = { breakfast: "Breakfast", lunch: "Lunch", snack: "Snack", dinner: "Dinner" };
const ACTIVITY = [
  ["Sitting", 1.2],
  ["Light", 1.375],
  ["Moderate", 1.55],
  ["Active", 1.725],
];
const LOGO = '<img src="icon.svg" alt="" class="logo-img">';

const ui = {
  view: readLocal("misura.view", "day"),
  day: null,
  sheet: null,
  setupError: "",
  toast: "",
  draft: null,
  weigh: null,
  fab: false,
};

const fmt = (n) => {
  const r = Math.round(n);
  return (r < 0 ? "−" : "") + Math.abs(r).toLocaleString("en-US");
};
const kg1 = (n) => (n < 0 ? "−" : "") + Math.abs(n).toFixed(1);
const signed = (n) => (Math.round(n * 10) === 0 ? "0.0" : (n > 0 ? "+" : "−") + Math.abs(n).toFixed(1));
const short = (k) => parseDay(k).toLocaleDateString([], { day: "numeric", month: "short" });
const wd = (k) => parseDay(k).toLocaleDateString([], { weekday: "short" });

function plan() {
  const rec = store.get("calorie.settings", "book");
  return rec && rec.plan ? P.withDefaults(rec.plan) : null;
}

function data() {
  return P.model(plan(), store.all("calorie.entry"), store.all("calorie.weight"), P.today());
}

function shown(m) {
  return ui.day || m.today;
}

function bar(value, marker, tint) {
  const v = Math.max(0, Math.min(1, value || 0));
  return `<div class="bar"><i style="width:${(v * 100).toFixed(1)}%;${tint ? `background:${tint}` : ""}"></i>${marker != null ? `<span class="mk" style="left:${(Math.max(0, Math.min(1, marker)) * 100).toFixed(1)}%"></span>` : ""}</div>`;
}

function ring(fraction, size, stroke, over) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const f = Math.max(0, Math.min(1, fraction));
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" class="ring"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="var(--track)" stroke-width="${stroke}"/><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${over ? "var(--over)" : "var(--under)"}" stroke-width="${stroke}" stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${(c * (1 - f)).toFixed(1)}" transform="rotate(-90 ${size / 2} ${size / 2})"/></svg>`;
}

function head() {
  return `<header class="hd"><div class="logo">${LOGO}</div><h1 class="name">Terra</h1><button class="gear" data-go="settings" aria-label="Settings">${ICONS.settings}</button></header>
  <div class="seg">${["day", "week", "month"].map((v) => `<button class="${ui.view === v ? "on" : ""}" data-go="${v}">${v[0].toUpperCase() + v.slice(1)}</button>`).join("")}</div>`;
}

function strip(m, k) {
  const days = P.weekDays(k);
  return `<div class="card strip"><button class="nav" data-day="${shiftDay(k, -7)}" aria-label="Previous week">${ICONS.left}</button>${days
    .map((d) => {
      const s = m.summary(d);
      const dot = s && s.logged && d < m.today ? `<i class="dot" style="background:${s.over ? "var(--over)" : "var(--under)"}"></i>` : `<i class="dot ring${d === m.today ? " now" : ""}"></i>`;
      return `<button class="d${d === k ? " on" : ""}" data-day="${d}"><span class="w">${wd(d)}</span><span class="n">${parseDay(d).getDate()}</span>${dot}</button>`;
    })
    .join("")}<button class="nav" data-day="${shiftDay(k, 7)}" aria-label="Next week">${ICONS.right}</button></div>`;
}

function viewDay() {
  const m = data();
  const k = shown(m);
  const s = m.summary(k);
  const list = m.entries(k);
  const kg = m.weightOn(k);
  const items = [...list.filter((e) => e.kind !== "workout").sort((a, b) => P.SLOTS.indexOf(a.slot) - P.SLOTS.indexOf(b.slot)), ...list.filter((e) => e.kind === "workout")];
  return `<main>
    ${head()}
    ${strip(m, k)}
    <div class="card hero">
      <div class="ringbox">${ring(s.eaten / Math.max(1, s.budget), 128, 13, s.over)}<div class="mid"><b class="${s.left < 0 ? "bad" : ""}">${fmt(Math.abs(s.left))}</b><span>${s.left < 0 ? "over" : "left"}</span></div></div>
      <div class="facts">
        <div class="row"><span>Budget</span><b>${fmt(s.budget)}</b></div>
        <div class="row"><span>Eaten</span><b>${fmt(s.eaten)}</b></div>
        <div class="row"><span>Workout</span><b class="good">${fmt(s.workout)}</b></div>
        <div class="row line"><span>Deficit</span><b>${fmt(s.base + s.workout - s.eaten)}</b></div>
      </div>
    </div>
    <div class="card list">
      ${items.length ? items.map((e) => `<button class="it" data-edit="${esc(e.id)}"><span>${esc(e.title)}</span><b class="${e.kind === "workout" ? "good" : ""}">${e.kind === "workout" ? fmt(-e.kcal * m.plan.watchShare) : fmt(e.kcal)}</b></button>`).join("") : `<div class="empty">Nothing logged</div>`}
      <button class="it" data-sheet="weigh"><span>Weight</span><b>${kg != null ? kg.toFixed(1) + " kg" : "–"}</b></button>
    </div>
  </main>`;
}

function viewWeek() {
  const m = data();
  const k = shown(m);
  const w = m.week(k);
  const days = P.weekDays(k);
  const top = Math.max(1, ...w.days.map((d) => Math.max(d.eaten, d.budget))) * 1.08;
  const H = 130;
  const budget = w.days[0].budget;
  const goal = P.dailyGoal(m.plan);
  const first = m.average(shiftDay(days[0], -1));
  const last = m.average(days[6] < m.today ? days[6] : m.today);
  const rows = w.days.filter((d) => d.logged || m.weightOn(d.day) != null);
  return `<main>
    ${head()}
    <div class="row navrow"><button class="nav" data-day="${shiftDay(k, -7)}" aria-label="Previous week">${ICONS.left}</button><span class="ttl">${short(days[0])} – ${short(days[6])}</span><button class="nav" data-day="${shiftDay(k, 7)}" aria-label="Next week">${ICONS.right}</button></div>
    <div class="card">
      <div class="row"><span class="kick">Deficit</span>${w.due > 0 ? `<span class="pill ${w.underLimit ? "" : "bad"}">${w.underLimit ? "Under the limit" : "Over the limit"}</span>` : ""}</div>
      <div class="row base"><span class="big">${fmt(w.deficit)}</span><span class="sub">/ ${fmt(w.goal)}</span></div>
      ${bar(w.deficit / Math.max(1, w.goal), w.due / Math.max(1, w.goal))}
    </div>
    <div class="card">
      <div class="kick">Eaten</div>
      <div class="chart" style="height:${H + 26}px">
        <div class="limit" style="bottom:${26 + (H * budget) / top}px"><span>${fmt(budget)}</span></div>
        ${w.days
          .map(
            (d) => `<button class="col" data-pick="${d.day}"><div class="stack" style="height:${H}px">${
              d.logged
                ? `<i class="eat${d.over ? " over" : ""}${d.day === m.today ? " now" : ""}" style="height:${Math.max(4, (H * d.eaten) / top)}px"></i><i class="burn" style="height:${(H * d.workout) / top}px"></i>`
                : `<i class="none"></i>`
            }</div><span class="${d.day === m.today ? "b" : ""}">${wd(d.day)}</span></button>`
          )
          .join("")}
      </div>
    </div>
    <div class="card facts">
      <div class="row"><span>Per day left</span><b>${fmt(m.perDayLeft(w))}</b></div>
      <div class="row"><span>Avg eaten</span><b>${fmt(w.avgEaten)}</b></div>
      <div class="row"><span>Workouts</span><b>${fmt(w.workouts)}</b></div>
      ${first != null && last != null ? `<div class="row"><span>Weight</span><b>${first.toFixed(1)} → ${last.toFixed(1)}</b></div>` : ""}
    </div>
    ${
      rows.length
        ? `<div class="card table"><div class="tr th"><span>Day</span><span>kg</span><span>Eaten</span><span>Deficit / goal</span></div>${rows
            .map((d) => {
              const kg = m.weightOn(d.day);
              return `<button class="tr" data-pick="${d.day}"><span>${wd(d.day)} ${parseDay(d.day).getDate()}</span><span>${kg != null ? `<em class="kg">${kg.toFixed(1)}</em>` : "–"}</span><span class="food">${fmt(d.eaten)}</span><span><b class="${d.deficit >= goal ? "good" : "bad"}">${fmt(d.deficit)}</b> <small>/ ${fmt(goal)}</small></span></button>`;
            })
            .join("")}</div>`
        : ""
    }
  </main>`;
}

function trend(m, days) {
  const pts = days.map((k, i) => ({ i, kg: m.weightOn(k), avg: m.weightOn(k) != null ? m.average(k) : null })).filter((p) => p.kg != null);
  if (!pts.length) return `<div class="empty">No weigh-ins yet</div>`;
  const vals = pts.flatMap((p) => [p.kg, p.avg]);
  const lo = Math.min(...vals) - 0.4;
  const hi = Math.max(...vals) + 0.4;
  const W = 310;
  const Hh = 120;
  const x = (i) => 8 + (i * (W - 16)) / Math.max(1, days.length - 1);
  const y = (v) => 8 + ((hi - v) / Math.max(0.1, hi - lo)) * (Hh - 16);
  const lastPt = pts[pts.length - 1];
  return `<svg viewBox="0 0 ${W} ${Hh}" class="trend" role="img" aria-label="Weight trend">
    <g fill="var(--faint)" stroke="none">${pts.map((p) => `<circle cx="${x(p.i).toFixed(1)}" cy="${y(p.kg).toFixed(1)}" r="2.6"/>`).join("")}</g>
    <polyline points="${pts.map((p) => `${x(p.i).toFixed(1)},${y(p.avg).toFixed(1)}`).join(" ")}" fill="none" stroke="var(--accent)" stroke-width="2.5" stroke-linejoin="round"/>
    <circle cx="${x(lastPt.i).toFixed(1)}" cy="${y(lastPt.avg).toFixed(1)}" r="5" fill="var(--accent-ink)" stroke="#fff" stroke-width="2"/>
  </svg>`;
}

function viewMonth() {
  const m = data();
  const k = shown(m);
  const days = P.monthDays(k);
  const loss = m.monthLoss(k);
  const lead = (parseDay(days[0]).getDay() + 6) % 7;
  const cells = Array(lead).fill(null).concat(days);
  return `<main>
    ${head()}
    <div class="row navrow"><button class="nav" data-day="${monthShift(k, -1)}" aria-label="Previous month">${ICONS.left}</button><span class="ttl">${parseDay(k).toLocaleDateString([], { month: "long", year: "numeric" })}</span><button class="nav" data-day="${monthShift(k, 1)}" aria-label="Next month">${ICONS.right}</button></div>
    <div class="card">
      <div class="cal">${["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) => `<span class="h">${d[0]}</span>`).join("")}${cells
        .map((d) => {
          if (!d) return `<span></span>`;
          const s = m.summary(d);
          const cls = !s.logged ? "f" : s.over ? "o" : "";
          return `<button class="c ${cls}${d === m.today ? " t" : ""}" data-pick="${d}">${parseDay(d).getDate()}</button>`;
        })
        .join("")}</div>
    </div>
    <div class="card">
      <div class="kick">Weight</div>
      <div class="row base"><span class="big">${kg1(-loss.lost)} kg</span><span class="sub">/ ${kg1(-loss.target)}</span></div>
      ${bar(loss.lost / Math.max(0.1, loss.target), loss.due / Math.max(0.1, loss.target))}
      ${trend(m, days.filter((d) => d <= m.today))}
    </div>
    <div class="card facts">
      <div class="row"><span>Deficit</span><b>${fmt(loss.span.deficit)} / ${fmt(loss.span.goal)}</b></div>
      <div class="row"><span>Avg eaten</span><b>${fmt(loss.span.avgEaten)}</b></div>
    </div>
  </main>`;
}

function planFields(d) {
  return `<div class="grid2">
    <label class="fld"><span>Born</span><input type="date" name="born" value="${esc(d.born)}"></label>
    <label class="fld"><span>Sex</span><select name="sex"><option value="male" ${d.sex === "male" ? "selected" : ""}>Male</option><option value="female" ${d.sex === "female" ? "selected" : ""}>Female</option></select></label>
    <label class="fld"><span>Height</span><input inputmode="decimal" name="heightCm" value="${esc(d.heightCm ?? "")}" placeholder="cm"></label>
    <label class="fld"><span>Activity</span><select name="activity">${ACTIVITY.map(([l, v]) => `<option value="${v}" ${Number(d.activity) === v ? "selected" : ""}>${l}</option>`).join("")}</select></label>
    <label class="fld"><span>Weight</span><input inputmode="decimal" name="startKg" value="${esc(d.startKg ?? "")}" placeholder="kg"></label>
    <label class="fld"><span>From</span><input type="date" name="startDay" value="${esc(d.startDay)}"></label>
    <label class="fld"><span>Goal</span><input inputmode="decimal" name="goalKg" value="${esc(d.goalKg ?? "")}" placeholder="kg"></label>
    <label class="fld"><span>By</span><input type="date" name="goalDay" value="${esc(d.goalDay)}"></label>
  </div>
  <div class="row"><span>Pace</span><div class="seg mini">${[
    ["fastest", "Fastest"],
    ["ontime", "On time"],
  ]
    .map(([v, l]) => `<label class="${d.pace === v ? "on" : ""}"><input type="radio" name="pace" value="${v}" ${d.pace === v ? "checked" : ""}>${l}</label>`)
    .join("")}</div></div>
  <label class="row"><span>Lowest budget</span><input class="inline" inputmode="numeric" name="floor" value="${esc(d.floor ?? 1500)}"></label>`;
}

function readPlan(form, old) {
  const f = new FormData(form);
  const num = (n) => Number(String(f.get(n) || "").replace(",", "."));
  const next = {
    ...(old || {}),
    born: f.get("born"),
    sex: f.get("sex"),
    heightCm: num("heightCm"),
    activity: num("activity"),
    startKg: num("startKg"),
    startDay: f.get("startDay"),
    goalKg: num("goalKg"),
    goalDay: f.get("goalDay"),
    pace: f.get("pace") || "fastest",
    floor: num("floor") || 1500,
  };
  if (!next.born || !next.startDay || !next.goalDay || next.goalDay <= next.startDay) return null;
  if (!(next.heightCm > 100 && next.heightCm < 250 && next.startKg > 25 && next.startKg < 400 && next.goalKg > 25 && next.goalKg < 400 && next.floor >= 800)) return null;
  return next;
}

function viewPlan() {
  const now = P.today();
  const d = ui.draft || { born: shiftDay(now, -9131), sex: "male", activity: 1.2, startDay: now, goalDay: shiftDay(now, 182), pace: "fastest", floor: 1500 };
  return `<main class="setup">
    <div class="hd"><div class="logo">${LOGO}</div><h1 class="name">Terra</h1></div>
    <h2 class="ttl">Your plan</h2>
    <form data-form="plan" class="card col gap">
      ${planFields(d)}
      <button class="primary xl">Start</button>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </form>
  </main>`;
}

function viewSettings() {
  const p = plan();
  const st = store.snapshot();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  return `<main>
    <header class="hd"><button class="gear" data-go="day" aria-label="Back">${ICONS.left}</button><h1 class="name">Settings</h1></header>
    <form data-form="settings" class="card col gap">
      <div class="kick">Plan</div>
      ${planFields(p)}
      <div class="row"><span>Daily deficit</span><b>${fmt(P.dailyGoal(p))}</b></div>
      <button class="primary">Save plan</button>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </form>
    <div class="card opts">
      <div class="kick">Workouts</div>
      <div class="opt"><span>Watch counts</span><span class="stepper"><button class="ghost sm" data-share="-5" aria-label="Less">−</button><b>${Math.round(p.watchShare * 100)}%</b><button class="ghost sm" data-share="5" aria-label="More">+</button></span></div>
      <label class="opt"><span>Eat back</span><input type="checkbox" class="switch" data-flag="eatBack" ${p.eatBack ? "checked" : ""}></label>
    </div>
    <div class="card opts">
      <div class="opt"><span>This device</span><input class="inline" data-device value="${esc(st.device)}" aria-label="Device name"></div>
      <div class="opt"><span>Last synced</span><span class="sub">${last ? last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" }) : "never"}</span></div>
      <div class="opt"><span>Waiting to upload</span><span class="sub">${store.pendingCount()}</span></div>
      ${st.problem ? `<div class="warn">${esc(st.problem)}</div>` : ""}
      <div class="row gap wrap"><button class="ghost" data-sync>Sync now</button><button class="ghost" data-export>Download</button><button class="ghost danger" data-signout>Disconnect</button></div>
    </div>
  </main>`;
}

function viewSetup() {
  return `<main class="setup">
    <div class="card">
      <div class="hd"><div class="logo">${LOGO}</div><h1 class="name">Terra</h1></div>
      <p class="sub">Paste your Pocket setup link.</p>
      <form data-form="server" class="col gap">
        <input name="link" placeholder="https://gaone1906.github.io/Pocket/terra/#connect=…" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
        <details><summary class="sub">Or enter the Supabase values</summary>
          <input name="url" placeholder="Project URL (https://xxxx.supabase.co)" autocomplete="off" autocapitalize="off" aria-label="Project URL">
          <input name="key" placeholder="Anon public key" autocomplete="off" autocapitalize="off" aria-label="Anon public key">
        </details>
        <button class="primary xl">Continue</button>
      </form>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </div>
  </main>`;
}

function sheetEntry(kind, entry) {
  const m = data();
  const slot = entry ? entry.slot : P.slotNow();
  return `<form data-form="entry" class="sheet" data-kind="${kind}" data-id="${entry ? esc(entry.id) : ""}">
    <div class="grab"></div>
    <div class="row"><b class="sheet-t">${kind === "workout" ? "Workout" : "Meal"}</b><button type="button" class="chip" data-close>Cancel</button></div>
    <input name="title" placeholder="${kind === "workout" ? "Gym" : "What"}" value="${entry ? esc(entry.title) : ""}" autocomplete="off" aria-label="Name">
    <label class="kcal"><input name="kcal" inputmode="numeric" placeholder="0" value="${entry ? Math.round(entry.kcal) : ""}" aria-label="kcal"><span>${kind === "workout" ? "kcal on the Watch" : "kcal"}</span></label>
    ${kind === "workout" ? `<div class="sub">Counts ${Math.round(m.plan.watchShare * 100)}%</div>` : `<div class="chips">${P.SLOTS.map((s) => `<label class="${s === slot ? "on" : ""}"><input type="radio" name="slot" value="${s}" ${s === slot ? "checked" : ""}>${SLOT_LABEL[s]}</label>`).join("")}</div>`}
    <div class="row gap">${entry ? `<button type="button" class="ghost danger" data-delete="${esc(entry.id)}">Delete</button>` : ""}<button class="primary grow">Save</button></div>
  </form>`;
}

function sheetWeigh() {
  const m = data();
  const k = shown(m);
  const kg = ui.weigh ?? m.weightOn(k) ?? m.asOf(k) ?? m.plan.startKg;
  const days = Array.from({ length: 14 }, (_, i) => shiftDay(k, i - 13));
  const avg = m.average(k);
  const weekAgo = m.average(shiftDay(k, -7));
  return `<form data-form="weigh" class="sheet">
    <div class="grab"></div>
    <div class="row"><b class="sheet-t">Weight</b><button type="button" class="chip" data-close>Cancel</button></div>
    <div class="weigh"><button type="button" class="step" data-kg="-0.1" aria-label="Down 0.1 kg">−</button><div><input name="kg" inputmode="decimal" value="${kg.toFixed(1)}" aria-label="kg"><div class="sub">kg</div></div><button type="button" class="step" data-kg="0.1" aria-label="Up 0.1 kg">+</button></div>
    <div class="card spark"><div class="kick">14 days</div>${trend(m, days)}</div>
    ${avg != null ? `<div class="row"><span>Average</span><b>${avg.toFixed(1)} kg</b></div>` : ""}
    ${avg != null && weekAgo != null ? `<div class="row"><span>Week</span><b>${signed(avg - weekAgo)} kg</b></div>` : ""}
    <button class="primary xl">Save</button>
  </form>`;
}

function render() {
  const app = $("#app");
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  if (!plan()) {
    if (ui.view === "settings") ui.view = "day";
    app.innerHTML = viewPlan();
    return;
  }
  const views = { day: viewDay, week: viewWeek, month: viewMonth, settings: viewSettings };
  if (!views[ui.view]) ui.view = "day";
  let sheet = "";
  if (ui.sheet) {
    if (ui.sheet === "weigh") sheet = sheetWeigh();
    else if (ui.sheet.startsWith("edit:")) {
      const e = store.get("calorie.entry", ui.sheet.slice(5));
      sheet = e ? sheetEntry(e.kind, e) : "";
    } else sheet = sheetEntry(ui.sheet);
    if (sheet) sheet = `<div class="dim" data-close></div>${sheet}`;
  }
  app.innerHTML = views[ui.view]() + (ui.view === "settings" ? "" : fab()) + sheet + (ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : "");
}

function fab() {
  return `<div class="fabs${ui.fab ? " open" : ""}"><div class="fab-dim" data-fab></div><div class="fab-menu">
    <button class="fab-opt" data-sheet="weigh"><span>Weight</span></button>
    <button class="fab-opt burn" data-sheet="workout"><span>Workout</span></button>
    <button class="fab-opt meal" data-sheet="meal"><span>Meal</span></button>
  </div><button class="fab" data-fab aria-label="Add" aria-expanded="${ui.fab ? "true" : "false"}">${ICONS.plus}</button></div>`;
}

function toast(text) {
  ui.toast = text;
  render();
  clearTimeout(toast.t);
  toast.t = setTimeout(() => {
    ui.toast = "";
    render();
  }, 2200);
}

function go(view) {
  ui.view = view;
  ui.fab = false;
  ui.sheet = null;
  ui.setupError = "";
  if (view !== "settings") writeLocal("misura.view", view);
  render();
  window.scrollTo(0, 0);
}

function savePlan(next) {
  const rec = store.get("calorie.settings", "book") || {};
  store.put("calorie.settings", "book", { ...rec, plan: next });
}

document.addEventListener("click", async (e) => {
  const t = e.target.closest("[data-fab],[data-go],[data-day],[data-pick],[data-sheet],[data-edit],[data-close],[data-delete],[data-kg],[data-share],[data-sync],[data-export],[data-signout]");
  if (!t) return;
  const d = t.dataset;
  if (d.fab !== undefined) {
    const box = document.querySelector(".fabs");
    const open = !box.classList.contains("open");
    ui.fab = open;
    box.classList.toggle("open", open);
    box.querySelector(".fab").setAttribute("aria-expanded", String(open));
    return;
  }
  if (d.go) return go(d.go);
  if (d.day) {
    ui.day = d.day === P.today() ? null : d.day;
    return render();
  }
  if (d.pick) {
    ui.day = d.pick === P.today() ? null : d.pick;
    return go("day");
  }
  if (d.sheet) {
    ui.fab = false;
    ui.sheet = d.sheet;
    ui.weigh = null;
    render();
    const input = document.querySelector(".sheet input[name=title], .sheet input[name=kg]");
    if (input && d.sheet !== "weigh") input.focus();
    return;
  }
  if (d.edit) {
    ui.sheet = "edit:" + d.edit;
    return render();
  }
  if (d.close !== undefined) {
    ui.sheet = null;
    return render();
  }
  if (d.delete) {
    store.remove("calorie.entry", d.delete);
    ui.sheet = null;
    return toast("Deleted");
  }
  if (d.kg) {
    const input = document.querySelector(".sheet input[name=kg]");
    const v = Math.round((Number(String(input.value).replace(",", ".")) + Number(d.kg)) * 10) / 10;
    input.value = v.toFixed(1);
    ui.weigh = v;
    return;
  }
  if (d.share) {
    const p = plan();
    savePlan({ ...p, watchShare: Math.max(0, Math.min(1, Math.round(p.watchShare * 100 + Number(d.share)) / 100)) });
    return;
  }
  if (d.sync !== undefined) {
    await store.syncNow();
    return toast(store.snapshot().problem || "Synced");
  }
  if (d.export !== undefined) {
    const blob = new Blob([JSON.stringify(store.exportDocuments(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `misura-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    return;
  }
  if (d.signout !== undefined) {
    if (confirm("Disconnect this device? Anything not yet uploaded is lost.")) store.disconnect();
  }
});

document.addEventListener("change", (e) => {
  const t = e.target;
  if (t.dataset.flag) {
    const p = plan();
    savePlan({ ...p, [t.dataset.flag]: t.checked });
    return;
  }
  if (t.dataset.device !== undefined) {
    store.setDevice(t.value);
    return;
  }
  if (t.name === "slot" || t.name === "pace") {
    t.closest(".chips, .seg")
      .querySelectorAll("label")
      .forEach((l) => l.classList.toggle("on", l.contains(t)));
  }
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const form = e.target;
  const kind = form.dataset.form;
  const f = new FormData(form);
  if (kind === "server") {
    const fromLink = parseLink(f.get("link") || "");
    const url = fromLink?.url || f.get("url");
    const key = fromLink?.key || f.get("key");
    if (!url || !key) {
      ui.setupError = "Paste the whole setup link, or both Supabase values.";
      return render();
    }
    ui.setupError = "";
    store.configure(url, key);
    return;
  }
  if (kind === "plan" || kind === "settings") {
    const next = readPlan(form, plan());
    if (!next) {
      ui.setupError = "Check the numbers and dates.";
      return render();
    }
    ui.setupError = "";
    savePlan(P.withDefaults(next));
    if (kind === "settings") toast("Saved");
    return;
  }
  if (kind === "entry") {
    let title = String(f.get("title") || "").trim();
    let kcal = Number(String(f.get("kcal") || "").replace(",", "."));
    if (!kcal) {
      const q = P.parseQuick(title);
      if (q) {
        title = q.title;
        kcal = q.kcal;
      }
    }
    if (!(kcal > 0 && kcal < 20000)) return form.querySelector("input[name=kcal]").focus();
    const m = data();
    const id = form.dataset.id;
    const old = id ? store.get("calorie.entry", id) : null;
    const entryKind = form.dataset.kind;
    const entry = {
      ...(old || {}),
      id: id || store.uuid(),
      day: old ? old.day : shown(m),
      kind: entryKind,
      title: title || (entryKind === "workout" ? "Workout" : "Meal"),
      kcal: Math.round(kcal),
      at: old ? old.at : isoNow(),
      updated: isoNow(),
    };
    if (entryKind === "meal") entry.slot = f.get("slot") || P.slotNow();
    else delete entry.slot;
    store.put("calorie.entry", entry.id, entry);
    ui.sheet = null;
    return render();
  }
  if (kind === "weigh") {
    const v = Math.round(Number(String(f.get("kg") || "").replace(",", ".")) * 10) / 10;
    if (!(v >= 25 && v <= 400)) return;
    const k = shown(data());
    store.put("calorie.weight", k, { id: k, day: k, kg: v, updated: isoNow() });
    ui.sheet = null;
    ui.weigh = null;
    return render();
  }
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
  if (active && active.matches && active.matches("input, select, textarea")) return;
  render();
}

readSetupLink();
store.subscribe(onStore);
render();
setInterval(() => {
  if (!ui.sheet && !(document.activeElement && document.activeElement.matches("input, select"))) render();
}, 60000);
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
