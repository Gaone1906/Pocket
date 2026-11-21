import * as store from "./store.js";
import { $, esc, ICONS, enso, readLocal, writeLocal, dayTitle, shiftDay, weekStart, spanDays, isoWeekday, parseDay, dayKey, uuid, isoNow } from "./util.js";
import * as R from "./routines.js";
import { beatsForSteps, estimate, clock, minutes, split, runOf, plainDetail, breath } from "../ventus/plan.js";

const RUN_KEY = "zenda.run.v1";
const SLOT_ICON = { morning: ICONS.sun, night: ICONS.moon };
const SLOT_NAME = { morning: "Morning", night: "Night" };
const LETTERS = ["M", "T", "W", "T", "F", "S", "S"];
const BREATH_LABEL = ["In", "Hold", "Out", "Hold"];
const BOOK_STYLE = ["a", "b", "c", "a", "b", "d"];
const SPINE_H = [104, 88, 96, 92, 84, 86];
const TAG_TITLE = { gratitude: "Gratitude", win: "Wins", script: "Script", action: "Action", review: "Review", note: "Note" };
const BOX_INNER = 234;
const BOX_CORNERS = [
  [0, 1],
  [0, 0],
  [1, 0],
  [1, 1],
];

const ui = {
  view: "today",
  menu: false,
  sel: null,
  selDay: null,
  weekAnchor: null,
  sheet: null,
  startProj: {},
  scope: "all",
  range: "All",
  bookTag: "gratitude",
  bookDay: null,
  bookFrom: "review",
  goto: false,
  setupError: "",
  toast: "",
};

let run = loadRun();
let lock = null;
let audio = null;
let writeTimer = null;

const pref = (k, d) => readLocal("zenda." + k, d) === "1";
const setPref = (k, on) => writeLocal("zenda." + k, on ? "1" : "0");
const list = (v) => (Array.isArray(v) ? v : []);

function loadRun() {
  try {
    const saved = JSON.parse(readLocal(RUN_KEY, "null"));
    if (saved && saved.day && (saved.routineId || saved.adhoc)) return saved;
  } catch (e) {}
  return null;
}

function saveRun() {
  writeLocal(RUN_KEY, run ? JSON.stringify(run) : null);
}

function session() {
  if (!run) return null;
  let routine;
  let steps;
  if (run.adhoc) {
    routine = { id: "zenda", name: "Zenda" };
    steps = run.steps || [];
  } else {
    routine = R.routine(run.routineId);
    if (!routine) return null;
    steps = R.stepsOn(routine, run.day, run.slot);
  }
  const beats = beatsForSteps(steps, run.day);
  return { routine, steps, beats, beat: beats[run.i] };
}

function chime(strong) {
  if (!pref("sound", "1")) return;
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    const notes = strong ? [523, 784] : [660];
    notes.forEach((f, i) => {
      const o = audio.createOscillator();
      const g = audio.createGain();
      o.type = "sine";
      o.frequency.value = f;
      const t = audio.currentTime + i * 0.22;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.25, t + 0.03);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.9);
      o.connect(g).connect(audio.destination);
      o.start(t);
      o.stop(t + 0.95);
    });
  } catch (e) {}
  try {
    navigator.vibrate && navigator.vibrate(strong ? [120, 80, 120] : 90);
  } catch (e) {}
}

async function keepAwake(on) {
  try {
    if (on && !lock && navigator.wakeLock) lock = await navigator.wakeLock.request("screen");
    if (!on && lock) {
      await lock.release();
      lock = null;
    }
  } catch (e) {}
}

function iconFor(step) {
  const r = runOf(step);
  const n = String(step.title || "").toLowerCase();
  if (r.type === "box") return ICONS.box;
  if (r.type === "say" || /affirm/.test(n)) return ICONS.voice;
  if (r.type === "write") return ICONS.pen;
  if (r.type === "timed" && (list(r.reads).length || /visual/.test(n))) return ICONS.eye;
  if (r.type === "timed") return ICONS.wave;
  return ICONS.dot;
}

function freshRun(base) {
  return { ...base, i: 0, started: Date.now(), stepStarted: Date.now(), spent: {}, paused: false, left: null, endsAt: null, say: { line: 0, said: 0 }, hide: false };
}

function startSession(routineId, day, slot) {
  const routine = R.routine(routineId);
  if (!routine) return;
  const steps = R.stepsOn(routine, day, slot);
  const beats = beatsForSteps(steps, day);
  const first = steps.findIndex((s) => !R.isDone(routineId, day, slot, s.id));
  const i = Math.max(0, beats.findIndex((b) => b.step === (first < 0 ? 0 : first)));
  run = freshRun({ routineId, day, slot });
  run.i = i;
  enterBeat(beats[i], true);
  begin();
}

function startAdhoc(step) {
  run = freshRun({ adhoc: true, day: R.today(), slot: "", steps: [step] });
  enterBeat(beatsForSteps([step], run.day)[0], true);
  begin();
}

function begin() {
  ui.view = "run";
  keepAwake(true);
  if (audio && audio.state === "suspended") audio.resume();
  render();
}

function enterBeat(beat, newStep) {
  if (!beat) return;
  run.say = { line: 0, said: 0 };
  if (newStep) run.stepStarted = Date.now();
  run.paused = false;
  const counted = beat.kind === "count" || beat.kind === "rest";
  run.left = counted ? beat.seconds : null;
  run.endsAt = counted ? Date.now() + beat.seconds * 1000 : null;
  saveRun();
}

function completeStep(s, index) {
  const step = s.steps[index];
  if (!step) return;
  run.spent[index] = (run.spent[index] || 0) + Math.round((Date.now() - run.stepStarted) / 1000);
  if (!run.adhoc) R.tick(s.routine.id, run.day, run.slot, step.id);
}

function advance() {
  const s = session();
  if (!s) return endRun();
  const cur = s.beat;
  const next = s.beats[run.i + 1];
  if (cur && (!next || next.step !== cur.step)) completeStep(s, cur.step);
  if (!next) {
    run.finished = Date.now();
    saveRun();
    ui.view = "done";
    keepAwake(false);
    chime(true);
    render();
    return;
  }
  run.i += 1;
  enterBeat(next, next.step !== cur.step);
  if (!cur.quiet) chime(false);
  render();
}

function togglePause() {
  if (!run) return;
  if (run.paused) {
    run.paused = false;
    run.stepStarted = Date.now() - (run.pausedUsed || 0);
    if (run.left != null) run.endsAt = Date.now() + run.left * 1000;
  } else {
    run.paused = true;
    run.pausedUsed = Date.now() - run.stepStarted;
    if (run.endsAt) run.left = Math.max(0, (run.endsAt - Date.now()) / 1000);
    run.endsAt = null;
  }
  saveRun();
  render();
}

function endRun() {
  run = null;
  saveRun();
  keepAwake(false);
  ui.view = "today";
  render();
}

function remaining() {
  if (!run) return 0;
  if (run.endsAt) return Math.max(0, (run.endsAt - Date.now()) / 1000);
  return run.left ?? 0;
}

function softLeft(beat) {
  if (!beat || !beat.guide) return null;
  const used = run.paused ? (run.pausedUsed || 0) / 1000 : (Date.now() - run.stepStarted) / 1000;
  return Math.max(0, beat.guide - used);
}

function sessionLeft(s) {
  let total = 0;
  s.steps.forEach((step, i) => {
    if (i > s.beat.step) total += estimate(step);
  });
  const here = s.beats.filter((b, i) => i > run.i && b.step === s.beat.step).reduce((n, b) => n + (b.seconds || 0), 0);
  const now = run.left != null ? remaining() : softLeft(s.beat) || 0;
  return total + here + now;
}

function stepPct(s) {
  const b = s.beat;
  if (run.left != null && b.seconds) return Math.round((1 - remaining() / b.seconds) * 100);
  if (b.kind === "say") {
    const lines = Math.max(1, b.lines.length);
    return Math.round(((run.say.line * b.times + run.say.said) / (lines * b.times)) * 100);
  }
  if (b.guide) return Math.min(100, Math.round(((Date.now() - run.stepStarted) / 1000 / b.guide) * 100));
  return 40;
}

function ballAt(b) {
  const p = breath(b.box, b.seconds - remaining());
  const a = BOX_CORNERS[p.index];
  const z = BOX_CORNERS[(p.index + 1) % 4];
  return { ...p, x: (a[0] + (z[0] - a[0]) * p.fraction) * BOX_INNER - 1.5, y: (a[1] + (z[1] - a[1]) * p.fraction) * BOX_INNER - 1.5 };
}

function readNow(b) {
  if (!b.reads || !b.reads.length) return null;
  const used = Math.max(0, b.seconds - remaining());
  const index = Math.floor(used / (b.every || 20)) % b.reads.length;
  return { text: b.reads[index], index };
}

function cueNow(beat) {
  if (!beat.cues || !beat.cues.length) return null;
  const used = beat.seconds - remaining();
  let cue = null;
  for (const c of beat.cues) if (used >= c.at) cue = c;
  return cue;
}

function topBar(s) {
  const segs = s.steps
    .map((step, i) => {
      const done = i < s.beat.step;
      const cur = i === s.beat.step;
      return `<div class="seg ${done ? "past" : cur ? "" : "next"}" aria-label="${esc(split(step.title).name)}">${iconFor(step)}<div class="b"><i ${cur ? "data-segbar" : ""} style="width:${done ? 100 : cur ? stepPct(s) : 0}%"></i></div></div>`;
    })
    .join("");
  return `<div class="runbar"><button class="circle" data-end aria-label="End session">${ICONS.close}</button><div class="segs">${segs}</div><span class="left" data-left>${clock(sessionLeft(s))}</span></div>`;
}

function controls(s, extra = "", small = false) {
  return `<div class="ctrls ${small ? "small" : ""}">${extra}<button class="p" data-pause aria-label="${run.paused ? "Resume" : "Pause"}">${run.paused ? ICONS.resume : ICONS.pause}</button><button class="n" data-skip aria-label="Next step">${ICONS.next}</button></div>`;
}

function boxStage(s) {
  const b = s.beat;
  const at = ballAt(b);
  return `<div class="stage"><div class="boxer"><span class="ball" data-ball style="left:${at.x.toFixed(1)}px;top:${at.y.toFixed(1)}px"></span><span class="lbl" data-phase>${BREATH_LABEL[at.index]}</span><span class="num" data-count>${at.left}</span></div><div class="phases" aria-hidden="true">${[0, 1, 2, 3].map((i) => `<i data-phasebar="${i}" class="${i === at.index ? "on" : ""}"></i>`).join("")}</div></div>${controls(s)}`;
}

function isVisual(b) {
  return (b.reads && b.reads.length > 0) || /visuali/i.test(b.name);
}

function visualStage(s) {
  const b = s.beat;
  const read = readNow(b);
  const tipLine = !read && b.tip ? b.tip : "";
  const dots = read ? `<div class="dots" aria-label="Line ${read.index + 1} of ${b.reads.length}">${b.reads.map((_, i) => `<i class="${i < read.index ? "past" : i === read.index ? "now" : ""}"></i>`).join("")}</div>` : "";
  const cue = cueNow(b);
  const eye = run.hide ? ICONS.eyeoff : ICONS.eye;
  return `<div class="stage">${enso(330, 0.13, "position:absolute")}<div class="vis"><span class="kick">${esc(split(b.detail || "").name || b.name)}</span>${run.hide ? "" : read ? `<p data-read>${esc(read.text).replace(/\n/g, "<br>")}</p>` : cue ? `<p>${esc(cue.text)}</p>` : tipLine ? `<p style="font-size:19px">${esc(tipLine)}</p>` : ""}${dots}</div></div>${controls(s, `<button class="g" data-hide aria-label="Hide lines">${eye}</button>`)}`;
}

function calmStage(s) {
  const b = s.beat;
  const cue = cueNow(b);
  return `<div class="stage"><span class="kick">${esc(b.name)}</span><div class="clockbig" data-clock>${clock(remaining())}</div>${cue ? `<p class="cue" data-cue>${esc(cue.text)}</p>` : b.tip ? `<p class="tiptext">${esc(b.tip)}</p>` : ""}</div>${controls(s)}`;
}

function sayStage(s) {
  const b = s.beat;
  const lines = b.lines.length ? b.lines : [b.detail || b.name];
  const at = Math.min(run.say.line, lines.length - 1);
  return `<div class="stage"><div class="aff"><span class="kick">${at + 1} / ${lines.length}</span><p>${esc(lines[at])}</p><svg width="200" height="12" viewBox="0 0 260 14" aria-hidden="true"><path d="M4 9C60 3 170 2 256 6C190 9 90 12 10 13Z" fill="#2B2926" opacity="0.18" stroke="none"/></svg><div class="said" aria-label="Said ${run.say.said} of ${b.times} times">${Array.from({ length: b.times }, (_, i) => `<i class="${i < run.say.said ? "on" : ""}"></i>`).join("")}</div></div></div><button class="saybtn" data-said>${ICONS.check}Said it</button>${controls(s, "", true)}`;
}

function entryBase(s) {
  const step = s.steps[s.beat.step];
  const parts = split(step.title);
  const tag = s.beat.tag || "note";
  const title = [parts.name, plainDetail(parts.detail)].filter(Boolean).join(" · ");
  if (run.adhoc) return { id: R.entryId("zenda", run.day, "adhoc", step.id), routine: "zenda", routineName: "Zenda", day: run.day, slot: "", step: step.id, title, tag };
  return { id: R.entryId(s.routine.id, run.day, run.slot, step.id), routine: s.routine.id, routineName: s.routine.name, day: run.day, slot: run.slot, step: step.id, title, tag };
}

function writeStage(s) {
  const b = s.beat;
  const base = entryBase(s);
  const saved = R.entry(base.id) || {};
  const rows = b.fields > 1 ? b.fields : 0;
  const title = TAG_TITLE[b.tag] || b.name;
  const body = rows
    ? Array.from({ length: rows }, (_, i) => `<label class="jrow"><b>${i + 1}</b><input data-line="${i}" value="${esc((saved.lines || [])[i] || "")}" aria-label="Line ${i + 1}" autocomplete="off"></label>`).join("")
    : `<textarea class="para" data-para aria-label="Your writing" placeholder="${esc(b.prompt || "")}">${esc(saved.text || "")}</textarea>`;
  return `<article class="journal">
    <div class="jh">${ICONS.pen}<h1>${esc(title)}</h1><span class="jd">${ICONS.moon}${esc(dayTitle(run.day, { day: "numeric", month: "short" }))}</span></div>
    ${body}
  </article>
  <div class="jfoot"><button class="circle" data-book="${esc(b.tag)}" aria-label="Open the ${esc(title)} book">${ICONS.book}</button><button class="save" data-skip>Save${ICONS.arrow}</button></div>`;
}

function tapStage(s) {
  const b = s.beat;
  return `<div class="stage"><div class="tapcard"><h2>${esc(b.name)}</h2>${b.detail ? `<p class="sub">${esc(b.detail)}</p>` : ""}${b.tip ? `<p class="tiptext">${esc(b.tip)}</p>` : ""}</div></div><button class="primary arrow" data-skip>${ICONS.check}Done</button>`;
}

function viewRun() {
  const s = session();
  if (!s || !s.beat) {
    run = null;
    saveRun();
    return shell(viewToday());
  }
  const b = s.beat;
  let body;
  if (b.kind === "count" && b.box) body = boxStage(s);
  else if (b.kind === "count" && isVisual(b)) body = visualStage(s);
  else if (b.kind === "count") body = calmStage(s);
  else if (b.kind === "say") body = sayStage(s);
  else if (b.kind === "write") body = writeStage(s);
  else body = tapStage(s);
  return `<main class="run">${topBar(s)}${body}</main>`;
}

function viewDone() {
  const s = session();
  if (!s) return shell(viewToday());
  const ticked = run.adhoc ? s.steps.length : s.steps.filter((st) => R.isDone(s.routine.id, run.day, run.slot, st.id)).length;
  return `<main class="run"><div class="donewrap">${enso(220, 0.1, "position:absolute")}<div class="bigcheck">${ICONS.check}</div><h1 style="font-size:30px">${ticked < s.steps.length ? "Stopped early" : "Done"}</h1><div class="donelist">${s.steps.map((st, i) => `<div class="step ${i === s.steps.length - 1 ? "last" : ""}">${iconFor(st)}<span>${esc(split(st.title).name)}</span><b class="mins">${run.spent[i] ? clock(run.spent[i]) : ""}</b></div>`).join("")}</div></div><button class="primary" data-home>Back to today</button></main>`;
}

function slotChips(routineId, day) {
  const out = R.projects().filter((p) => p.routine === routineId && R.applies(p, day));
  return out.map((p) => `<span class="pchip">${esc(R.shortName(p))} · day ${R.dayOf(p, day).n}</span>`).join("");
}

function stepRows(steps, withLast = true) {
  return steps.map((st, i) => `<div class="step ${i === steps.length - 1 && withLast ? "last" : ""}">${iconFor(st)}<span>${esc(split(st.title).name)}</span><b class="mins">${minutes(estimate(st))}</b></div>`).join("");
}

function totalMinutes(steps) {
  return minutes(steps.reduce((t, st) => t + estimate(st), 0));
}

function sessionDayStatus(day) {
  const all = R.sessions(day);
  return { planned: all.length, done: all.filter((x) => x.done === x.total).length };
}

function streakFor(sessionsOf, from) {
  let n = 0;
  let d = R.today();
  let first = true;
  for (let guard = 0; guard < 800 && d >= from; guard++) {
    const xs = sessionsOf(d);
    if (xs.length) {
      const done = xs.every((x) => x.done === x.total);
      if (done) n++;
      else if (!first) break;
    }
    first = false;
    d = shiftDay(d, -1);
  }
  return n;
}

function earliest() {
  const starts = [...R.routines().map((r) => r.starts), ...R.projects().map((p) => p.start)].filter(Boolean).sort();
  return starts[0] || R.today();
}

function viewToday() {
  const day = R.today();
  const all = R.sessions(day);
  const slot = R.slotNow();
  const open = all.filter((x) => x.done < x.total);
  const next = open.find((x) => x.slot === slot) || open[0];
  const streak = streakFor((d) => R.sessions(d), earliest());
  const st = store.snapshot();
  const cards = all
    .map((x) => {
      const chips = `<span class="chipset">${slotChips(x.routine.id, day)}</span>`;
      if (x.done === x.total) return `<section class="session done"><span class="ic">${SLOT_ICON[x.slot]}</span><h2>${SLOT_NAME[x.slot]}</h2>${chips}<span class="tick">${ICONS.check}</span></section>`;
      const head = `<div class="top"><span class="ic">${SLOT_ICON[x.slot]}</span><h2>${SLOT_NAME[x.slot]}</h2>${chips}${x === next ? "" : `<button class="ghostlink" data-start="${x.routine.id}|${x.slot}">Start</button>`}</div>`;
      const foot = x === next ? `<button class="primary" data-start="${x.routine.id}|${x.slot}">${ICONS.play}${x.done ? "Continue" : "Start"} · ${totalMinutes(x.steps)} min</button>` : "";
      return `<section class="session" style="${x === next ? "" : "border-width:1px;border-color:var(--line)"}">${head}${stepRows(x.steps, x !== next)}${foot}</section>`;
    })
    .join("");
  const ws = weekStart(day);
  const strip = Array.from({ length: 7 }, (_, i) => {
    const d = shiftDay(ws, i);
    const s = sessionDayStatus(d);
    const kind = s.planned && s.done === s.planned ? "full" : s.done ? "half" : "none";
    return `<div class="wd ${d === day ? "now" : ""}">${LETTERS[i]}<i class="${kind}"></i></div>`;
  }).join("");
  return `<main class="screen">
    ${enso(240, 0.08, "right:-70px;top:10px")}
    <header class="head">
      <img class="logo" src="icon-192.png" alt="Zenda">
      <div class="dayname"><b>${esc(dayTitle(day, { weekday: "long" }))}</b><span>${esc(dayTitle(day, { day: "numeric", month: "short" }))}</span></div>
      <span class="seal" aria-hidden="true">禅</span>
      <div class="streak" aria-label="Streak">${ICONS.flame}${streak}</div>
      <button class="gear" data-view="settings" aria-label="Settings">${ICONS.gear}${st.problem ? "<i></i>" : ""}</button>
    </header>
    ${cards || `<div class="empty">${ICONS.leaf}</div>`}
    <section class="week" aria-label="This week">${strip}</section>
  </main>`;
}

function tabs() {
  const t = [
    ["today", "Today", ICONS.today],
    ["scheduled", "Scheduled", ICONS.calendar],
    ["start", "Start", ICONS.play],
    ["review", "Review", ICONS.bars],
  ];
  return `<nav class="tabs" aria-label="Zenda">${t.map(([k, label, icon]) => `<button class="tab ${ui.view === k ? "on" : ""}" data-view="${k}">${icon}${label}</button>`).join("")}</nav>`;
}

function shell(inner) {
  return inner + tabs();
}

function currentProject() {
  const ps = R.projects();
  if (!ps.length) return null;
  const found = ps.find((p) => p.id === ui.sel);
  if (found) return found;
  const day = R.today();
  return ps.find((p) => R.applies(p, day)) || ps[0];
}

function pickDay(p) {
  const base = ui.weekAnchor || weekStart(R.today());
  const days = Array.from({ length: 7 }, (_, i) => shiftDay(base, i));
  if (ui.selDay && days.includes(ui.selDay)) return ui.selDay;
  const today = R.today();
  if (days.includes(today)) return today;
  return days.find((d) => R.applies(p, d)) || days[0];
}

function viewScheduled() {
  const ps = R.projects();
  const p = currentProject();
  const newBtn = `<button class="round" data-newproject aria-label="New project">${ICONS.plus}</button>`;
  if (!p) return `<main class="screen"><div class="row" style="justify-content:flex-end">${newBtn}</div><div class="empty">${ICONS.leaf}</div></main>`;
  const today = R.today();
  const base = ui.weekAnchor || weekStart(today);
  const selDay = pickDay(p);
  const total = spanDays(p.start, p.end) + 1;
  const n = Math.min(total, Math.max(0, spanDays(p.start, today) + 1));
  const weekNo = Math.floor(spanDays(weekStart(p.start), base) / 7) + 1;
  const lastWeek = weekStart(p.end);
  const fmt = (d) => dayTitle(d, { day: "numeric", month: "short" });
  const r = R.routine(p.routine);
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = shiftDay(base, i);
    const on = R.applies(p, d) && r;
    const am = on && R.stepsOn(r, d, "morning").length;
    const pm = on && R.stepsOn(r, d, "night").length;
    return `<button class="day ${d === selDay ? "sel" : ""} ${d === today ? "now" : ""}" data-day="${d}" aria-label="${esc(dayTitle(d))}"><small>${LETTERS[i]}</small><b>${parseDay(d).getDate()}</b><i class="${am ? "on" : ""}"></i><i class="${pm ? "on" : ""}"></i></button>`;
  }).join("");
  let panel = `<div class="empty">${ICONS.leaf}</div>`;
  if (r && R.applies(p, selDay)) {
    const am = R.stepsOn(r, selDay, "morning");
    const pm = R.stepsOn(r, selDay, "night");
    if (am.length || pm.length) {
      panel = `${am.length ? `<div class="slot">${ICONS.sun}Morning<b>${totalMinutes(am)} min</b></div>${stepRows(am)}` : ""}${pm.length ? `<div class="slot ${am.length ? "second" : ""}">${ICONS.moon}Night<b>${totalMinutes(pm)} min</b></div>${stepRows(pm)}` : ""}`;
    }
  }
  const menu = ui.menu ? `<div class="menu" role="listbox">${ps.map((x) => `<button role="option" data-pick="${esc(x.id)}" class="${x.id === p.id ? "on" : ""}">${esc(x.name)}</button>`).join("")}</div>` : "";
  return `<main class="screen">
    <div class="row" style="position:relative"><button class="pill" data-menu aria-haspopup="listbox"><span>${esc(p.name)}</span>${ICONS.down}</button><span style="margin-left:auto"></span>${newBtn}${menu}</div>
    <section style="display:flex;flex-direction:column;gap:10px">
      <div class="goal">${ICONS.target}<h1>${esc(p.goal || p.name)}</h1></div>
      <div class="dates"><button class="dchip" data-edit="${esc(p.id)}">${esc(fmt(p.start))}</button>${ICONS.right}<button class="dchip" data-edit="${esc(p.id)}">${esc(fmt(p.end))}</button><span class="count">${n}<span> / ${total}</span></span></div>
      <div class="bar"><i style="width:${Math.round((n / total) * 100)}%"></i></div>
    </section>
    <section style="display:flex;flex-direction:column;gap:8px">
      <div class="stepper"><button data-week="-1" aria-label="Previous week" ${base <= weekStart(p.start) ? "disabled" : ""}>${ICONS.left}</button><span>Week ${weekNo}<span> · ${esc(fmt(base))} – ${esc(fmt(shiftDay(base, 6)))}</span></span><button data-week="1" aria-label="Next week" ${base >= lastWeek ? "disabled" : ""}>${ICONS.right}</button></div>
      <div class="days">${days}</div>
    </section>
    <section class="panel">${panel}</section>
  </main>`;
}

function minutePref(k, fallback) {
  return Number(readLocal("zenda.mins." + k, fallback)) || fallback;
}

function startProject(k) {
  const ps = R.projects();
  if (!ps.length) return null;
  const day = R.today();
  return ps.find((p) => p.id === ui.startProj[k]) || ps.find((p) => R.applies(p, day)) || ps[0];
}

function tile(k, icon, name, mins, withProjects) {
  const cur = minutePref(k, mins[1]);
  const p = withProjects ? startProject(k) : null;
  const projRow = withProjects && R.projects().length ? `<div class="chips">${R.projects().map((x) => `<button class="chip proj ${p && x.id === p.id ? "on" : ""}" data-sproj="${k}|${esc(x.id)}">${esc(R.shortName(x))}</button>`).join("")}</div>` : "";
  return `<div class="tile"><div class="big">${icon}</div><div class="tname">${name}</div>${projRow}<div class="chips wrap">${mins.map((m) => `<button class="chip ${m === cur ? "on" : ""}" data-go="${k}|${m}" aria-label="${name} ${m} minutes">${m}</button>`).join("")}</div></div>`;
}

function viewStart() {
  const shelf = R.BOOKS.map(([tag, label], i) => `<button class="bk ${["a", "b", "c", "a"][i % 4]}" data-journal="${tag}">${ICONS.pen}${label}</button>`).join("");
  return `<main class="screen" style="gap:14px">
    <h1 class="title">Start</h1>
    <div class="grid2">
      ${tile("box", ICONS.box, "Box breathing", [2, 4, 8, 12], false)}
      ${tile("visualize", ICONS.eye, "Visualize", [3, 6, 10], true)}
      ${tile("affirm", ICONS.voice, "Affirm", [3, 5, 10], true)}
      ${tile("scan", ICONS.wave, "Body scan", [5, 10, 20], false)}
    </div>
    <div class="tile"><div class="row" style="gap:12px"><div class="big">${ICONS.pen}</div><div class="tname">Journal</div></div><div class="books">${shelf}<button class="bk d" data-journal="note">${ICONS.pen}Blank</button></div></div>
  </main>`;
}

function planKey(isoDay) {
  return (isoDay % 7) + 1;
}

function allSteps(r) {
  return ["morning", "night"].flatMap((slot) => Object.keys(r.plan || {}).filter((k) => k.endsWith("-" + slot)).flatMap((k) => list(r.plan[k])));
}

function findStep(test, p) {
  const today = isoWeekday(R.today());
  if (p) {
    const r = R.routine(p.routine);
    if (r) {
      const wds = [...(p.days.includes(today) ? [today] : []), ...p.days];
      for (const wd of wds) {
        for (const slot of ["morning", "night"]) {
          const hit = list(r.plan && r.plan[`${planKey(wd)}-${slot}`]).find(test);
          if (hit) return hit;
        }
      }
    }
  }
  for (const r of R.routines()) {
    const hit = allSteps(r).find(test);
    if (hit) return hit;
  }
  return null;
}

const isVisualStep = (s) => (runOf(s).type === "timed" && list(runOf(s).reads).length > 0) || /visuali/i.test(s.title || "");
const isAffirmStep = (s) => runOf(s).type === "say" || /affirm/i.test(s.title || "");
const isScanStep = (s) => /body scan/i.test(s.title || "") || (runOf(s).type === "timed" && runOf(s).quiet);
const isBoxStep = (s) => runOf(s).type === "box";

function quoted(tip) {
  return [...String(tip || "").matchAll(/"([^"]{6,})"/g)].map((m) => m[1]);
}

function adhocStep(kind, minutesChosen, arg) {
  const seconds = minutesChosen * 60;
  if (kind === "box") {
    const found = findStep(isBoxStep, null);
    const base = found ? runOf(found) : {};
    return { id: uuid(), title: "Box breathing", tip: "", run: { type: "box", pattern: base.pattern, seconds, cues: [] } };
  }
  if (kind === "scan") {
    const found = findStep(isScanStep, null);
    const base = found ? runOf(found) : {};
    return { id: uuid(), title: "Body scan", tip: found ? found.tip || "" : "", run: { type: "timed", quiet: true, seconds, cues: base.cues || [] } };
  }
  const p = startProject(kind);
  if (kind === "visualize") {
    const found = findStep(isVisualStep, p);
    const base = found ? runOf(found) : {};
    return { id: uuid(), title: "Visualize" + (p ? ` | ${p.name}` : ""), tip: found ? found.tip || "" : "", run: { type: "timed", seconds, reads: base.reads || [], pick: base.pick, every: base.every, cues: base.cues || [] } };
  }
  if (kind === "affirm") {
    const found = findStep(isAffirmStep, p);
    const base = found ? runOf(found) : {};
    const lines = list(base.lines).length || list(base.pool).length ? list(base.lines) : found ? quoted(found.tip) : [];
    return { id: uuid(), title: "Affirm" + (p ? ` | ${p.name}` : ""), tip: "", run: { type: "say", lines, pool: base.pool, pick: base.pick, times: base.times || 3, seconds } };
  }
  const writer = findStep((s) => runOf(s).type === "write" && runOf(s).tag === arg, null);
  const base = writer ? runOf(writer) : {};
  const fields = base.fields != null ? base.fields : arg === "gratitude" || arg === "win" ? 3 : 0;
  const label = (R.BOOKS.find((b) => b[0] === arg) || [0, "Journal"])[1];
  return { id: uuid(), title: arg === "note" ? "Note" : label, tip: writer ? writer.tip || "" : "", run: { type: "write", tag: arg, fields, prompt: base.prompt || "" } };
}

function reviewScope() {
  const ps = R.projects();
  if (ui.scope !== "all") {
    const p = ps.find((x) => x.id === ui.scope);
    if (p) return [p];
  }
  return ps;
}

function viewReview() {
  const ps = R.projects();
  const scope = reviewScope();
  const today = R.today();
  const sessionsOf = (d) => (scope.length ? R.scopeSessions(scope, d, d) : R.sessions(d));
  const starts = scope.map((p) => p.start).sort();
  const ends = scope.map((p) => p.end).sort();
  const origin = starts[0] || earliest();
  let from = origin;
  if (ui.range === "W") from = weekStart(today);
  else if (ui.range === "M") from = today.slice(0, 8) + "01";
  if (from < origin) from = origin;
  const to = today;
  const rangeSessions = [];
  const minutesPerDay = [];
  for (let d = from; d <= to; d = shiftDay(d, 1)) {
    const xs = sessionsOf(d);
    rangeSessions.push(...xs);
    const mins = xs.reduce((t, x) => t + x.steps.filter((s) => R.isDone(x.routine.id, x.day, x.slot, s.id)).reduce((a, s) => a + estimate(s), 0), 0);
    minutesPerDay.push([d, Math.round(mins / 60)]);
  }
  const done = rangeSessions.filter((x) => x.done === x.total).length;
  const seconds = rangeSessions.reduce((t, x) => t + x.steps.filter((s) => R.isDone(x.routine.id, x.day, x.slot, s.id)).reduce((a, s) => a + estimate(s), 0), 0);
  const routineIds = new Set(scope.map((p) => p.routine));
  const entryCount = R.entries().filter((e) => e.day >= from && e.day <= to && (ui.scope === "all" || routineIds.has(e.routine) || e.routine === "zenda")).length;
  const streak = streakFor(sessionsOf, origin);
  const heatFrom = origin;
  const heatTo = ends[ends.length - 1] || today;
  const lead = isoWeekday(heatFrom) - 1;
  const total = spanDays(heatFrom, heatTo) + 1;
  const cols = Math.ceil((total + lead) / 7);
  let cells = Array.from({ length: lead }, () => `<span style="visibility:hidden"></span>`).join("");
  for (let i = 0; i < total; i++) {
    const d = shiftDay(heatFrom, i);
    let cls = "";
    if (d <= today) {
      const xs = sessionsOf(d);
      if (xs.length) {
        const dn = xs.filter((x) => x.done === x.total).length;
        cls = dn === xs.length ? "d2" : dn ? "d1" : "d0";
      }
    }
    cells += `<span class="${cls} ${d === today ? "t" : ""}"></span>`;
  }
  const adherence = ps
    .filter((p) => ui.scope === "all" || p.id === ui.scope)
    .map((p) => {
      const xs = R.projectSessions(p, p.start, today > p.end ? p.end : today);
      const dn = xs.filter((x) => x.done === x.total).length;
      return `<div class="adh"><b>${esc(R.shortName(p))}</b><div class="bar"><i style="width:${xs.length ? Math.round((dn / xs.length) * 100) : 0}%"></i></div><em>${dn}/${xs.length}</em></div>`;
    })
    .join("");
  const recent = minutesPerDay.slice(-21);
  const top = Math.max(1, ...recent.map((x) => x[1]));
  const bars = recent.map(([d, m]) => `<span class="${m ? "" : "z"}" style="height:${m ? Math.max(6, Math.round((m / top) * 100)) : 3}%" title="${esc(d)} ${m}"></span>`).join("");
  const shelf = R.BOOKS.map(([tag, label], i) => {
    const days = new Set(R.entries(tag).map((e) => e.day)).size;
    return `<button class="spine ${BOOK_STYLE[i]}" style="height:${SPINE_H[i]}px" data-book="${tag}" data-from="review" aria-label="${label}"><b>${days}</b><span>${label}</span></button>`;
  }).join("");
  const menu = ui.menu ? `<div class="menu" role="listbox"><button data-scope="all" class="${ui.scope === "all" ? "on" : ""}">All projects</button>${ps.map((x) => `<button data-scope="${esc(x.id)}" class="${ui.scope === x.id ? "on" : ""}">${esc(x.name)}</button>`).join("")}</div>` : "";
  const label = ui.scope === "all" || !scope.length ? "All projects" : scope[0].name;
  return `<main class="screen" style="gap:12px">
    <div class="row" style="position:relative;gap:8px"><button class="pill" style="height:40px" data-menu><span>${esc(label)}</span>${ICONS.down}</button><div class="seg3" role="tablist">${["W", "M", "All"].map((r) => `<button role="tab" data-range="${r}" class="${ui.range === r ? "on" : ""}" aria-selected="${ui.range === r}">${r}</button>`).join("")}</div>${menu}</div>
    <div class="stats">
      <div class="stat">${ICONS.flame}<div><b>${streak}</b><small>streak</small></div></div>
      <div class="stat">${ICONS.check}<div><b>${done}<span>/${rangeSessions.length}</span></b><small>sessions</small></div></div>
      <div class="stat">${ICONS.today}<div><b>${(seconds / 3600).toFixed(1)}<span>h</span></b><small>present</small></div></div>
      <div class="stat">${ICONS.pen}<div><b>${entryCount}</b><small>entries</small></div></div>
    </div>
    <section class="card" aria-label="Days"><div class="heat" style="grid-template-columns:repeat(${cols},minmax(0,1fr))">${cells}</div><div class="heatlabels"><span>${esc(dayTitle(heatFrom, { day: "numeric", month: "short" }))}</span><span>${esc(dayTitle(heatTo, { day: "numeric", month: "short" }))}</span></div></section>
    ${adherence ? `<section class="card" aria-label="Projects">${adherence}</section>` : ""}
    <section class="card" aria-label="Minutes per day"><div class="mpd">${bars}</div></section>
    <section class="card" aria-label="Books" style="padding-bottom:12px"><div class="shelf">${shelf}</div><div class="shelfbar" aria-hidden="true"></div></section>
  </main>`;
}

function bookPages(tag) {
  const byDay = new Map();
  for (const e of R.entries(tag)) {
    if (!byDay.has(e.day)) byDay.set(e.day, []);
    byDay.get(e.day).push(e);
  }
  return [...byDay.keys()].sort().map((d) => ({ day: d, entries: byDay.get(d) }));
}

function viewBook() {
  const tag = ui.bookTag;
  const pages = bookPages(tag);
  let at = pages.findIndex((p) => p.day === ui.bookDay);
  if (at < 0) at = pages.length - 1;
  const page = pages[at];
  const chips = R.BOOKS.map(([t, label]) => `<button class="bkchip ${t === tag ? "on" : ""}" data-booktag="${t}">${label}</button>`).join("");
  let article = `<article class="page"><div class="empty">${ICONS.leaf}</div></article>`;
  if (page) {
    const order = { morning: 0, night: 1 };
    const sorted = [...page.entries].sort((a, b) => (order[a.slot] ?? 2) - (order[b.slot] ?? 2));
    const proj = R.projects().find((p) => R.applies(p, page.day) && sorted.some((e) => e.routine === p.routine));
    const sections = sorted
      .map((e) => {
        const lines = e.lines ? e.lines.filter((l) => String(l).trim()) : String(e.text || "").trim() ? [String(e.text).trim()] : [];
        const head = SLOT_ICON[e.slot] ? `<div class="slot">${SLOT_ICON[e.slot]}${SLOT_NAME[e.slot]}</div>` : "";
        return head + lines.map((l, i) => `<div class="ln"><b>${e.lines ? i + 1 : ""}</b><span>${esc(l)}</span></div>`).join("");
      })
      .join("");
    article = `<article class="page"><div class="ph"><h2>${esc(dayTitle(page.day, { weekday: "short", day: "numeric", month: "short" }))}</h2><span>${proj ? esc(R.shortName(proj)) : ""}</span></div>${sections}<div class="pageno">${at + 1}</div></article>`;
  }
  return `<main class="screen bookscreen" style="gap:0">
    <div class="row pad" style="padding:0 20px"><button class="circle" data-bookback aria-label="Back">${ICONS.left}</button><button class="circle" style="margin-left:auto" data-goto aria-label="Go to date">${ICONS.calendar}</button></div>
    ${ui.goto ? `<div class="goto"><input type="date" data-gotodate aria-label="Go to date" min="${esc(pages[0] ? pages[0].day : "")}" max="${esc(pages.length ? pages[pages.length - 1].day : "")}"></div>` : ""}
    <div class="bkchips">${chips}</div>
    ${article}
    <div class="flip"><button data-flip="-1" aria-label="Previous page" ${at <= 0 ? "disabled" : ""}>${ICONS.left}</button><button data-flip="1" aria-label="Next page" ${at >= pages.length - 1 ? "disabled" : ""}>${ICONS.right}</button></div>
  </main>`;
}

function viewSettings() {
  const st = store.snapshot();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  const state = st.problem ? "Problem" : store.pendingCount() ? "Uploading" : "Synced";
  return `<main class="screen">
    <div class="row"><button class="circle" data-view="today" aria-label="Back">${ICONS.left}</button><h1 style="font-size:26px">Settings</h1></div>
    <div class="card">
      <div class="opt"><span>Sync</span><small>${state}${last ? " · " + esc(last.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })) : ""}</small></div>
      <div class="opt"><span>Waiting to upload</span><small>${store.pendingCount()}</small></div>
      <div class="opt"><span>This device</span><input class="inline" data-device value="${esc(st.device)}" aria-label="Device name"></div>
      <div class="opt"><span>Chime</span><input type="checkbox" class="switch" data-pref="sound" ${pref("sound", "1") ? "checked" : ""}></div>
      ${st.problem ? `<div class="warn">${esc(st.problem)}</div>` : ""}
      <div class="btnrow"><button class="btn" data-sync>Sync now</button><button class="btn" data-export>Download a copy</button><button class="btn danger" data-signout>Disconnect</button></div>
    </div>
  </main>`;
}

function viewSetup() {
  return `<main class="screen setup">
    <div class="row" style="gap:14px"><img class="logo" src="icon-192.png" alt="Zenda"><h1 style="font-size:30px">Zenda</h1></div>
    <form data-form="server">
      <input name="link" placeholder="https://gaone1906.github.io/Pocket/zenda/#connect=…" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
      <details><summary>Or enter the Supabase values</summary>
        <input name="url" placeholder="Project URL (https://xxxx.supabase.co)" autocomplete="off" autocapitalize="off" aria-label="Project URL">
        <input name="key" placeholder="Anon public key" autocomplete="off" autocapitalize="off" aria-label="Anon public key">
      </details>
      <button class="primary">Continue</button>
    </form>
    ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
  </main>`;
}

function sheetView() {
  const d = ui.sheet;
  if (!d) return "";
  const routines = R.allRoutines().filter((r) => Object.keys(r.plan || {}).length);
  const wd = [1, 2, 3, 4, 5, 6, 7];
  return `<div class="sheetwrap" data-close-sheet><div class="sheet" role="dialog" aria-label="Project">
    <h2>${d.id ? "Edit project" : "New project"}</h2>
    <label class="field">Name<input data-f="name" value="${esc(d.name)}" autocomplete="off"></label>
    <label class="field">Goal<input data-f="goal" value="${esc(d.goal)}" autocomplete="off"></label>
    <div class="field two"><label>Start<input type="date" data-f="start" value="${esc(d.start)}"></label><label>End<input type="date" data-f="end" value="${esc(d.end)}"></label></div>
    <label class="field">Routine<select data-f="routine">${routines.map((r) => `<option value="${esc(r.id)}" ${r.id === d.routine ? "selected" : ""}>${esc(r.name)}</option>`).join("")}</select></label>
    <div class="wdays">${wd.map((n) => `<button data-wday="${n}" class="${d.days.includes(n) ? "on" : ""}" aria-pressed="${d.days.includes(n)}">${LETTERS[n - 1]}</button>`).join("")}</div>
    ${d.error ? `<div class="warn">${esc(d.error)}</div>` : ""}
    <div class="sheetfoot">${d.id ? `<button class="btn danger" data-delproject>Delete</button>` : `<button class="btn" data-cancel>Cancel</button>`}<button class="btn main" data-saveproject>Save</button></div>
  </div></div>`;
}

function readSheet() {
  if (!ui.sheet) return;
  document.querySelectorAll("[data-f]").forEach((el) => {
    ui.sheet[el.dataset.f] = el.value;
  });
}

function openSheet(p) {
  const routines = R.routines();
  const today = R.today();
  ui.sheet = p
    ? { id: p.id, name: p.name, goal: p.goal || "", start: p.start, end: p.end, routine: p.routine, days: [...(p.days || [])], error: "" }
    : { id: null, name: "", goal: "", start: today, end: shiftDay(today, 180), routine: (routines[0] || R.allRoutines()[0] || {}).id || "", days: [], error: "" };
  render();
}

function saveProject() {
  readSheet();
  const d = ui.sheet;
  const name = d.name.trim();
  if (!name) d.error = "Give it a name.";
  else if (!d.start || !d.end || d.end < d.start) d.error = "End must be after start.";
  else if (!d.days.length) d.error = "Pick at least one day.";
  else if (!d.routine) d.error = "Pick a routine.";
  else d.error = "";
  if (d.error) return render();
  const id = d.id || uuid();
  store.put("zenda.project", id, { id, name, goal: d.goal.trim(), start: d.start, end: d.end, routine: d.routine, days: [...d.days].sort((a, b) => a - b), updated: isoNow() });
  ui.sel = id;
  ui.sheet = null;
  render();
}

function render() {
  const app = $("#app");
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  if (run && ui.view !== "run" && ui.view !== "done" && ui.view !== "book" && !session()) {
    run = null;
    saveRun();
  }
  const prev = app.querySelector(".screen");
  const scroll = prev ? prev.scrollTop : 0;
  const views = {
    today: () => shell(viewToday()),
    scheduled: () => shell(viewScheduled()),
    start: () => shell(viewStart()),
    review: () => shell(viewReview()),
    settings: () => viewSettings(),
    book: () => viewBook(),
    run: viewRun,
    done: viewDone,
  };
  if (!views[ui.view]) ui.view = "today";
  app.innerHTML = views[ui.view]() + sheetView() + (ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : "");
  const now = app.querySelector(".screen");
  if (now && prev) now.scrollTop = scroll;
}

function tickClock() {
  if (!run || ui.view !== "run") return;
  const s = session();
  if (!s || !s.beat) return;
  const b = s.beat;
  if (b.kind === "count" && !run.paused) {
    const left = remaining();
    if (left <= 0) return advance();
    const clockEl = document.querySelector("[data-clock]");
    if (clockEl) clockEl.textContent = clock(left);
    if (b.box) {
      const at = ballAt(b);
      const ball = document.querySelector("[data-ball]");
      if (ball) {
        ball.style.left = at.x.toFixed(1) + "px";
        ball.style.top = at.y.toFixed(1) + "px";
      }
      const phase = document.querySelector("[data-phase]");
      if (phase && phase.textContent !== BREATH_LABEL[at.index]) phase.textContent = BREATH_LABEL[at.index];
      const count = document.querySelector("[data-count]");
      if (count && count.textContent !== String(at.left)) count.textContent = String(at.left);
      document.querySelectorAll("[data-phasebar]").forEach((el) => el.classList.toggle("on", Number(el.dataset.phasebar) === at.index));
    } else if (b.reads && b.reads.length && !run.hide) {
      const read = readNow(b);
      const el = document.querySelector("[data-read]");
      if (read && el && el.textContent.replace(/\s+/g, " ") !== read.text.replace(/\s+/g, " ")) render();
    } else if (b.cues && b.cues.length) {
      const cue = cueNow(b);
      const el = document.querySelector("[data-cue]");
      if (cue && el && el.textContent !== cue.text) render();
    }
  }
  const bar = document.querySelector("[data-segbar]");
  if (bar) bar.style.width = stepPct(s) + "%";
  const leftEl = document.querySelector("[data-left]");
  if (leftEl) leftEl.textContent = clock(sessionLeft(s));
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
  ui.menu = false;
  render();
  const el = document.querySelector(".screen");
  if (el) el.scrollTop = 0;
}

function saveWrite() {
  const s = session();
  if (!s || !s.beat || s.beat.kind !== "write") return;
  const base = entryBase(s);
  const lineEls = [...document.querySelectorAll("[data-line]")];
  if (lineEls.length) {
    const lines = lineEls.map((el) => el.value.trim());
    if (lines.some(Boolean) || R.entry(base.id)) R.saveEntry(base, { lines });
  } else {
    const para = document.querySelector("[data-para]");
    const text = para ? para.value.trim() : "";
    if (text || R.entry(base.id)) R.saveEntry(base, { text });
  }
}

function openBook(tag, from) {
  ui.bookTag = tag;
  ui.bookDay = null;
  ui.goto = false;
  ui.bookFrom = from;
  go("book");
}

document.addEventListener("input", (e) => {
  if (e.target.matches("[data-line], [data-para]")) {
    clearTimeout(writeTimer);
    writeTimer = setTimeout(saveWrite, 600);
  }
});

document.addEventListener("change", (e) => {
  if (e.target.matches("[data-pref]")) setPref(e.target.dataset.pref, e.target.checked);
  if (e.target.matches("[data-device]")) store.setDevice(e.target.value);
  if (e.target.matches("[data-gotodate]")) {
    const pages = bookPages(ui.bookTag);
    const v = e.target.value;
    const hit = [...pages].reverse().find((p) => p.day <= v) || pages[0];
    if (hit) ui.bookDay = hit.day;
    ui.goto = false;
    render();
  }
});

document.addEventListener("click", async (e) => {
  if (e.target.matches("[data-close-sheet]")) {
    ui.sheet = null;
    return render();
  }
  const t = e.target.closest("button");
  if (!t || t.disabled) return;
  const d = t.dataset;
  if (d.view) return go(d.view);
  if (d.home !== undefined) {
    run = null;
    saveRun();
    return go("today");
  }
  if (d.start) {
    const [id, slot] = d.start.split("|");
    return startSession(id, R.today(), slot);
  }
  if (d.go) {
    const [k, m] = d.go.split("|");
    writeLocal("zenda.mins." + k, m);
    return startAdhoc(adhocStep(k, Number(m)));
  }
  if (d.journal) return startAdhoc(adhocStep("journal", 0, d.journal));
  if (d.sproj) {
    const [k, id] = d.sproj.split("|");
    ui.startProj[k] = id;
    return render();
  }
  if (d.end !== undefined) {
    if (confirm("End this session? Steps you finished stay ticked.")) endRun();
    return;
  }
  if (d.pause !== undefined) return togglePause();
  if (d.hide !== undefined) {
    run.hide = !run.hide;
    saveRun();
    return render();
  }
  if (d.skip !== undefined) {
    clearTimeout(writeTimer);
    saveWrite();
    return advance();
  }
  if (d.said !== undefined) {
    const s = session();
    const lines = s.beat.lines.length ? s.beat.lines : [s.beat.name];
    run.say.said += 1;
    if (run.say.said >= s.beat.times) {
      run.say.said = 0;
      run.say.line += 1;
      if (run.say.line >= lines.length) return advance();
      chime(false);
    }
    saveRun();
    return render();
  }
  if (d.menu !== undefined) {
    ui.menu = !ui.menu;
    return render();
  }
  if (d.pick) {
    ui.sel = d.pick;
    ui.menu = false;
    ui.selDay = null;
    ui.weekAnchor = null;
    return render();
  }
  if (d.scope) {
    ui.scope = d.scope;
    ui.menu = false;
    return render();
  }
  if (d.range) {
    ui.range = d.range;
    return render();
  }
  if (d.week) {
    ui.weekAnchor = shiftDay(ui.weekAnchor || weekStart(R.today()), Number(d.week) * 7);
    ui.selDay = null;
    return render();
  }
  if (d.day) {
    ui.selDay = d.day;
    return render();
  }
  if (d.newproject !== undefined) return openSheet(null);
  if (d.edit) return openSheet(R.projects().find((p) => p.id === d.edit));
  if (d.wday) {
    readSheet();
    const n = Number(d.wday);
    const days = ui.sheet.days;
    ui.sheet.days = days.includes(n) ? days.filter((x) => x !== n) : [...days, n];
    return render();
  }
  if (d.cancel !== undefined) {
    ui.sheet = null;
    return render();
  }
  if (d.saveproject !== undefined) return saveProject();
  if (d.delproject !== undefined) {
    if (confirm("Delete this project? Sessions and journal pages stay.")) {
      store.remove("zenda.project", ui.sheet.id);
      ui.sheet = null;
      ui.sel = null;
      render();
    }
    return;
  }
  if (d.book) return openBook(d.book, ui.view === "run" ? "run" : d.from || "review");
  if (d.bookback !== undefined) return go(ui.bookFrom === "run" && run ? "run" : "review");
  if (d.booktag) {
    ui.bookTag = d.booktag;
    ui.bookDay = null;
    return render();
  }
  if (d.flip) {
    const pages = bookPages(ui.bookTag);
    let at = pages.findIndex((p) => p.day === ui.bookDay);
    if (at < 0) at = pages.length - 1;
    const next = pages[at + Number(d.flip)];
    if (next) ui.bookDay = next.day;
    return render();
  }
  if (d.goto !== undefined) {
    ui.goto = !ui.goto;
    return render();
  }
  if (d.sync !== undefined) {
    await store.syncNow();
    return toast(store.snapshot().problem || "Synced");
  }
  if (d.export !== undefined) {
    const blob = new Blob([JSON.stringify(store.exportDocuments(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `zenda-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    return;
  }
  if (d.signout !== undefined) {
    if (confirm("Disconnect this device? Anything not yet uploaded is lost.")) store.disconnect();
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
    return render();
  }
  ui.setupError = "";
  store.configure(url, key);
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
  if (active && active.matches && active.matches("textarea, input, select")) return;
  render();
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && run && ui.view === "run") {
    keepAwake(true);
    tickClock();
  }
});

readSetupLink();
window.addEventListener("hashchange", readSetupLink);
store.subscribe(onStore);
if (run && !run.finished && session()) ui.view = "run";
if (run && run.finished) {
  run = null;
  saveRun();
}
render();
setInterval(tickClock, 250);
setInterval(() => {
  if (ui.view === "today") onStore();
}, 60000);
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
