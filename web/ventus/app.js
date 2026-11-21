import * as store from "./store.js";
import { $, esc, readLocal, writeLocal, parseDay, shiftDay, weekStart, isoNow } from "./util.js";
import * as R from "./routines.js";
import * as P from "./projects.js";
import { beatsForSteps, estimate, clock, minutes, split, runOf, plainDetail, breath } from "./plan.js";

const APP_NAME = "Ventus";
const RUN_KEY = "runner.run.v1";
const FEELS = [
  ["easy", "Easy"],
  ["right", "Right"],
  ["hard", "Hard"],
];
const FEEL_NUM = { easy: "2", right: "3", hard: "4", "too-hard": "4" };
const KINDS = [
  ["run", "Run"],
  ["rope", "Rope"],
  ["walk", "Walk"],
  ["gym", "Gym"],
  ["other", "Other"],
];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

const PATHS = {
  today: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2" fill="currentColor"/>',
  scheduled: '<rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  start: '<path d="M8 5.5v13l10.5-6.5z"/>',
  review: '<path d="M6 20v-7M12 20V5M18 20v-10"/>',
  flame: '<path d="M12 3c1 4 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3 0-3-1-5 1-8.5z"/>',
  run: '<path d="M4 8h9M2 12h13M5 16h8"/><path d="M15 6l5 6-5 6"/>',
  rope: '<path d="M6 4v5M18 4v5M6 9c0 9 12 9 12 0"/>',
  up: '<path d="M12 20V5M7 10l5-5 5 5"/>',
  wave: '<path d="M3 14c3-5 6 5 9 0s6 5 9 0"/>',
  pulse: '<path d="M3 12h3l2-5 4 10 2-5h7"/>',
  loop: '<path d="M17 4l3 3-3 3M20 7H8a4 4 0 0 0-4 4M7 20l-3-3 3-3M4 17h12a4 4 0 0 0 4-4"/>',
  walk: '<circle cx="13" cy="4.5" r="1.8"/><path d="M9 21l2.5-6.5L14 17v4M11.5 14.5l1-5.5 3 3h3M12.5 9L8 11v3"/>',
  gym: '<path d="M6.5 7v10M17.5 7v10M3.5 10v4M20.5 10v4M6.5 12h11"/>',
  other: '<circle cx="6" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="18" cy="12" r="1.2"/>',
  timer: '<circle cx="12" cy="13" r="7.5"/><path d="M12 9v4l2.5 2M10 3h4"/>',
  down: '<path d="M6 9l6 6 6-6"/>',
  left: '<path d="M15 6l-6 6 6 6"/>',
  right: '<path d="M9 6l6 6-6 6"/>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  minus: '<path d="M6 12h12"/>',
  close: '<path d="M6 6l12 12M18 6L6 18"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  flag: '<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  heart: '<path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10z"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
};
const FILLED = {
  play: '<path d="M7 4.5v15l12-7.5z"/>',
  pause: '<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>',
  prev: '<path d="M18 5v14L8 12zM6 5h2v14H6z"/>',
  next: '<path d="M6 5v14l10-7zM16 5h2v14h-2z"/>',
};

function icon(name, cls = "") {
  if (FILLED[name]) return `<svg class="ic fill ${cls}" viewBox="0 0 24 24" aria-hidden="true">${FILLED[name]}</svg>`;
  return `<svg class="ic ${cls}" viewBox="0 0 24 24" aria-hidden="true">${PATHS[name] || PATHS.other}</svg>`;
}

function kindOf(step) {
  const name = split(step && step.title).name;
  if (/warm/i.test(name)) return "flame";
  if (/rope|skip/i.test(name)) return "rope";
  if (/calf|calves|shin/i.test(name)) return "up";
  if (/stretch|mobility|cool|recovery/i.test(name)) return "wave";
  if (/cardio|interval|hiit/i.test(name)) return "pulse";
  if (/circuit|strength/i.test(name)) return "loop";
  if (/walk/i.test(name)) return "walk";
  if (/gym|weights|lift/i.test(name)) return "gym";
  if (/^run|jog/i.test(name)) return "run";
  const t = runOf(step).type;
  return t === "intervals" ? "pulse" : t === "rounds" ? "loop" : t === "log" ? "run" : t === "moves" ? "loop" : "timer";
}

function stepIcon(step) {
  const k = kindOf(step);
  return icon(k, k === "flame" ? "hot" : k === "wave" ? "cool" : "");
}

const ui = {
  tab: "today",
  view: "today",
  day: null,
  week: null,
  weekFor: null,
  scope: "project",
  sheet: null,
  draft: null,
  draftError: "",
  logd: null,
  setupError: "",
  toast: "",
  steps: false,
};

let run = loadRun();
let lock = null;
let audio = null;

const pref = (k, d) => readLocal("runner." + k, d) === "1";
const setPref = (k, on) => writeLocal("runner." + k, on ? "1" : "0");

function newId() {
  try {
    return store.uuid();
  } catch (e) {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => ((Math.random() * 16) | (c === "x" ? 0 : 8)).toString(16)).toUpperCase();
  }
}

function loadRun() {
  try {
    const saved = JSON.parse(readLocal(RUN_KEY, "null"));
    if (saved && typeof saved === "object" && saved.routineId != null && typeof saved.day === "string") {
      if (saved.adhoc && !Array.isArray(saved.steps)) return null;
      saved.spent = saved.spent && typeof saved.spent === "object" ? saved.spent : {};
      saved.say = saved.say && typeof saved.say === "object" ? saved.say : { line: 0, said: 0 };
      saved.doneSteps = Array.isArray(saved.doneSteps) ? saved.doneSteps : [];
      saved.i = Number.isInteger(saved.i) && saved.i >= 0 ? saved.i : 0;
      return saved;
    }
  } catch (e) {}
  return null;
}

function saveRun() {
  writeLocal(RUN_KEY, run ? JSON.stringify(run) : null);
}

function session() {
  if (!run) return null;
  const routine = R.routine(run.routineId) || (run.adhoc ? { id: run.routineId, name: run.routineName || "" } : null);
  if (!routine) return null;
  const steps = run.adhoc ? run.steps.filter((s) => s && typeof s === "object") : R.stepsOn(routine, run.day, run.slot);
  if (!steps.length) return null;
  const beats = beatsForSteps(steps, run.day);
  return { routine, steps, beats, beat: beats[run.i] };
}

function stepDone(s, index) {
  if (!run) return false;
  if (run.adhoc) return run.doneSteps.includes(index);
  const step = s.steps[index];
  return !!step && R.isDone(s.routine.id, run.day, run.slot, step.id);
}

function chime(strong) {
  if (!pref("sound", "1")) return;
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    const notes = strong ? [660, 880] : [740];
    notes.forEach((f, i) => {
      const o = audio.createOscillator();
      const g = audio.createGain();
      o.type = "sine";
      o.frequency.value = f;
      const t = audio.currentTime + i * 0.18;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(0.35, t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.5);
      o.connect(g).connect(audio.destination);
      o.start(t);
      o.stop(t + 0.55);
    });
  } catch (e) {}
  try {
    navigator.vibrate && navigator.vibrate(strong ? [120, 80, 120] : 150);
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

function begin(beats, i) {
  enterBeat(beats[i], true);
  ui.view = "run";
  ui.steps = false;
  ui.sheet = null;
  keepAwake(true);
  if (audio && audio.state === "suspended") audio.resume();
  render();
  window.scrollTo(0, 0);
}

function startSession(routineId, day, slot) {
  const routine = R.routine(routineId);
  if (!routine) return;
  const steps = R.stepsOn(routine, day, slot);
  if (!steps.length) return;
  const beats = beatsForSteps(steps, day);
  if (!beats.length) return;
  const first = steps.findIndex((s) => !R.isDone(routineId, day, slot, s.id));
  const i = Math.max(0, beats.findIndex((b) => b.step === (first < 0 ? 0 : first)));
  run = { routineId, routineName: routine.name, day, slot, i, started: Date.now(), stepStarted: Date.now(), spent: {}, paused: false, waiting: false, left: null, endsAt: null, say: { line: 0, said: 0 }, doneSteps: [] };
  begin(beats, i);
}

function startAdhoc(routine, day, steps, title) {
  const clean = steps.filter((s) => s && typeof s === "object");
  if (!clean.length) return;
  const beats = beatsForSteps(clean, day);
  if (!beats.length) return;
  run = { adhoc: true, routineId: routine ? routine.id : "", routineName: routine ? routine.name || "" : "", day, slot: "", steps: JSON.parse(JSON.stringify(clean)), title: String(title || "Workout"), i: 0, started: Date.now(), stepStarted: Date.now(), spent: {}, paused: false, waiting: false, left: null, endsAt: null, say: { line: 0, said: 0 }, doneSteps: [], log: {} };
  begin(beats, 0);
}

function enterBeat(beat, newStep) {
  if (!beat) return;
  run.say = { line: 0, said: 0 };
  if (newStep) run.stepStarted = Date.now();
  run.waiting = newStep && pref("hold", "0") && run.i > 0;
  const counted = beat.kind === "count" || beat.kind === "rest";
  run.left = counted ? beat.seconds : null;
  run.paused = run.waiting;
  run.endsAt = counted && !run.paused ? Date.now() + beat.seconds * 1000 : null;
  saveRun();
}

function completeStep(s, index) {
  const step = s.steps[index];
  if (!step) return;
  run.spent[index] = (run.spent[index] || 0) + Math.round((Date.now() - run.stepStarted) / 1000);
  if (run.adhoc) {
    if (!run.doneSteps.includes(index)) run.doneSteps.push(index);
  } else R.tick(s.routine.id, run.day, run.slot, step.id);
}

function finish() {
  run.finished = Date.now();
  if (run.adhoc && !run.workoutId) saveWorkout();
  saveRun();
  ui.view = "done";
  keepAwake(false);
}

function saveWorkout() {
  const id = `workout|${newId()}`;
  const seconds = Math.max(1, Math.round(((run.finished || Date.now()) - run.started) / 1000));
  const data = { id, routine: run.routineId, routineName: run.routineName || "", tag: "workout", step: "guided", title: run.title, day: run.day, slot: "", seconds, updated: isoNow() };
  const km = Number(run.log && run.log.km);
  if (km > 0) data.km = km;
  if (run.log && run.log.notes) data.notes = String(run.log.notes);
  store.put("runner.entry", id, data);
  run.workoutId = id;
}

function advance() {
  const s = session();
  if (!s) return endRun();
  const cur = s.beat;
  const next = s.beats[run.i + 1];
  if (cur && (!next || next.step !== cur.step)) completeStep(s, cur.step);
  if (!next) {
    finish();
    chime(true);
    render();
    return;
  }
  run.i += 1;
  enterBeat(next, next.step !== cur.step);
  if (!cur.quiet) chime(false);
  render();
}

function back() {
  const s = session();
  if (!s || run.i === 0) return;
  const prev = s.beats[run.i - 1];
  const changing = prev.step !== s.beat.step;
  run.i -= 1;
  enterBeat(prev, changing);
  render();
}

function togglePause() {
  if (!run) return;
  if (run.waiting) {
    run.waiting = false;
    run.paused = false;
    run.stepStarted = Date.now();
    if (run.left != null) run.endsAt = Date.now() + run.left * 1000;
  } else if (run.paused) {
    run.paused = false;
    if (run.left != null) run.endsAt = Date.now() + run.left * 1000;
  } else {
    run.paused = true;
    if (run.endsAt) run.left = Math.max(0, (run.endsAt - Date.now()) / 1000);
    run.endsAt = null;
  }
  saveRun();
  render();
}

function addRest(seconds) {
  if (!run) return;
  if (run.endsAt) run.endsAt += seconds * 1000;
  else if (run.left != null) run.left += seconds;
  saveRun();
  tickClock();
}

function endRun() {
  run = null;
  saveRun();
  keepAwake(false);
  ui.view = ui.tab;
  render();
}

function remaining() {
  if (!run) return 0;
  if (run.endsAt) return Math.max(0, (run.endsAt - Date.now()) / 1000);
  return run.left ?? 0;
}

function softLeft(beat) {
  if (!beat || !beat.guide) return null;
  const used = run.paused && !run.waiting ? 0 : (Date.now() - run.stepStarted) / 1000;
  return Math.max(0, beat.guide - used);
}

function elapsed() {
  return run ? Math.max(0, ((run.finished || Date.now()) - run.started) / 1000) : 0;
}

const BOX_SIDE = 220;
const BOX_CORNERS = [
  [0, 1],
  [0, 0],
  [1, 0],
  [1, 1],
];

function ballAt(b) {
  const p = breath(b.box, b.seconds - remaining());
  const a = BOX_CORNERS[p.index];
  const z = BOX_CORNERS[(p.index + 1) % 4];
  return { ...p, x: (a[0] + (z[0] - a[0]) * p.fraction) * BOX_SIDE, y: (a[1] + (z[1] - a[1]) * p.fraction) * BOX_SIDE };
}

function boxView(b) {
  const at = ballAt(b);
  const pad = 16;
  const size = BOX_SIDE + pad * 2;
  return `<div class="breathbox"><svg width="${size}" height="${size}" viewBox="${-pad} ${-pad} ${size} ${size}" aria-hidden="true"><rect x="0" y="0" width="${BOX_SIDE}" height="${BOX_SIDE}" rx="10" fill="none" stroke="var(--track)" stroke-width="4"/><circle data-ball cx="${at.x.toFixed(1)}" cy="${at.y.toFixed(1)}" r="12" fill="var(--ink)"/></svg><div class="breathtext"><b data-phase>${esc(at.label)}</b><span data-phasecount>${at.left}</span></div></div>`;
}

function readNow(b) {
  if (!b.reads || !b.reads.length) return null;
  const used = Math.max(0, b.seconds - remaining());
  return b.reads[Math.floor(used / (b.every || 20)) % b.reads.length];
}

function tickBox() {
  const s = run && ui.view === "run" && !ui.steps ? session() : null;
  if (s && s.beat && s.beat.box && !run.waiting) {
    const ball = document.querySelector("[data-ball]");
    if (ball) {
      const at = ballAt(s.beat);
      ball.setAttribute("cx", at.x.toFixed(1));
      ball.setAttribute("cy", at.y.toFixed(1));
      const phase = document.querySelector("[data-phase]");
      if (phase && phase.textContent !== at.label) phase.textContent = at.label;
      const count = document.querySelector("[data-phasecount]");
      if (count && count.textContent !== String(at.left)) count.textContent = String(at.left);
    }
  }
  requestAnimationFrame(tickBox);
}

function ring(size, stroke, fraction, color, track) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return `<svg class="ring" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${track}" stroke-width="${stroke}"/><circle data-ring="${c.toFixed(1)}" cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${(c * (1 - fraction)).toFixed(1)}" transform="rotate(-90 ${size / 2} ${size / 2})"/></svg>`;
}

function dayRing(n, of, size, dark) {
  const c = 2 * Math.PI * 27;
  const f = of > 0 ? Math.min(1, Math.max(0, n / of)) : 0;
  const track = dark ? "#6E5747" : "var(--track)";
  const ink = dark ? "#ffffff" : "var(--ink)";
  return `<svg class="dring" viewBox="0 0 64 64" width="${size}" height="${size}" aria-hidden="true"><circle cx="32" cy="32" r="27" fill="none" stroke="${track}" stroke-width="7"/><circle cx="32" cy="32" r="27" fill="none" stroke="${ink}" stroke-width="7" stroke-linecap="round" stroke-dasharray="${(c * f).toFixed(1)} ${c.toFixed(1)}" transform="rotate(-90 32 32)"/><text x="32" y="38" text-anchor="middle" font-family="Nunito, system-ui, sans-serif" font-weight="900" font-size="18" fill="${ink}">${n > 0 && n <= of ? n : ""}</text></svg>`;
}

function topBar(s) {
  const step = s.steps[s.beat.step];
  const segs = s.steps
    .map((_, i) => {
      if (i === s.beat.step) return `<span class="seg now"></span>`;
      if (i < s.beat.step || stepDone(s, i)) return `<span class="seg done"></span>`;
      return `<span class="seg"></span>`;
    })
    .join("");
  return `
    <div class="runbar">
      <button class="xbtn" data-end aria-label="End session">${icon("close")}</button>
      <button class="runtitle" data-steps aria-label="Steps">${esc(split(step.title).name)} · ${s.beat.step + 1}/${s.steps.length}</button>
      <span class="elapsed" data-elapsed>${clock(elapsed())}</span>
    </div>
    <div class="segs">${segs}</div>`;
}

function stepsSheet(s) {
  if (!ui.steps) return "";
  return `<div class="sheet" data-close-steps><div class="sheet-card"><span class="grab"></span>${s.steps
    .map((step, i) => {
      const { name } = split(step.title);
      const done = stepDone(s, i);
      return `<button class="steprow ${i === s.beat.step ? "on" : ""}" data-jump="${i}"><span class="tick ${done ? "done" : ""}">${done ? icon("check") : stepIcon(step)}</span><span class="grow">${esc(name)}</span><em>${esc(P.compact(step))}</em></button>`;
    })
    .join("")}</div></div>`;
}

function controls(primary) {
  return `<div class="controls">
    <button class="cb" data-back aria-label="Back" ${run.i === 0 ? "disabled" : ""}>${icon("prev")}</button>
    ${primary}
    <button class="cb" data-skip aria-label="Skip">${icon("next")}</button>
  </div>`;
}

function pauseButton() {
  return `<button class="cb big" data-pause aria-label="${run.paused ? "Resume" : "Pause"}">${run.paused ? icon("play") : icon("pause")}</button>`;
}

function nextText(s) {
  const b = s.beat;
  if (b.then) return `${b.then.restName} ${clock(b.then.rest)}`;
  const next = s.beats[run.i + 1];
  if (!next) return "Done";
  if (next.step !== b.step) return split(s.steps[next.step].title).name;
  if (next.kind === "rest") return `${next.name} ${clock(next.seconds)}`;
  return `${next.reps ? next.reps + " " : ""}${next.name}`;
}

function nextChip(s) {
  return `<div class="nextchip">${icon("arrow")}${esc(nextText(s))}</div>`;
}

function roundDots(b) {
  if (!b.rounds || b.rounds < 2) return "";
  const n = Math.min(b.rounds, 24);
  return `<div class="rdots">${Array.from({ length: n }, (_, i) => `<span class="${i < b.round ? "done" : i === b.round ? "now" : ""}"></span>`).join("")}</div>`;
}

function cueNow(beat) {
  if (!beat.cues || !beat.cues.length) return null;
  const used = beat.seconds - remaining();
  let cue = null;
  for (const c of beat.cues) if (used >= c.at) cue = c;
  return cue;
}

function moveList(beat) {
  if (!beat.list) return "";
  return `<div class="moves">${beat.list
    .map((m, i) => {
      const state = i < beat.at ? "done" : i === beat.at ? "now" : "";
      const amt = m.seconds ? clock(m.seconds) : m.reps ? String(m.reps) : "";
      return `<div class="mv ${state}"><span class="mk">${state === "done" ? icon("check") : ""}</span><span class="grow">${esc(m.name)}</span><span class="amt">${esc(amt)}</span></div>`;
    })
    .join("")}</div>`;
}

function waitingCard(s) {
  const step = s.steps[s.beat.step];
  const { name, detail } = split(step.title);
  return `
    <div class="center grow">
      <div class="bigicon">${stepIcon(step)}</div>
      <h1 class="huge">${esc(name)}</h1>
      ${detail ? `<p class="lead">${esc(detail)}</p>` : ""}
      ${step.tip ? `<div class="note">${esc(step.tip)}</div>` : ""}
    </div>
    <button class="primary xl" data-pause>${icon("play")}${esc(name)}</button>`;
}

function viewCount(s) {
  const b = s.beat;
  const left = remaining();
  const cue = cueNow(b);
  const fraction = b.seconds ? left / b.seconds : 0;
  if (b.hot) {
    return `
      <div class="center grow">
        ${roundDots(b)}
        <h1 class="move">${esc(b.name)}</h1>
        <div class="bigclock" data-clock>${clock(left)}</div>
        ${nextChip(s)}
      </div>
      ${controls(pauseButton())}`;
  }
  if (b.list) {
    return `
      <div class="center grow">
        ${roundDots(b)}
        <h1 class="move">${esc(b.name)}</h1>
        ${b.detail ? `<p class="lead">${esc(b.detail)}</p>` : ""}
        <div class="ringbox mid">${ring(200, 12, fraction, "var(--ink)", "var(--track)")}<div class="ringtext"><span class="clock" data-clock>${clock(left)}</span></div></div>
        ${nextChip(s)}
      </div>
      ${moveList(b)}
      ${controls(pauseButton())}`;
  }
  const read = readNow(b);
  if (b.box) {
    return `
    <div class="center grow">
      <h1 class="title">${esc(b.name)}</h1>
      ${boxView(b)}
      <p class="sub"><span data-clock>${clock(left)}</span></p>
      ${cue ? `<div class="note" data-cue>${esc(cue.text)}</div>` : ""}
    </div>
    ${controls(pauseButton())}`;
  }
  return `
    <div class="center grow">
      <h1 class="move">${esc(b.name)}</h1>
      ${read ? `<div class="note readline" data-read><p>${esc(read)}</p></div>` : ""}
      <div class="ringbox">${ring(250, 12, fraction, "var(--ink)", "var(--track)")}<div class="ringtext"><span class="clock" data-clock>${clock(left)}</span></div></div>
      ${cue ? `<div class="note" data-cue>${esc(cue.text)}</div>` : b.tip ? `<details class="note"><summary>Tip</summary>${esc(b.tip)}</details>` : ""}
      ${nextChip(s)}
    </div>
    ${controls(pauseButton())}`;
}

function viewRest(s) {
  const b = s.beat;
  const left = remaining();
  const next = s.beats[run.i + 1];
  return `
    <div class="center grow">
      ${roundDots(b)}
      <h1 class="move">${esc(b.name)}</h1>
      <div class="ringbox">${ring(250, 12, b.seconds ? left / b.seconds : 0, "var(--rest)", "var(--track)")}<div class="ringtext"><span class="clock" data-clock>${clock(left)}</span></div></div>
      <div class="chips"><button class="chipbtn" data-more="15">+15s</button><button class="chipbtn" data-skip>${icon("next")}</button><button class="chipbtn" data-pause aria-label="${run.paused ? "Resume" : "Pause"}">${run.paused ? icon("play") : icon("pause")}</button></div>
    </div>
    ${next ? `<div class="nextcard">${icon("arrow")}<span class="grow"><b>${next.reps ? next.reps + " " : ""}${esc(next.name)}</b>${b.nextList && b.nextList.length > 1 ? `<small>${esc(b.nextList.slice(1).join(" · "))}</small>` : ""}</span></div>` : ""}`;
}

function viewReps(s) {
  const b = s.beat;
  const soft = softLeft(b);
  return `
    <div class="grow col center-y">
      ${roundDots(b)}
      ${b.reps ? `<div class="repcount">${b.reps}</div>` : ""}
      <h1 class="move">${esc(b.name)}</h1>
      ${b.detail ? `<p class="lead">${esc(b.detail)}</p>` : ""}
      ${!b.list && b.tip ? `<div class="note">${esc(b.tip)}</div>` : ""}
      ${soft != null ? `<p class="sub" data-soft>${clock(soft)}</p>` : ""}
    </div>
    ${moveList(b)}
    <div class="row gap">
      <button class="cb" data-back aria-label="Back" ${run.i === 0 ? "disabled" : ""}>${icon("prev")}</button>
      <button class="primary xl grow" data-skip>${icon("check")}Done</button>
    </div>`;
}

function viewSay(s) {
  const b = s.beat;
  const lines = b.lines.length ? b.lines : [b.detail || b.name];
  const at = Math.min(run.say.line, lines.length - 1);
  const soft = softLeft(b);
  return `
    <div class="row spread"><h2 class="title">${esc(b.name)}</h2>${soft != null ? `<span class="softclock" data-soft>${clock(soft)}</span>` : ""}</div>
    <div class="grow col center-y">
      <span class="kicker">${at + 1} / ${lines.length}</span>
      <p class="sayline">${esc(lines[at])}</p>
      <div class="dots">${Array.from({ length: b.times }, (_, i) => `<span class="${i < run.say.said ? "lit" : ""}"></span>`).join("")}</div>
    </div>
    <button class="primary xl" data-said>Said it</button>`;
}

function entryBase(s) {
  const step = s.steps[s.beat.step];
  return { id: R.entryId(s.routine.id, run.day, run.slot, step.id), routine: s.routine.id, routineName: s.routine.name, day: run.day, slot: run.slot, step: step.id, title: [split(step.title).name, plainDetail(split(step.title).detail)].filter(Boolean).join(" · "), tag: s.beat.tag || (s.beat.type === "log" ? "run" : "note") };
}

function viewWrite(s) {
  const b = s.beat;
  const saved = run.adhoc ? run.log || {} : R.entry(entryBase(s).id) || {};
  const soft = softLeft(b);
  const lines = b.fields > 1 ? Array.from({ length: b.fields }, (_, i) => (saved.lines || [])[i] || "") : null;
  return `
    <div class="row spread"><h2 class="title">${esc(b.name)}</h2>${soft != null ? `<span class="softclock" data-soft>${clock(soft)}</span>` : ""}</div>
    ${b.prompt ? `<p class="sub">${esc(b.prompt)}</p>` : ""}
    ${
      lines
        ? `<div class="col gap">${lines.map((v, i) => `<label class="field"><span>${i + 1}</span><textarea data-line="${i}" rows="2">${esc(v)}</textarea></label>`).join("")}</div><div class="grow"></div>`
        : `<label class="sr" for="para">${esc(b.name)}</label><textarea id="para" class="para grow" data-para>${esc(saved.text || "")}</textarea>`
    }
    <div class="row gap"><button class="ghost xl" data-skip-write>Skip</button><button class="primary xl grow2" data-skip>Save</button></div>`;
}

function parseDuration(text) {
  const t = String(text || "").trim();
  if (!t) return null;
  if (t.includes(":")) {
    const [m, sec] = t.split(":").map(Number);
    return Number.isFinite(m) && Number.isFinite(sec) && m >= 0 && sec >= 0 ? Math.round(m * 60 + sec) : null;
  }
  const m = Number(t.replace(",", "."));
  return Number.isFinite(m) && m > 0 ? Math.round(m * 60) : null;
}

function pace(seconds, km) {
  if (!seconds || !km) return "";
  return `${clock(seconds / km)} /km`;
}

function viewLog(s) {
  const b = s.beat;
  const saved = run.adhoc ? run.log || {} : R.entry(entryBase(s).id) || {};
  return `
    <div class="center">
      <div class="bigicon">${icon("run")}</div>
      <h1 class="move">${esc(b.plan)}</h1>
    </div>
    ${b.tip ? `<details class="note"><summary>Tip</summary>${esc(b.tip)}</details>` : ""}
    <div class="row gap">
      <label class="fld"><span>min</span><input data-log="time" inputmode="decimal" placeholder="12:40" value="${saved.seconds ? clock(saved.seconds) : ""}"></label>
      <label class="fld"><span>km</span><input data-log="km" inputmode="decimal" placeholder="1.6" value="${esc(saved.km ?? "")}"></label>
    </div>
    <p class="sub center-text" data-pace>${saved.seconds && saved.km ? pace(saved.seconds, saved.km) : ""}</p>
    <label class="notes"><span class="sr">Notes</span><input data-log="notes" placeholder="Notes" value="${esc(saved.notes || "")}"></label>
    <div class="grow"></div>
    <div class="row gap"><button class="ghost xl" data-later>Later</button><button class="primary xl grow2" data-skip>Save</button></div>`;
}

function viewRun() {
  const s = session();
  if (!s || !s.beat) {
    run = null;
    saveRun();
    ui.view = ui.tab;
    return viewTab();
  }
  document.body.dataset.mood = s.beat.kind === "rest" ? "rest" : run.waiting ? "" : "hot";
  let body;
  if (run.waiting) body = waitingCard(s);
  else if (s.beat.kind === "count") body = viewCount(s);
  else if (s.beat.kind === "rest") body = viewRest(s);
  else if (s.beat.kind === "say") body = viewSay(s);
  else if (s.beat.kind === "write") body = viewWrite(s);
  else if (s.beat.kind === "log") body = viewLog(s);
  else body = viewReps(s);
  return `<main class="run">${topBar(s)}${body}</main>${stepsSheet(s)}`;
}

function viewDone() {
  const s = session();
  if (!s) {
    ui.view = ui.tab;
    return viewTab();
  }
  document.body.dataset.mood = "";
  const ticked = s.steps.filter((_, i) => stepDone(s, i)).length;
  const took = Math.max(1, Math.round(elapsed() / 60));
  const p = run.adhoc ? null : P.projects().find((x) => x.id === s.routine.id);
  const n = p ? P.dayNumber(p, run.day) : null;
  const feel = run.adhoc ? Object.keys(FEEL_NUM).find((k) => FEEL_NUM[k] === String((R.entry(run.workoutId) || {}).feel)) : (R.entry(R.entryId(s.routine.id, run.day, run.slot, "feel")) || {}).feel;
  const title = ticked < s.steps.length ? "Stopped early" : run.adhoc ? `${run.title}` : n && n.n > 0 && n.n <= n.of ? `Day ${n.n}` : P.sessionTitle(s.steps);
  return `
    <main class="done">
      <div class="col center gap">
        <div class="bigcheck">${icon("check")}</div>
        <h1 class="huge">${esc(title)}</h1>
        <p class="sub">${took} min${p ? ` · ${esc(p.name)}` : ""}</p>
      </div>
      <div class="card list">${s.steps
        .map((st, i) => `<div class="mv"><span class="mk">${stepDone(s, i) ? icon("check") : ""}</span><span class="ico">${stepIcon(st)}</span><span class="grow">${esc(split(st.title).name)}</span><span class="amt">${run.spent[i] ? clock(run.spent[i]) : ""}</span></div>`)
        .join("")}</div>
      <div class="feel">${FEELS.map(([k, label]) => `<button class="chipbtn ${feel === k ? "on" : ""}" data-feel="${k}">${label}</button>`).join("")}</div>
      <div class="grow"></div>
      <button class="primary xl" data-home>${icon("check")}Done</button>
    </main>`;
}

function dateLabel(day) {
  const d = parseDay(day);
  return `${DAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

function shortDate(day) {
  const d = parseDay(day);
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

function tabBar() {
  const tabs = [
    ["today", "Today"],
    ["scheduled", "Scheduled"],
    ["start", "Start"],
    ["review", "Review"],
  ];
  return `<nav class="tabs">${tabs.map(([k, label]) => `<button class="${ui.tab === k ? "on" : ""}" data-tab="${k}">${icon(k)}${label}</button>`).join("")}</nav>`;
}

function syncDot() {
  const st = store.snapshot();
  const state = st.problem ? "warn" : store.pendingCount() ? "pending" : "ok";
  return `<span class="sync ${state}" title="${esc(st.problem || (store.pendingCount() ? "Uploading" : "Synced"))}"></span>`;
}

function projectPill(p) {
  return `<button class="pill" data-pick>${esc(p.name)}${icon("down")}</button>`;
}

function weekDots(p, day) {
  const start = weekStart(day);
  const letters = ["M", "T", "W", "T", "F", "S", "S"];
  return `<div class="weekdots">${letters
    .map((l, i) => {
      const d = shiftDay(start, i);
      const inRange = d >= p.start && d <= p.end;
      const info = inRange ? P.dayInfo(p, d) : null;
      let cls = "";
      if (info && info.total) {
        if (info.status === "done") cls = info.rest ? "rest" : "done";
        else if (info.status === "part") cls = "part";
        else if (info.status === "missed") cls = "missed";
        else if (info.rest) cls = "rest soon";
      }
      if (d === day) cls += " today";
      return `<button class="wd ${d === day ? "on" : ""}" data-day="${d}" aria-label="${esc(dateLabel(d))}">${l}<span class="${cls}"></span></button>`;
    })
    .join("")}</div>`;
}

function goalBars(p, compact) {
  if (!p.targets.length) return "";
  const ids = new Set([p.id]);
  return p.targets
    .map((t, i) => {
      const got = p.achieved.has(i);
      const best = P.bestFor(t, ids);
      const f = got ? 1 : best ? Math.min(1, best.have / best.want) : 0;
      const right = got ? icon("check") : best ? `${best.have}/${best.want}${best.unit ? " " + best.unit : ""}` : shortDate(p.end);
      return `<button class="goal ${compact ? "" : "card"}" data-goal="${i}"><span class="row spread"><b>${esc(t)}</b><em>${right}</em></span><span class="bar"><i style="width:${Math.round(f * 100)}%"></i></span></button>`;
    })
    .join("");
}

function stepRows(steps, doneOf) {
  return steps
    .map((st, i) => {
      const done = doneOf ? doneOf(st, i) : false;
      return `<div class="step ${done ? "was" : ""}">${stepIcon(st)}<span class="grow">${esc(split(st.title).name)}</span>${done ? icon("check", "okc") : ""}<em>${esc(P.compact(st))}</em></div>`;
    })
    .join("");
}

function inProgress(routineId, day, slot) {
  return run && !run.finished && !run.adhoc && run.routineId === routineId && run.day === day && run.slot === slot && session();
}

function hero(p, x) {
  const n = P.dayNumber(p, x.day);
  const secs = x.steps.reduce((t, st) => t + estimate(st), 0);
  const done = x.done >= x.steps.length;
  const going = inProgress(p.id, x.day, x.slot);
  const label = going ? "Resume" : done ? "Done" : x.done ? "Continue" : "Start";
  return `<section class="hero">
      <div class="herohead">${dayRing(n.n, n.of, 50)}<div class="grow"><small>${esc(p.name)}</small><b>${esc(P.sessionTitle(x.steps))}</b></div></div>
      ${stepRows(x.steps, (st) => R.isDone(p.id, x.day, x.slot, st.id))}
    </section>
    <button class="primary xl" ${done && !going ? "disabled" : ""} data-session="${esc(p.id)}|${x.day}|${x.slot}">${done && !going ? icon("check") : icon("play")}${label}${done || going ? "" : ` · ${minutes(secs)}m`}</button>`;
}

function nextCard(p, info) {
  if (!info) return "";
  return `<button class="nextsession" data-day="${info.day}"><span class="ico">${icon("arrow")}</span><span class="grow"><small>${esc(dateLabel(info.day).replace(/ \w+$/, ""))}</small><b>${esc(info.rest ? split(info.steps[0].title).name : P.sessionTitle(info.steps))}</b></span><em>${minutes(info.seconds)}m</em></button>`;
}

function viewToday() {
  const day = R.today();
  const list = P.projects();
  const cur = P.current(list);
  const d = parseDay(day);
  const ms = cur ? P.nextMilestone(cur) : null;
  const streak = cur ? P.streak(cur) : 0;
  const chips = `${ms ? `<span class="hchip" title="${esc(ms.label)}">${icon("gym")}${P.span(day, ms.day)}</span>` : ""}${cur ? `<span class="hchip">${icon("flame", "hot")}${streak}</span>` : ""}`;
  const heroes = [];
  for (const p of list) {
    const info = P.dayInfo(p, day);
    for (const x of info.sessions) heroes.push(hero(p, x));
  }
  const adhoc = run && run.adhoc && !run.finished && session() ? `<button class="resume" data-resume>${icon("play")}<span class="grow">${esc(run.title)}</span><em>Resume</em></button>` : "";
  let body = heroes.join("");
  if (!heroes.length) {
    const info = cur ? P.dayInfo(cur, day) : null;
    body = `<p class="quiet">${cur && day >= cur.start && day <= cur.end && !(info && info.total) ? "Rest day" : "Nothing today"}</p>`;
  }
  const next = cur ? P.nextSession(cur, day) : null;
  return `<main class="tabview">
    <header class="top"><h1>${DAYS[d.getDay()]} <span>${d.getDate()} ${MONTHS[d.getMonth()]}</span></h1><span class="hchips">${chips}</span></header>
    ${cur ? weekDots(cur, day) : ""}
    ${adhoc}
    ${body}
    ${cur && cur.targets.length ? `<section class="card goals">${goalBars(cur, true)}</section>` : ""}
    ${cur ? nextCard(cur, next) : ""}
  </main>`;
}

function weekIndex(p) {
  const ws = P.weeks(p);
  if (ui.weekFor !== p.id || ui.week == null || ui.week < 0 || ui.week >= ws.length) {
    const now = weekStart(R.today());
    const at = ws.indexOf(now);
    ui.week = at >= 0 ? at : now < ws[0] ? 0 : ws.length - 1;
    ui.weekFor = p.id;
  }
  return { ws, at: ui.week };
}

function timeline(p) {
  const total = Math.max(1, P.span(p.start, p.end));
  const pct = (d) => Math.min(100, Math.max(0, (P.span(p.start, d) / total) * 100));
  const today = R.today();
  const tp = pct(today);
  const marks = p.milestones
    .filter((m) => m.day >= p.start && m.day <= p.end)
    .map((m) => `<span class="mark" style="left:${pct(m.day).toFixed(1)}%" title="${esc(m.label)} · ${esc(shortDate(m.day))}">${icon(m.day === p.end ? "flag" : "gym")}</span>`)
    .join("");
  const endMark = p.milestones.some((m) => m.day === p.end) ? "" : `<span class="mark" style="left:100%">${icon("flag")}</span>`;
  return `<div class="timeline">
      <span class="track"></span><span class="fill" style="width:${tp.toFixed(1)}%"></span>
      ${today >= p.start && today <= p.end ? `<span class="now" style="left:${tp.toFixed(1)}%"></span>` : ""}
      ${marks}${endMark}
      <span class="lab l">${esc(shortDate(p.start))}</span><span class="lab r">${esc(shortDate(p.end))}</span>
    </div>`;
}

function dayGlyphs(info) {
  const main = info.steps.filter((s) => !/warm|stretch/i.test(split(s.title).name));
  const use = main.length ? main : info.steps;
  const seen = [];
  for (const s of use) {
    const k = kindOf(s);
    if (!seen.includes(k)) seen.push(k);
  }
  return seen
    .slice(0, 4)
    .map((k) => icon(k, k === "wave" ? "cool" : ""))
    .join("");
}

function viewScheduled() {
  const list = P.projects();
  const p = P.current(list);
  if (!p) return `<main class="tabview"><p class="quiet">No fitness routines</p></main>`;
  const { ws, at } = weekIndex(p);
  const today = R.today();
  const rows = Array.from({ length: 7 }, (_, i) => {
    const d = shiftDay(ws[at], i);
    const dt = parseDay(d);
    const inRange = d >= p.start && d <= p.end;
    const info = inRange ? P.dayInfo(p, d) : { total: 0, steps: [], seconds: 0, rest: false, status: "none" };
    const cls = [d === today ? "inv" : "", d < today ? "past" : "", info.rest ? "restday" : "", !inRange ? "out" : ""].join(" ");
    const right = info.status === "done" ? icon("check", "okc") : info.total ? `<em>${minutes(info.seconds)}m</em>` : "";
    return `<button class="dr ${cls}" data-day="${d}"><span class="d"><small>${DAYS[dt.getDay()]}</small><b>${dt.getDate()}</b></span><span class="g">${info.total ? dayGlyphs(info) : ""}</span>${right}</button>`;
  }).join("");
  return `<main class="tabview">
    <header class="top">${projectPill(p)}<span class="grow"></span><button class="ib" data-edit aria-label="Edit project">${icon("pencil")}</button></header>
    <section class="card plan">
      ${p.targets.length ? `<div class="targets">${icon("flag")}<span>${p.targets.map(esc).join('<i>·</i>')}</span></div>` : ""}
      ${timeline(p)}
    </section>
    <div class="stepper"><button class="ib" data-week="-1" aria-label="Previous week" ${at === 0 ? "disabled" : ""}>${icon("left")}</button><span class="grow">Week ${at + 1} <span>/ ${ws.length}</span></span><button class="ib" data-week="1" aria-label="Next week" ${at >= ws.length - 1 ? "disabled" : ""}>${icon("right")}</button></div>
    <div class="days">${rows}</div>
  </main>`;
}

function stepCard(st, done) {
  const seg = P.segments(st);
  const sets = P.sets(st);
  let extra = "";
  if (seg) {
    extra = `<div class="segbar">${seg.bars.map((b) => `<span class="${b}"></span>`).join("")}</div><div class="legend"><span><i class="on"></i>${esc(seg.onName.toLowerCase())} ${clock(seg.on)}</span>${seg.off ? `<span><i class="off"></i>${esc(seg.offName.toLowerCase())} ${clock(seg.off)}</span>` : ""}</div>`;
  } else if (sets) {
    extra = `<div class="setchips">${sets.map((x) => `<span>${esc(x)}</span>`).join("")}</div>`;
  }
  return `<div class="st ${done ? "was" : ""}"><div class="hd">${stepIcon(st)}<span class="grow">${esc(split(st.title).name)}</span>${done ? icon("check", "okc") : ""}<em>${esc(P.amount(st))}</em></div>${extra}</div>`;
}

function viewDay() {
  const p = P.current();
  const day = ui.day;
  if (!p || !P.isDay(day)) {
    ui.view = "scheduled";
    return viewScheduled();
  }
  const info = P.dayInfo(p, day);
  const n = P.dayNumber(p, day);
  const d = parseDay(day);
  const wk = P.weeks(p).indexOf(weekStart(day));
  const inRange = day >= p.start && day <= p.end;
  const cards = info.sessions.flatMap((x) => x.steps.map((st) => stepCard(st, R.isDone(p.id, day, x.slot, st.id)))).join("");
  return `<main class="tabview dayview">
    <button class="backlink" data-tab="scheduled">${icon("left")}${wk >= 0 ? `Week ${wk + 1}` : "Scheduled"}</button>
    <header class="dayhead"><h1>${DAYS[d.getDay()]} ${d.getDate()}</h1><span>${inRange ? `Day ${n.n}` : ""}${info.total ? `${inRange ? " · " : ""}${minutes(info.seconds)}m` : ""}${info.status === "done" ? ` ${icon("check", "okc")}` : ""}</span></header>
    ${cards || `<p class="quiet">${inRange ? "Rest day" : "Nothing"}</p>`}
    <span class="grow"></span>
    ${info.total ? `<div class="row gap"><button class="soft xl grow" data-preview>${icon("eye")}Preview</button><button class="primary xl grow" data-startday="${day}">${icon("play")}${day === R.today() && info.done && info.done < info.total ? "Continue" : "Start"}</button></div>` : ""}
  </main>`;
}

function distinctSteps(p) {
  const today = R.today();
  const found = new Map();
  for (const d of P.daysOf(p)) {
    for (const x of P.sessionsOn(p.routine, d)) {
      for (const st of x.steps) {
        const name = split(st.title).name;
        if (!name) continue;
        if (!found.has(name) || d <= today) found.set(name, { day: d, step: st });
      }
    }
  }
  return [...found.entries()].map(([name, v]) => ({ name, ...v }));
}

function viewStart() {
  const p = P.current();
  const today = R.today();
  const info = p ? P.dayInfo(p, today) : null;
  const tiles = p ? distinctSteps(p) : [];
  ui.tiles = tiles;
  const n = p ? P.dayNumber(p, today) : null;
  const big =
    info && info.total
      ? `<button class="t big" data-starttoday>${dayRing(n.n, n.of, 50, true)}<span class="grow">${esc(P.sessionTitle(info.steps))}<small>${info.status === "done" ? icon("check") : `${minutes(info.seconds)}m`}</small></span>${icon("play")}</button>`
      : "";
  return `<main class="tabview">
    <div class="cap">${icon("play")}Guided</div>
    ${big}
    <div class="grid3">
      ${tiles.map((t, i) => `<button class="t" data-tile="${i}">${stepIcon(t.step)}<span>${esc(t.name)}<small>${esc(P.compact(t.step))}</small></span></button>`).join("")}
      ${p ? `<button class="t line" data-tab="scheduled">${icon("scheduled")}<span>Any day<small>1–${P.dayNumber(p, p.end).of}</small></span></button>` : ""}
    </div>
    <div class="cap">${icon("plus")}Log</div>
    <div class="grid5">${KINDS.map(([k, label]) => `<button class="t line l" data-logkind="${k}">${icon(k)}${label}</button>`).join("")}</div>
  </main>`;
}

function scopeDays(scope, p, list) {
  const today = R.today();
  const out = [];
  const add = (q, from, to) => {
    for (const d of P.daysOf(q, from, to)) if (d <= today) out.push({ p: q, day: d, info: P.dayInfo(q, d) });
  };
  if (scope === "week") add(p, weekStart(today), shiftDay(weekStart(today), 6));
  else if (scope === "all") list.forEach((q) => add(q, q.start, q.end));
  else add(p, p.start, p.end);
  return out;
}

function heatmap(p) {
  const today = R.today();
  const ws = P.weeks(p);
  const ms = new Map(p.milestones.map((m) => [m.day, m]));
  return ws
    .map(
      (w) =>
        `<div class="hm">${Array.from({ length: 7 }, (_, i) => {
          const d = shiftDay(w, i);
          if (d < p.start || d > p.end) return `<span class="blank"></span>`;
          const info = P.dayInfo(p, d);
          let cls = "";
          if (info.status === "done") cls = info.rest ? "r" : "d";
          else if (info.status === "part") cls = "pt";
          else if (info.status === "missed") cls = "x";
          else if (info.rest) cls = "r soon";
          if (d === today) cls += " tdy";
          else if (d === p.end) cls += " end";
          else if (ms.has(d)) cls += " ms";
          return `<span class="${cls}" title="${esc(dateLabel(d))}${ms.has(d) ? ` · ${esc(ms.get(d).label)}` : ""}"></span>`;
        }).join("")}</div>`
    )
    .join("");
}

function chart(days, ids) {
  const byDay = new Map();
  for (const x of days) {
    const cur = byDay.get(x.day) || { day: x.day, secs: 0, total: 0, rest: true, missed: true };
    cur.secs += x.info.doneSeconds;
    cur.total += x.info.total;
    if (x.info.total && !x.info.rest) cur.rest = false;
    if (x.info.status !== "missed") cur.missed = false;
    byDay.set(x.day, cur);
  }
  for (const w of P.workouts(ids)) {
    const cur = byDay.get(w.day);
    if (cur) {
      cur.secs += Number(w.seconds) > 0 ? Number(w.seconds) : 0;
      cur.missed = cur.secs <= 0 && cur.missed;
    }
  }
  const today = R.today();
  const pts = [...byDay.values()].filter((v) => v.total || v.secs).filter((v) => !(v.day === today && v.secs <= 0)).sort((a, b) => a.day.localeCompare(b.day));
  if (!pts.length) return "";
  const W = 340;
  const H = 120;
  const max = Math.max(10, ...pts.map((v) => v.secs / 60));
  const step = pts.length > 1 ? (W - 28) / (pts.length - 1) : 0;
  const xy = pts.map((v, i) => ({ v, x: 14 + i * step, y: 110 - ((v.secs / 60) / max) * 96 }));
  let path = "";
  let pen = false;
  for (const q of xy) {
    const work = !q.v.missed && !q.v.rest && q.v.secs > 0;
    if (work) {
      path += `${pen ? "L" : "M"}${q.x.toFixed(1)} ${q.y.toFixed(1)}`;
      pen = true;
    } else pen = false;
  }
  const dots = xy
    .map((q) => {
      if (q.v.missed || q.v.secs <= 0) return `<circle cx="${q.x.toFixed(1)}" cy="110" r="4.5" fill="var(--card)" stroke="var(--line)" stroke-width="2"/>`;
      if (q.v.rest) return `<circle cx="${q.x.toFixed(1)}" cy="${q.y.toFixed(1)}" r="4.5" fill="var(--rest)"/>`;
      return `<circle cx="${q.x.toFixed(1)}" cy="${q.y.toFixed(1)}" r="4" fill="var(--ink)"/>`;
    })
    .join("");
  return `<section class="card"><div class="cardhead"><span>Minutes</span><em>${Math.round(max)}</em></div><svg class="chart" viewBox="0 0 ${W} ${H + 6}" role="img" aria-label="Minutes per session day"><g stroke="var(--side)" stroke-width="1"><path d="M0 14H${W}M0 62H${W}M0 110H${W}"/></g><path d="${path}" fill="none" stroke="var(--ink)" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>${dots}</svg></section>`;
}

function feelCard(ids) {
  const list = P.feels(ids);
  if (!list.length) return "";
  return `<section class="card"><div class="cardhead"><span>${icon("heart")}Feel</span><em>${list[list.length - 1].v}</em></div><div class="feelbars">${list.map((f) => `<span title="${esc(dateLabel(f.day))}"><i style="height:${f.v * 20}%"></i><small>${f.v}</small></span>`).join("")}</div></section>`;
}

function runsCard(ids) {
  const list = P.runs(ids).slice(0, 8);
  if (!list.length) return "";
  return `<section class="card"><div class="cardhead"><span>${icon("run")}Runs</span><em>${list.length}</em></div>${list
    .map((e) => {
      const km = Number(e.km) > 0 ? Number(e.km) : 0;
      const s = Number(e.seconds) > 0 ? Number(e.seconds) : 0;
      return `<div class="runrow"><span class="grow">${esc(dateLabel(e.day))}</span><b>${km ? `${km} km` : ""}</b><span>${s ? clock(s) : ""}</span><em>${pace(s, km)}</em></div>`;
    })
    .join("")}</section>`;
}

function viewReview() {
  const list = P.projects();
  const p = P.current(list);
  if (!p) return `<main class="tabview"><header class="top"><span class="grow"></span>${syncDot()}<button class="ib" data-settings aria-label="Settings">${icon("gear")}</button></header><p class="quiet">No fitness routines</p></main>`;
  const scope = ["week", "project", "all"].includes(ui.scope) ? ui.scope : "project";
  const days = scopeDays(scope, p, list);
  const today = R.today();
  const counted = days.filter((x) => x.info.total && (x.day < today || x.info.status === "done"));
  const done = counted.filter((x) => x.info.status === "done").length;
  const ids = scope === "all" ? new Set(list.map((q) => q.id)) : new Set([p.id]);
  const dayset = new Set(days.map((x) => x.day));
  const workSecs = P.workouts(ids)
    .filter((w) => (scope === "all" ? true : dayset.has(w.day)))
    .reduce((n, w) => n + (Number(w.seconds) > 0 ? Number(w.seconds) : 0), 0);
  const hours = (days.reduce((n, x) => n + x.info.doneSeconds, 0) + workSecs) / 3600;
  const goalsOf = scope === "all" ? list : [p];
  const goalsDone = goalsOf.reduce((n, q) => n + q.achieved.size, 0);
  const goalsAll = goalsOf.reduce((n, q) => n + q.targets.length, 0);
  const streak = scope === "all" ? Math.max(0, ...list.map((q) => P.streak(q))) : P.streak(p);
  return `<main class="tabview">
    <header class="top">${projectPill(p)}<span class="grow"></span>${syncDot()}<button class="ib" data-settings aria-label="Settings">${icon("gear")}</button></header>
    <div class="segs3">${[
      ["week", "Week"],
      ["project", "Project"],
      ["all", "All"],
    ]
      .map(([k, l]) => `<button class="${scope === k ? "on" : ""}" data-scope="${k}">${l}</button>`)
      .join("")}</div>
    <div class="stats">
      <div class="card stat"><b>${done}<small>/${counted.length}</small></b><span>days</span></div>
      <div class="card stat"><b>${streak}</b><span>${icon("flame", "hot")}streak</span></div>
      <div class="card stat"><b>${hours < 10 ? hours.toFixed(1) : Math.round(hours)}</b><span>hours</span></div>
      <div class="card stat"><b>${goalsDone}<small>/${goalsAll}</small></b><span>goals</span></div>
    </div>
    <section class="card heat">${heatmap(p)}<div class="legend"><span><i class="d"></i>done</span><span><i class="r"></i>rest</span><span><i class="ms"></i>${esc((p.milestones.find((m) => m.day !== p.end) || { label: "milestone" }).label.toLowerCase())}</span><span><i class="end"></i>${esc((p.milestones.find((m) => m.day === p.end) || { label: "end" }).label.toLowerCase())}</span></div></section>
    ${chart(days, ids)}
    ${p.targets.length ? `<div class="goalgrid">${goalBars(p, false)}</div>` : ""}
    ${feelCard(ids)}
    ${runsCard(ids)}
  </main>`;
}

function viewSettings() {
  const st = store.snapshot();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  return `<main class="tabview">
    <button class="backlink" data-tab="review">${icon("left")}Review</button>
    <h1 class="pagetitle">Settings</h1>
    <div class="card opts">
      <label class="opt"><span>Chime</span><input type="checkbox" class="switch" data-pref="sound" ${pref("sound", "1") ? "checked" : ""}></label>
      <label class="opt"><span>Wait before each step</span><input type="checkbox" class="switch" data-pref="hold" ${pref("hold", "0") ? "checked" : ""}></label>
    </div>
    <div class="card opts">
      <div class="opt"><span>Device</span><input class="inline" data-device value="${esc(st.device)}" aria-label="Device name"></div>
      <div class="opt"><span>Synced</span><span class="sub">${last ? last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" }) : "never"}</span></div>
      <div class="opt"><span>To upload</span><span class="sub">${store.pendingCount()}</span></div>
      ${st.problem ? `<div class="warn">${esc(st.problem)}</div>` : ""}
      <div class="row gap wrap btns"><button class="soft" data-sync>Sync now</button><button class="soft" data-export>Download</button><button class="soft danger" data-signout>Disconnect</button></div>
    </div>
  </main>`;
}

function viewSetup() {
  return `<main class="setup">
    <div class="card">
      <div class="row gap"><img class="logo" src="icon-192.png" alt=""><h1 class="pagetitle">${APP_NAME}</h1></div>
      <form data-form="server" class="col gap">
        <input name="link" placeholder="Setup link" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
        <details><summary class="sub">Supabase</summary>
          <input name="url" placeholder="Project URL" autocomplete="off" autocapitalize="off" aria-label="Project URL">
          <input name="key" placeholder="Anon key" autocomplete="off" autocapitalize="off" aria-label="Anon public key">
        </details>
        <button class="primary xl">Continue</button>
      </form>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </div>
  </main>`;
}

function sheetPick() {
  const list = P.projects();
  const cur = P.current(list);
  return `<div class="sheet" data-sheet-close><div class="sheet-card"><span class="grab"></span>${list
    .map((q) => `<button class="steprow ${cur && q.id === cur.id ? "on" : ""}" data-project="${esc(q.id)}"><span class="grow">${esc(q.name)}</span><em>${esc(shortDate(q.start))} – ${esc(shortDate(q.end))}</em></button>`)
    .join("")}</div></div>`;
}

function openEditor() {
  const p = P.current();
  if (!p) return;
  ui.draft = { id: p.id, name: p.name, goal: p.goal, start: p.start, end: p.end, targets: [...p.targets], milestones: p.milestones.map((m) => ({ ...m })) };
  ui.draftError = "";
  ui.sheet = "edit";
  render();
}

function sheetEdit() {
  const d = ui.draft;
  if (!d) return "";
  return `<div class="sheet" data-sheet-close><div class="sheet-card form"><span class="grab"></span>
    <div class="row spread"><span class="sheettitle">Project</span><button class="ib" data-sheet-close aria-label="Close">${icon("close")}</button></div>
    <label class="tfld"><span>Name</span><input data-draft="name" value="${esc(d.name)}" maxlength="80"></label>
    <label class="tfld"><span>Goal</span><input data-draft="goal" value="${esc(d.goal)}" maxlength="200"></label>
    <div class="row gap"><label class="tfld grow"><span>Start</span><input type="date" data-draft="start" value="${esc(d.start)}"></label><label class="tfld grow"><span>Goal date</span><input type="date" data-draft="end" value="${esc(d.end)}"></label></div>
    <div class="cap">${icon("flag")}Targets</div>
    ${d.targets.map((t, i) => `<div class="lrow"><input data-draft="target:${i}" value="${esc(t)}" maxlength="80" aria-label="Target ${i + 1}"><button class="ib" data-draftdel="target:${i}" aria-label="Remove">${icon("minus")}</button></div>`).join("")}
    <button class="addrow" data-draftadd="target">${icon("plus")}</button>
    <div class="cap">${icon("gym")}Milestones</div>
    ${d.milestones.map((m, i) => `<div class="lrow"><input type="date" class="date" data-draft="mday:${i}" value="${esc(m.day)}" aria-label="Milestone date"><input data-draft="mlabel:${i}" value="${esc(m.label)}" maxlength="40" aria-label="Milestone label"><button class="ib" data-draftdel="milestone:${i}" aria-label="Remove">${icon("minus")}</button></div>`).join("")}
    <button class="addrow" data-draftadd="milestone">${icon("plus")}</button>
    ${ui.draftError ? `<div class="warn">${esc(ui.draftError)}</div>` : ""}
    <button class="primary xl" data-saveproject>Save</button>
  </div></div>`;
}

function saveDraft() {
  const d = ui.draft;
  const p = P.projects().find((q) => q.id === (d && d.id));
  if (!d || !p) {
    ui.sheet = null;
    return render();
  }
  if (!P.isDay(d.start) || !P.isDay(d.end)) {
    ui.draftError = "Dates";
    return render();
  }
  if (d.end < d.start) {
    ui.draftError = "Goal date is before start";
    return render();
  }
  const targets = d.targets.map((t) => String(t).trim()).filter(Boolean);
  const milestones = d.milestones.map((m) => ({ day: m.day, label: String(m.label || "").trim() })).filter((m) => P.isDay(m.day) && m.label);
  const wasDone = new Set([...p.achieved].map((i) => p.targets[i]));
  const feel = targets
    .map((t, i) => (wasDone.has(t) ? i : -1))
    .filter((i) => i >= 0)
    .join(",");
  const next = { ...p, name: String(d.name || "").trim() || String(p.routine.name || "Project"), goal: String(d.goal || "").trim(), start: d.start, end: d.end, targets, milestones };
  P.saveProject(next, { feel: feel || null });
  ui.sheet = null;
  ui.draft = null;
  toast("Saved");
}

function openLog(kind) {
  const p = P.current();
  ui.logd = { kind: KINDS.some(([k]) => k === kind) ? kind : "run", day: R.today(), rid: p ? p.id : "", min: "", km: "", skips: "", sets: "", feel: 0, notes: "" };
  ui.sheet = "log";
  render();
}

function logPace(l) {
  const min = Number(String(l.min).replace(",", "."));
  const km = Number(String(l.km).replace(",", "."));
  return min > 0 && km > 0 ? pace(min * 60, km) : "";
}

function sheetLog() {
  const l = ui.logd;
  if (!l) return "";
  const list = P.projects();
  const proj = list.find((q) => q.id === l.rid);
  const fld = (k, label, mode = "decimal") => `<label class="fld"><span>${label}</span><input data-lg="${k}" inputmode="${mode}" value="${esc(l[k])}"></label>`;
  let fields = "";
  if (l.kind === "run" || l.kind === "walk") fields = `${fld("min", "min")}${fld("km", "km")}`;
  else if (l.kind === "rope") fields = `${fld("skips", "skips", "numeric")}${fld("sets", "sets", "numeric")}${fld("min", "min")}`;
  else fields = fld("min", "min");
  return `<div class="sheet" data-sheet-close><div class="sheet-card form"><span class="grab"></span>
    <div class="row spread"><span class="sheettitle">Log</span><label class="datechip"><span>${l.day === R.today() ? "Today" : esc(dateLabel(l.day))}</span><input type="date" data-lg="day" value="${esc(l.day)}" aria-label="Date"></label></div>
    ${list.length ? `<label class="pill selpill"><span>${esc(proj ? proj.name : "—")}</span>${icon("down")}<select data-lg="rid" aria-label="Project">${list.map((q) => `<option value="${esc(q.id)}" ${q.id === l.rid ? "selected" : ""}>${esc(q.name)}</option>`).join("")}</select></label>` : ""}
    <div class="kseg">${KINDS.map(([k, label]) => `<button class="${l.kind === k ? "on" : ""}" data-kind="${k}">${icon(k)}${label}</button>`).join("")}</div>
    <div class="row gap">${fields}</div>
    ${l.kind === "run" || l.kind === "walk" ? `<p class="sub center-text" data-lpace>${logPace(l)}</p>` : ""}
    <div class="feelrow">${icon("heart")}${[1, 2, 3, 4, 5].map((n) => `<button class="feeln ${l.feel === n ? "on" : ""}" data-feeln="${n}">${n}</button>`).join("")}</div>
    <label class="notes"><span class="sr">Notes</span><input data-lg="notes" placeholder="Notes" value="${esc(l.notes)}" maxlength="400"></label>
    <button class="primary xl" data-savelog>Save</button>
  </div></div>`;
}

function numIn(v, max, int) {
  const n = Number(String(v ?? "").trim().replace(",", "."));
  if (!Number.isFinite(n) || n <= 0) return 0;
  const c = Math.min(n, max);
  return int ? Math.round(c) : Math.round(c * 100) / 100;
}

function saveLogSheet() {
  const l = ui.logd;
  if (!l) return;
  const min = numIn(l.min, 1440, false);
  const km = l.kind === "run" || l.kind === "walk" ? numIn(l.km, 300, false) : 0;
  const skips = l.kind === "rope" ? numIn(l.skips, 100000, true) : 0;
  const sets = l.kind === "rope" ? numIn(l.sets, 500, true) : 0;
  if (!min && !km && !skips) return toast("Add a number");
  const day = P.isDay(l.day) ? l.day : R.today();
  const proj = P.projects().find((q) => q.id === l.rid);
  const label = (KINDS.find(([k]) => k === l.kind) || ["other", "Other"])[1];
  const id = `workout|${newId()}`;
  const data = { id, routine: proj ? proj.id : "", routineName: proj ? String(proj.routine.name || "") : "", tag: "workout", step: l.kind, title: label, day, slot: "", updated: isoNow() };
  if (min) data.seconds = Math.round(min * 60);
  if (km) data.km = km;
  if (skips) data.text = String(skips);
  if (sets) data.lines = [String(sets)];
  if (l.feel >= 1 && l.feel <= 5) data.feel = String(l.feel);
  if (String(l.notes || "").trim()) data.notes = String(l.notes).trim().slice(0, 400);
  store.put("runner.entry", id, data);
  ui.sheet = null;
  ui.logd = null;
  toast("Saved");
}

function sheetPreview() {
  const p = P.current();
  if (!p || !P.isDay(ui.day)) return "";
  const info = P.dayInfo(p, ui.day);
  return `<div class="sheet" data-sheet-close><div class="sheet-card"><span class="grab"></span>
    <div class="row spread"><span class="sheettitle">${esc(dateLabel(ui.day))}</span><button class="ib" data-sheet-close aria-label="Close">${icon("close")}</button></div>
    ${info.steps
      .map((st) => {
        const run = runOf(st);
        const moves = Array.isArray(run.moves) ? run.moves.filter((m) => m && m.name) : [];
        const seg = P.segments(st);
        let body = "";
        if (moves.length) body = moves.map((m) => `<div class="mv"><span class="grow">${esc(m.name)}${m.detail ? ` <small>${esc(m.detail)}</small>` : ""}</span><span class="amt">${m.seconds ? clock(Number(m.seconds) || 0) : m.reps ? esc(String(m.reps)) : ""}</span></div>`).join("");
        if (run.type === "rounds") body = `<div class="mv"><span class="grow"><b>${esc(P.compact(st))}</b></span><span class="amt">${run.rest ? `${icon("timer")}${clock(Number(run.rest) || 0)}` : ""}</span></div>` + body;
        if (seg) body = `<div class="mv"><span class="grow">${esc(P.compact(st))}</span><span class="amt">${esc(seg.onName.toLowerCase())} ${clock(seg.on)}${seg.off ? ` · ${esc(seg.offName.toLowerCase())} ${clock(seg.off)}` : ""}</span></div>`;
        if (run.type === "log") body = `<div class="mv"><span class="grow">${esc(run.plan || split(st.title).detail)}</span></div>`;
        return `<div class="pv"><div class="hd">${stepIcon(st)}<span class="grow">${esc(split(st.title).name)}</span><em>${minutes(estimate(st))}m</em></div>${body}${st.tip ? `<p class="tip">${esc(st.tip)}</p>` : ""}</div>`;
      })
      .join("")}
  </div></div>`;
}

function sheet() {
  if (ui.sheet === "pick") return sheetPick();
  if (ui.sheet === "edit") return sheetEdit();
  if (ui.sheet === "log") return sheetLog();
  if (ui.sheet === "preview") return sheetPreview();
  return "";
}

function viewTab() {
  const views = { today: viewToday, scheduled: viewScheduled, start: viewStart, review: viewReview, day: viewDay, settings: viewSettings };
  if (!views[ui.view]) ui.view = ui.tab;
  document.body.dataset.mood = "";
  return (views[ui.view] || viewToday)() + tabBar();
}

function render() {
  const app = $("#app");
  if (!app) return;
  try {
    if (!store.signedIn()) {
      document.body.dataset.mood = "";
      app.innerHTML = viewSetup();
      return;
    }
    if (run && ui.view !== "done" && ui.view !== "run" && !session()) {
      run = null;
      saveRun();
    }
    let html;
    if (ui.view === "run") html = viewRun();
    else if (ui.view === "done") html = viewDone();
    else html = viewTab() + sheet();
    document.body.classList.toggle("locked", !!ui.sheet || ui.steps);
    app.innerHTML = html + (ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : "");
  } catch (e) {
    console.warn("ventus render", e);
    app.innerHTML = `<main class="tabview"><p class="quiet">Something in the data could not be shown.</p></main>` + tabBar();
  }
}

function tickClock() {
  if (!run || ui.view !== "run" || ui.steps) return;
  const s = session();
  if (!s || !s.beat) return;
  const b = s.beat;
  const el0 = document.querySelector("[data-elapsed]");
  if (el0) el0.textContent = clock(elapsed());
  if ((b.kind === "count" || b.kind === "rest") && !run.paused) {
    const left = remaining();
    const el = document.querySelector("[data-clock]");
    if (el) el.textContent = clock(left);
    const ringEl = document.querySelector("[data-ring]");
    if (ringEl && b.seconds) ringEl.setAttribute("stroke-dashoffset", (Number(ringEl.dataset.ring) * (1 - left / b.seconds)).toFixed(1));
    if (b.cues && b.cues.length) {
      const cue = cueNow(b);
      const cueEl = document.querySelector("[data-cue]");
      if (cue && cueEl && !cueEl.textContent.endsWith(cue.text)) render();
    }
    if (b.reads && b.reads.length) {
      const read = readNow(b);
      const readEl = document.querySelector("[data-read] p");
      if (readEl && read && readEl.textContent !== read) render();
    }
    if (left <= 0) return advance();
  }
  const soft = softLeft(b);
  const softEl = document.querySelector("[data-soft]");
  if (softEl && soft != null) softEl.textContent = clock(soft);
}

function toast(text) {
  ui.toast = text;
  render();
  clearTimeout(toast.t);
  toast.t = setTimeout(() => {
    ui.toast = "";
    render();
  }, 2000);
}

function go(view) {
  if (["today", "scheduled", "start", "review"].includes(view)) ui.tab = view;
  ui.view = view;
  ui.steps = false;
  ui.sheet = null;
  render();
  window.scrollTo(0, 0);
}

function saveLog() {
  const s = session();
  if (!s || !s.beat || s.beat.kind !== "log") return;
  const time = parseDuration(document.querySelector('[data-log="time"]')?.value);
  const kmText = (document.querySelector('[data-log="km"]')?.value || "").replace(",", ".");
  const kmNum = kmText ? Math.round(Number(kmText) * 100) / 100 : null;
  const notes = (document.querySelector('[data-log="notes"]')?.value || "").trim().slice(0, 400);
  const patch = { seconds: time && time > 0 && time < 86400 ? time : null, km: Number.isFinite(kmNum) && kmNum > 0 && kmNum < 300 ? kmNum : null, notes };
  const p = document.querySelector("[data-pace]");
  if (p) p.textContent = patch.seconds && patch.km ? pace(patch.seconds, patch.km) : "";
  if (run.adhoc) {
    run.log = { ...(run.log || {}), ...patch };
    saveRun();
    return;
  }
  if (!patch.seconds && !patch.km && !notes) return;
  R.saveEntry(entryBase(s), patch);
}

function saveWrite() {
  const s = session();
  if (!s || !s.beat || s.beat.kind !== "write") return;
  const lineEls = [...document.querySelectorAll("[data-line]")];
  const text = document.querySelector("[data-para]")?.value.trim() || "";
  if (run.adhoc) {
    run.log = { ...(run.log || {}), ...(lineEls.length ? { lines: lineEls.map((el) => el.value.trim()) } : { text }) };
    saveRun();
    return;
  }
  const base = entryBase(s);
  if (lineEls.length) {
    const lines = lineEls.map((el) => el.value.trim());
    if (lines.some(Boolean) || R.entry(base.id)) R.saveEntry(base, { lines });
  } else if (text || R.entry(base.id)) R.saveEntry(base, { text });
}

function setDraft(key, value) {
  const d = ui.draft;
  if (!d) return;
  const [k, i] = key.split(":");
  const n = Number(i);
  if (k === "name" || k === "goal" || k === "start" || k === "end") d[k] = value;
  else if (k === "target" && Number.isInteger(n) && n < d.targets.length) d.targets[n] = value;
  else if (k === "mday" && d.milestones[n]) d.milestones[n].day = value;
  else if (k === "mlabel" && d.milestones[n]) d.milestones[n].label = value;
}

let writeTimer = null;

document.addEventListener("input", (e) => {
  const t = e.target;
  if (t.matches("[data-line], [data-para]")) {
    clearTimeout(writeTimer);
    writeTimer = setTimeout(saveWrite, 700);
  } else if (t.matches("[data-log]")) {
    clearTimeout(writeTimer);
    writeTimer = setTimeout(saveLog, 700);
  } else if (t.matches("[data-draft]")) setDraft(t.dataset.draft, t.value);
  else if (t.matches("[data-lg]") && ui.logd) {
    const k = t.dataset.lg;
    if (k === "day" || k === "rid") return;
    ui.logd[k] = t.value;
    const el = document.querySelector("[data-lpace]");
    if (el) el.textContent = logPace(ui.logd);
  }
});

document.addEventListener("change", (e) => {
  const t = e.target;
  if (t.matches("[data-pref]")) setPref(t.dataset.pref, t.checked);
  if (t.matches("[data-device]")) store.setDevice(t.value);
  if (t.matches("[data-draft]")) setDraft(t.dataset.draft, t.value);
  if (t.matches("[data-lg]") && ui.logd && (t.dataset.lg === "day" || t.dataset.lg === "rid")) {
    if (t.dataset.lg === "day") ui.logd.day = P.isDay(t.value) ? t.value : R.today();
    else ui.logd.rid = t.value;
    render();
  }
});

function startDay(day) {
  const p = P.current();
  if (!p) return;
  const info = P.dayInfo(p, day);
  if (!info.total) return;
  if (day === R.today()) {
    const open = info.sessions.find((x) => x.done < x.steps.length) || info.sessions[0];
    const going = inProgress(p.id, day, open.slot);
    if (going) return go("run");
    return startSession(p.id, day, open.slot);
  }
  startAdhoc(p.routine, day, info.steps, `${P.sessionTitle(info.steps)}`);
}

document.addEventListener("click", async (e) => {
  if (e.target.matches("[data-close-steps]")) {
    ui.steps = false;
    return render();
  }
  if (e.target.matches(".sheet[data-sheet-close]")) {
    ui.sheet = null;
    return render();
  }
  const t = e.target.closest("button");
  if (!t || t.disabled) return;
  const d = t.dataset;
  if (d.sheetClose !== undefined) {
    ui.sheet = null;
    return render();
  }
  if (d.tab) return go(d.tab);
  if (d.day) {
    ui.day = d.day;
    const p = P.current();
    if (p) {
      const at = P.weeks(p).indexOf(weekStart(d.day));
      if (at >= 0) {
        ui.week = at;
        ui.weekFor = p.id;
      }
    }
    ui.tab = "scheduled";
    return go("day");
  }
  if (d.week) {
    ui.week = (ui.week || 0) + Number(d.week);
    return render();
  }
  if (d.pick !== undefined) {
    ui.sheet = "pick";
    return render();
  }
  if (d.project) {
    P.writePick(d.project);
    ui.week = null;
    ui.sheet = null;
    return render();
  }
  if (d.edit !== undefined) return openEditor();
  if (d.draftadd && ui.draft) {
    if (d.draftadd === "target") ui.draft.targets.push("");
    else ui.draft.milestones.push({ day: R.today(), label: "" });
    return render();
  }
  if (d.draftdel && ui.draft) {
    const [k, i] = d.draftdel.split(":");
    if (k === "target") ui.draft.targets.splice(Number(i), 1);
    else ui.draft.milestones.splice(Number(i), 1);
    return render();
  }
  if (d.saveproject !== undefined) return saveDraft();
  if (d.goal) {
    const p = P.current();
    const i = Number(d.goal);
    if (p && Number.isInteger(i) && i >= 0 && i < p.targets.length) P.toggleTarget(p, i);
    return;
  }
  if (d.scope) {
    ui.scope = d.scope;
    return render();
  }
  if (d.settings !== undefined) return go("settings");
  if (d.session) {
    const [id, day, slot] = d.session.split("|");
    if (inProgress(id, day, slot)) return go("run");
    return startSession(id, day, slot);
  }
  if (d.startday) return startDay(d.startday);
  if (d.starttoday !== undefined) return startDay(R.today());
  if (d.tile) {
    const tile = (ui.tiles || [])[Number(d.tile)];
    const p = P.current();
    if (tile && p) startAdhoc(p.routine, R.today(), [tile.step], tile.name);
    return;
  }
  if (d.preview !== undefined) {
    ui.sheet = "preview";
    return render();
  }
  if (d.logkind) return openLog(d.logkind);
  if (d.kind && ui.logd) {
    ui.logd.kind = d.kind;
    return render();
  }
  if (d.feeln && ui.logd) {
    const n = Number(d.feeln);
    ui.logd.feel = ui.logd.feel === n ? 0 : n;
    return render();
  }
  if (d.savelog !== undefined) return saveLogSheet();
  if (d.home !== undefined) {
    if (ui.view === "done") {
      run = null;
      saveRun();
    }
    return go(ui.tab);
  }
  if (d.resume !== undefined) return go("run");
  if (d.end !== undefined) {
    if (confirm(run && run.adhoc ? "End this workout?" : "End this session? Finished steps stay ticked in Aqua.")) endRun();
    return;
  }
  if (d.steps !== undefined) {
    ui.steps = true;
    return render();
  }
  if (d.jump) {
    const s = session();
    const i = s ? s.beats.findIndex((b) => b.step === Number(d.jump)) : -1;
    if (i >= 0) {
      run.i = i;
      enterBeat(s.beats[i], true);
    }
    ui.steps = false;
    return render();
  }
  if (d.pause !== undefined) return togglePause();
  if (d.back !== undefined) return back();
  if (d.more) return addRest(Number(d.more));
  if (d.skip !== undefined) {
    clearTimeout(writeTimer);
    saveWrite();
    saveLog();
    return advance();
  }
  if (d.skipWrite !== undefined || d.later !== undefined) {
    clearTimeout(writeTimer);
    const s = session();
    if (!s) return endRun();
    const next = s.beats[run.i + 1];
    if (!next) {
      finish();
      return render();
    }
    run.i += 1;
    enterBeat(next, next.step !== s.beat.step);
    return render();
  }
  if (d.said !== undefined) {
    const s = session();
    if (!s) return;
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
  if (d.feel) {
    const s = session();
    if (s && run.adhoc && run.workoutId) {
      const prev = R.entry(run.workoutId);
      if (prev) store.put("runner.entry", run.workoutId, { ...prev, feel: FEEL_NUM[d.feel] || "3", updated: isoNow() });
    } else if (s) R.saveEntry({ id: R.entryId(s.routine.id, run.day, run.slot, "feel"), routine: s.routine.id, routineName: s.routine.name, day: run.day, slot: run.slot, step: "feel", title: s.routine.name, tag: "feel" }, { feel: d.feel });
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
    a.download = `ventus-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    return;
  }
  if (d.signout !== undefined) {
    if (confirm("Disconnect this device? Anything not yet uploaded is lost.")) store.disconnect();
  }
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  if (e.target.dataset.form !== "server") return;
  const f = new FormData(e.target);
  const fromLink = parseLink(f.get("link") || "");
  const url = fromLink?.url || f.get("url");
  const key = fromLink?.key || f.get("key");
  if (!url || !key) {
    ui.setupError = "Paste the whole setup link.";
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
  if (ui.sheet === "edit" || ui.sheet === "log") return;
  if (active && active.matches && active.matches("textarea, input")) return;
  render();
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && run && ui.view === "run") {
    keepAwake(true);
    tickClock();
  }
});

readSetupLink();
store.subscribe(onStore);
if (run && session() && !run.finished) ui.view = "run";
if (run && run.finished) {
  run = null;
  saveRun();
}
render();
setInterval(tickClock, 250);
requestAnimationFrame(tickBox);
setInterval(() => {
  if (["today", "scheduled", "start", "review"].includes(ui.view) && !ui.sheet) render();
}, 60000);
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
