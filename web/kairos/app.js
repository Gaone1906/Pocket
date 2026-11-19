import * as store from "./store.js";
import { $, esc, ICONS, readLocal, writeLocal, dayTitle, fmtTime } from "./util.js";
import * as R from "./routines.js";
import { beatsForSteps, estimate, howLabel, clock, minutes, split, runOf, plainDetail } from "./plan.js";

const APP_NAME = "Kairos";
const RUN_KEY = "runner.run.v1";
const TAGS = [
  ["all", "All"],
  ["gratitude", "Gratitude"],
  ["win", "Wins"],
  ["script", "Scripts"],
  ["action", "Actions"],
  ["review", "Reviews"],
  ["run", "Runs"],
];
const TAG_LABEL = { gratitude: "Gratitude", win: "Win", script: "Script", action: "One action", review: "Weekly review", run: "Run", feel: "How it felt", note: "Note" };
const FEELS = [
  ["easy", "Easy"],
  ["right", "Right"],
  ["hard", "Too hard"],
];

const ICON = {
  play: '<svg viewBox="0 0 24 24" class="fill"><path d="M7 4.5v15l13-7.5z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" class="fill"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
  prev: '<svg viewBox="0 0 24 24" class="fill"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg>',
  next: '<svg viewBox="0 0 24 24" class="fill"><path d="M16 5h2v14h-2zM4 5v14l11-7z"/></svg>',
  list: '<svg viewBox="0 0 24 24"><path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/></svg>',
  book: '<svg viewBox="0 0 24 24"><path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M9 9h6M9 13h6"/></svg>',
  search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg>',
};

const ui = {
  view: "today",
  pick: null,
  setupError: "",
  toast: "",
  tag: "all",
  query: "",
  steps: false,
  open: null,
};

let run = loadRun();
let lock = null;
let audio = null;

const pref = (k, d) => readLocal("runner." + k, d) === "1";
const setPref = (k, on) => writeLocal("runner." + k, on ? "1" : "0");

function loadRun() {
  try {
    const saved = JSON.parse(readLocal(RUN_KEY, "null"));
    if (saved && saved.routineId) return saved;
  } catch (e) {}
  return null;
}

function saveRun() {
  writeLocal(RUN_KEY, run ? JSON.stringify(run) : null);
}

function session() {
  if (!run) return null;
  const routine = R.routine(run.routineId);
  if (!routine) return null;
  const steps = R.stepsOn(routine, run.day, run.slot);
  const beats = beatsForSteps(steps);
  return { routine, steps, beats, beat: beats[run.i] };
}

function routineTitle(routine, day, slot) {
  const n = R.dayNumber(routine, day);
  return `${routine.name}${n ? ` · Day ${n.n}` : ""}`;
}

function slotLabel(slot) {
  return slot === "morning" ? "Morning" : "Night";
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

function startSession(routineId, day, slot) {
  const routine = R.routine(routineId);
  if (!routine) return;
  const steps = R.stepsOn(routine, day, slot);
  const beats = beatsForSteps(steps);
  const first = steps.findIndex((s) => !R.isDone(routineId, day, slot, s.id));
  const i = Math.max(0, beats.findIndex((b) => b.step === (first < 0 ? 0 : first)));
  run = { routineId, day, slot, i, started: Date.now(), stepStarted: Date.now(), spent: {}, paused: false, waiting: false, left: null, endsAt: null, say: { line: 0, said: 0 } };
  enterBeat(beats[i], true);
  ui.view = "run";
  ui.steps = false;
  keepAwake(true);
  if (audio && audio.state === "suspended") audio.resume();
  render();
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
  R.tick(s.routine.id, run.day, run.slot, step.id);
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
  const used = run.paused && !run.waiting ? 0 : (Date.now() - run.stepStarted) / 1000;
  return Math.max(0, beat.guide - used);
}

function sessionLeft(s) {
  let total = 0;
  s.steps.forEach((step, i) => {
    if (i > s.beat.step) total += estimate(step);
  });
  const here = s.beats.filter((b, i) => i > run.i && b.step === s.beat.step).reduce((n, b) => n + (b.seconds || 0) + (b.kind === "reps" ? 30 : 0), 0);
  return total + here + (run.left != null ? remaining() : 0);
}

function ring(size, stroke, fraction, color, track) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return `<svg class="ring" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${track}" stroke-width="${stroke}"/><circle data-ring="${c.toFixed(1)}" cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${(c * (1 - fraction)).toFixed(1)}" transform="rotate(-90 ${size / 2} ${size / 2})"/></svg>`;
}

function topBar(s) {
  const steps = s.steps.length;
  const segs = s.steps
    .map((_, i) => {
      if (i < s.beat.step || R.isDone(s.routine.id, run.day, run.slot, s.steps[i].id) && i !== s.beat.step) return `<span class="seg done"></span>`;
      if (i > s.beat.step) return `<span class="seg"></span>`;
      const mine = s.beats.filter((b) => b.step === i);
      const at = mine.indexOf(s.beat);
      const pct = Math.round(((at + 0.5) / mine.length) * 100);
      return `<span class="seg" style="--p:${pct}%"></span>`;
    })
    .join("");
  return `
    <div class="runbar">
      <button class="icon" data-end aria-label="End session">${ICONS.close}</button>
      <div class="runtitle"><b>${esc(routineTitle(s.routine, run.day, run.slot))} · ${slotLabel(run.slot)}</b><span>Step ${s.beat.step + 1} of ${steps} · <span data-left>${minutes(sessionLeft(s))}</span> min left</span></div>
      <button class="icon" data-steps aria-label="Show steps">${ICON.list}</button>
    </div>
    <div class="segs">${segs}</div>`;
}

function stepsSheet(s) {
  if (!ui.steps) return "";
  return `<div class="sheet" data-close-sheet><div class="sheet-card"><h3>Steps</h3>${s.steps
    .map((step, i) => {
      const { name, detail } = split(step.title);
      const done = R.isDone(s.routine.id, run.day, run.slot, step.id);
      return `<button class="steprow ${i === s.beat.step ? "on" : ""}" data-jump="${i}"><span class="dot ${done ? "done" : ""}">${done ? ICONS.check : i + 1}</span><span class="grow"><b>${esc(name)}</b><small>${esc(detail)}</small></span></button>`;
    })
    .join("")}<button class="ghost wide" data-close-sheet>Close</button></div></div>`;
}

function controls(primary) {
  return `<div class="controls">
    <button class="round" data-back aria-label="Previous" ${run.i === 0 ? "disabled" : ""}>${ICON.prev}</button>
    ${primary}
    <button class="round" data-skip aria-label="Next">${ICON.next}</button>
  </div>`;
}

function pauseButton() {
  return `<button class="round big" data-pause aria-label="${run.paused ? "Resume" : "Pause"}">${run.paused ? ICON.play : ICON.pause}</button>`;
}

function upNext(s) {
  const next = s.beats[run.i + 1];
  if (!next) return `<div class="upnext"><span>Last one</span><b>Then you're done</b></div>`;
  const step = s.steps[next.step];
  if (next.step !== s.beat.step) {
    const { name, detail } = split(step.title);
    return `<div class="upnext"><span>Up next</span><b>${esc(name)}${detail ? ` · ${esc(detail)}` : ""}</b></div>`;
  }
  if (next.kind === "rest") return `<div class="upnext"><span>Then</span><b>rest ${clock(next.seconds)}${next.nextName ? `, then ${esc(next.nextName)}` : ""}</b></div>`;
  return `<div class="upnext"><span>Up next</span><b>${next.reps ? next.reps + " " : ""}${esc(next.name)}</b></div>`;
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
      const amount = m.seconds ? clock(m.seconds) : m.reps ? `${m.reps}${m.detail && /each|side|leg|way/.test(m.detail) ? "" : ""}` : "";
      return `<div class="mv ${state}"><span class="mk">${state === "done" ? "✓" : state === "now" ? "●" : "○"}</span><span class="grow">${esc(m.name)}</span><span class="amt">${esc(amount)}${m.detail && m.reps ? ` <small>${esc(m.detail)}</small>` : ""}</span></div>`;
    })
    .join("")}</div>`;
}

function waitingCard(s) {
  const step = s.steps[s.beat.step];
  const { name, detail } = split(step.title);
  return `
    <div class="center grow">
      <span class="kicker">Ready when you are</span>
      <h1 class="huge">${esc(name)}</h1>
      ${detail ? `<p class="lead">${esc(detail)}</p>` : ""}
      ${step.tip ? `<div class="card note">${esc(step.tip)}</div>` : ""}
    </div>
    <button class="primary xl" data-pause>Start ${esc(name)}</button>`;
}

function viewCount(s) {
  const b = s.beat;
  const left = remaining();
  const cue = cueNow(b);
  const fraction = b.seconds ? left / b.seconds : 0;
  if (b.hot) {
    return `
      <div class="center grow">
        <span class="kicker hot">${esc(b.label)}</span>
        <h1 class="huge">${esc(b.name)}</h1>
        <div class="bigclock" data-clock>${clock(left)}</div>
        ${b.tip ? `<p class="lead clamp">${esc(firstSentences(b.tip))}</p>` : ""}
      </div>
      <div class="pips">${Array.from({ length: b.rounds }, (_, i) => `<span class="${i < b.round ? "done" : i === b.round ? "now" : ""}">${i + 1}</span>`).join("")}</div>
      ${upNext(s)}
      ${controls(pauseButton())}`;
  }
  if (b.list) {
    return `
      <div class="head">
        <span class="kicker">${esc(b.label)}</span>
        <h1 class="huge">${esc(b.name)}</h1>
        ${b.detail ? `<p class="lead">${esc(b.detail)}</p>` : ""}
      </div>
      <div class="center">
        <div class="ringbox mid">${ring(200, 10, fraction, "var(--accent)", "var(--line)")}<div class="ringtext"><span class="clock" data-clock>${clock(left)}</span></div></div>
      </div>
      ${moveList(b)}
      <div class="grow"></div>
      ${controls(pauseButton())}`;
  }
  return `
    <div class="center grow">
      <span class="kicker">${esc(b.label || runLabel(b))}</span>
      <h1 class="title">${esc(b.name)}</h1>
      <div class="ringbox">${ring(260, 10, fraction, "var(--accent)", "var(--line)")}<div class="ringtext"><span class="clock" data-clock>${clock(left)}</span><small>of ${clock(b.seconds)}</small></div></div>
      ${cue ? `<div class="card note" data-cue><small>Now</small>${esc(cue.text)}</div>` : b.tip ? `<details class="card note"><summary>How to</summary>${esc(b.tip)}</details>` : ""}
    </div>
    ${upNext(s)}
    ${controls(pauseButton())}`;
}

function runLabel(b) {
  return b.detail || "";
}

function firstSentences(text) {
  const parts = String(text).split(/(?<=\.)\s+/);
  return parts.slice(0, 2).join(" ");
}

function viewRest(s) {
  const b = s.beat;
  const left = remaining();
  const next = s.beats[run.i + 1];
  return `
    <div class="center grow">
      <span class="kicker">${esc(b.name)}</span>
      <p class="lead">${esc(b.label)}</p>
      <div class="ringbox">${ring(250, 10, b.seconds ? left / b.seconds : 0, "var(--rest)", "var(--line)")}<div class="ringtext"><span class="clock" data-clock>${clock(left)}</span></div></div>
      <div class="chips"><button class="ghost" data-more="15">+15s</button><button class="ghost" data-skip>Skip rest</button>${run.paused ? `<button class="ghost" data-pause>Resume</button>` : `<button class="ghost" data-pause>Pause</button>`}</div>
    </div>
    ${next ? `<div class="card nextcard"><small>Get ready${b.rounds && !b.intervals ? ` · ${b.unit || "round"} ${b.round + 2} of ${b.rounds}` : ""}</small><b>${next.reps ? next.reps + " " : ""}${esc(next.name)}</b>${b.nextList ? `<span>then ${esc(b.nextList.slice(1).join(", "))}</span>` : ""}</div>` : ""}`;
}

function viewReps(s) {
  const b = s.beat;
  const soft = softLeft(b);
  return `
    <div class="row spread">
      <span class="kicker">${esc(b.label || "")}</span>
      ${b.list ? `<span class="sub">Move ${b.at + 1} of ${b.list.length}</span>` : ""}
    </div>
    <div class="grow col center-y">
      ${b.reps ? `<div class="repcount">${b.reps}</div>` : ""}
      <h1 class="huge">${esc(b.name)}</h1>
      ${b.detail ? `<p class="lead">${esc(b.detail)}</p>` : ""}
      ${!b.list && b.tip ? `<div class="card note">${esc(b.tip)}</div>` : ""}
      ${soft != null ? `<p class="sub">About <span data-soft>${clock(soft)}</span> left for this step</p>` : ""}
    </div>
    ${moveList(b)}
    <div class="row gap">
      <button class="round" data-back aria-label="Previous" ${run.i === 0 ? "disabled" : ""}>${ICON.prev}</button>
      <button class="primary xl grow" data-skip>Done</button>
    </div>`;
}

function viewSay(s) {
  const b = s.beat;
  const lines = b.lines.length ? b.lines : [b.detail || b.name];
  const at = Math.min(run.say.line, lines.length - 1);
  const soft = softLeft(b);
  return `
    <div class="row spread"><h2 class="title">${esc(b.name)}</h2>${soft != null ? `<span class="softclock" data-soft>${clock(soft)}</span>` : ""}</div>
    ${b.detail ? `<p class="sub">${esc(b.detail)} · each line ${b.times} time${b.times === 1 ? "" : "s"}</p>` : ""}
    <div class="grow col center-y">
      <span class="kicker">Line ${at + 1} of ${lines.length}</span>
      <p class="sayline">${esc(lines[at])}</p>
      <div class="dots">${Array.from({ length: b.times }, (_, i) => `<span class="${i < run.say.said ? "lit" : ""}"></span>`).join("")}<small>Said ${run.say.said} of ${b.times} times</small></div>
    </div>
    <div class="saylist">${lines
      .map((l, i) => (i === at ? "" : `<div class="${i < at ? "done" : ""}"><span>${i < at ? "✓" : ""}</span>${esc(l)}</div>`))
      .join("")}</div>
    <button class="primary xl" data-said>Said it</button>`;
}

function entryBase(s) {
  const step = s.steps[s.beat.step];
  return { id: R.entryId(s.routine.id, run.day, run.slot, step.id), routine: s.routine.id, routineName: s.routine.name, day: run.day, slot: run.slot, step: step.id, title: [split(step.title).name, plainDetail(split(step.title).detail)].filter(Boolean).join(" · "), tag: s.beat.tag || (s.beat.type === "log" ? "run" : "note") };
}

function viewWrite(s) {
  const b = s.beat;
  const base = entryBase(s);
  const saved = R.entry(base.id) || {};
  const soft = softLeft(b);
  const lines = b.fields > 1 ? Array.from({ length: b.fields }, (_, i) => (saved.lines || [])[i] || "") : null;
  return `
    <div class="row spread"><h2 class="title">${esc([b.name, b.tag === "script" || b.tag === "action" ? plainDetail(b.detail).replace(/, as if it's done$/, "") : ""].filter(Boolean).join(" · "))}</h2>${soft != null ? `<span class="softclock" data-soft>${clock(soft)}</span>` : ""}</div>
    <p class="sub">${esc(b.prompt || b.tip || b.detail)}</p>
    ${
      lines
        ? `<div class="col gap fields">${lines.map((v, i) => `<label class="field"><span>${i + 1}</span><textarea data-line="${i}" rows="2" placeholder="${i === lines.length - 1 ? "What else went well, and why?" : ""}">${esc(v)}</textarea></label>`).join("")}</div><div class="grow"></div>`
        : `<label class="sr" for="para">Your writing</label><textarea id="para" class="para grow" data-para placeholder="Start writing…">${esc(saved.text || "")}</textarea>`
    }
    <p class="sub center-text">${saved.updated ? `Saved ${fmtTime(new Date(saved.updated))} · ` : ""}The timer is a guide; it won't cut you off.</p>
    <div class="row gap"><button class="ghost xl" data-skip-write>Skip</button><button class="primary xl grow2" data-skip>Save and next</button></div>`;
}

function parseDuration(text) {
  const t = String(text || "").trim();
  if (!t) return null;
  if (t.includes(":")) {
    const [m, sec] = t.split(":").map(Number);
    return Number.isFinite(m) && Number.isFinite(sec) ? m * 60 + sec : null;
  }
  const m = Number(t.replace(",", "."));
  return Number.isFinite(m) ? Math.round(m * 60) : null;
}

function pace(seconds, km) {
  if (!seconds || !km) return "";
  return `${clock(seconds / km)} /km`;
}

function lastRun(before) {
  return R.entries().find((e) => e.tag === "run" && e.km && e.seconds && e.id !== before);
}

function viewLog(s) {
  const b = s.beat;
  const base = entryBase(s);
  const saved = R.entry(base.id) || {};
  const prev = lastRun(base.id);
  return `
    <div class="head">
      <span class="kicker">Today's ${esc(b.name.toLowerCase())}</span>
      <h1 class="huge">${esc(b.plan)}</h1>
    </div>
    ${b.tip ? `<div class="card note">${esc(b.tip)}</div>` : ""}
    <p class="sub">Go and do it. When you're back, enter what you did.</p>
    <div class="row gap">
      <label class="metric"><span>Time</span><div><input data-log="time" inputmode="decimal" placeholder="12:40" value="${saved.seconds ? clock(saved.seconds) : ""}"><small>min</small></div></label>
      <label class="metric"><span>Distance</span><div><input data-log="km" inputmode="decimal" placeholder="1.6" value="${saved.km ?? ""}"><small>km</small></div></label>
    </div>
    <div class="row spread sub"><span data-pace>${saved.seconds && saved.km ? "Pace " + pace(saved.seconds, saved.km) : ""}</span><span>${prev ? `Last: ${prev.km} km in ${clock(prev.seconds)}` : ""}</span></div>
    <label class="field"><span>Notes (optional)</span><textarea data-log="notes" rows="2" placeholder="How it felt, any pain, weather">${esc(saved.notes || "")}</textarea></label>
    <div class="grow"></div>
    <div class="row gap"><button class="ghost xl" data-later>Later</button><button class="primary xl grow2" data-skip>Save and next</button></div>`;
}

function viewRun() {
  const s = session();
  if (!s || !s.beat) {
    run = null;
    saveRun();
    return viewToday();
  }
  document.body.dataset.mood = s.beat.kind === "rest" ? "rest" : s.beat.hot && !run.waiting ? "hot" : "";
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
  if (!s) return viewToday();
  const n = R.dayNumber(s.routine, run.day);
  const ticked = s.steps.filter((st) => R.isDone(s.routine.id, run.day, run.slot, st.id)).length;
  const took = Math.round(((run.finished || Date.now()) - run.started) / 60000);
  const feelId = R.entryId(s.routine.id, run.day, run.slot, "feel");
  const feel = (R.entry(feelId) || {}).feel;
  const left = n ? n.of - n.n : 0;
  return `
    <main class="done">
      <div class="col center gap">
        <div class="bigcheck">${ICONS.check}</div>
        <h1 class="huge">${ticked < s.steps.length ? "Stopped early" : n ? `Day ${n.n} done` : `${esc(s.routine.name)} done`}</h1>
        <p class="sub">${esc(s.routine.name)} · ${took} min${n && left > 0 ? ` · ${left} more to go` : ""}</p>
      </div>
      <div class="card orario"><span class="ologo"></span><div><b>Ticked in Orario</b><small>${ticked} of ${s.steps.length} steps · syncs to every device</small></div></div>
      <div class="list">${s.steps
        .map((st, i) => `<div class="mv done"><span class="mk">${R.isDone(s.routine.id, run.day, run.slot, st.id) ? "✓" : "–"}</span><span class="grow">${esc(split(st.title).name)}</span><span class="amt">${run.spent[i] ? clock(run.spent[i]) : ""}</span></div>`)
        .join("")}</div>
      <div class="col gap">
        <span class="kicker">How did it feel?</span>
        <div class="feel">${FEELS.map(([k, label]) => `<button class="ghost ${feel === k ? "on" : ""}" data-feel="${k}">${label}</button>`).join("")}</div>
      </div>
      <div class="grow"></div>
      <button class="primary xl" data-home>Back to today</button>
    </main>`;
}

function header(title, back) {
  const st = store.snapshot();
  const syncState = st.problem ? "warn" : store.pendingCount() ? "pending" : "ok";
  return `<header>
    ${back ? `<button class="icon" data-home aria-label="Back">${ICONS.left}</button>` : `<span class="logo"></span>`}
    <h2>${esc(title)}</h2>
    <span class="sync ${syncState}" title="${esc(st.problem || (store.pendingCount() ? "Uploading" : "Synced"))}"></span>
    ${back ? "" : `<button class="icon" data-view="settings" aria-label="Settings">${ICONS.settings}</button>`}
  </header>`;
}

function sessionCard(x, primary) {
  const n = R.dayNumber(x.routine, x.day);
  const secs = x.steps.reduce((t, st) => t + estimate(st), 0);
  const names = x.steps.map((st) => split(st.title).name);
  const done = x.done === x.total;
  if (primary) {
    return `<div class="card hero">
      <div class="row spread"><span class="pill">${esc(x.routine.name)}${n ? ` · Day ${n.n} of ${n.of}` : ""}</span><span class="sub">${slotLabel(x.slot)}</span></div>
      <b class="big">${x.total} steps · about ${minutes(secs)} min</b>
      <span class="sub">${esc(names.join(", "))}</span>
      <button class="primary xl" data-before="${x.routine.id}|${x.slot}">${ICON.play}${x.done ? "Continue" : "Start"}</button>
    </div>`;
  }
  return `<button class="item" data-before="${x.routine.id}|${x.slot}">
    <span class="dot ${done ? "done" : x.done ? "part" : ""}">${done ? ICONS.check : ""}</span>
    <span class="grow"><b>${esc(x.routine.name)}</b><small>${done ? "Done" : `${x.done ? `${x.done} of ${x.total} done · ` : `${x.total} steps · `}about ${minutes(secs)} min`}${x.steps.some((st) => runOf(st).type === "write") ? ` · ${x.steps.filter((st) => runOf(st).type === "write").length} to write` : ""}</small></span>
    ${done ? "" : `<span class="go">Start</span>`}
  </button>`;
}

function viewToday() {
  document.body.dataset.mood = "";
  const day = R.today();
  const slot = R.slotNow();
  const all = R.sessions(day);
  const open = all.filter((x) => x.done < x.total);
  const hero = open.find((x) => x.slot === slot) || (slot === "morning" ? open[0] : null);
  const section = (sl, title) => {
    const xs = all.filter((x) => x.slot === sl && x !== hero);
    if (!xs.length) return "";
    return `<div class="col gap"><span class="kicker plain">${title}</span>${xs.map((x) => sessionCard(x, false)).join("")}</div>`;
  };
  const resume = run && session() ? `<button class="card resume" data-resume><b>Session in progress</b><small>${esc(session().routine.name)} · tap to go back</small></button>` : "";
  return `<main>
    ${header(APP_NAME)}
    <div class="col tight"><span class="kicker plain">${esc(dayTitle(day, { weekday: "long", day: "numeric", month: "long" }))}</span><h1 class="title">${hero ? "Up next" : all.length ? "All done for now" : "Nothing to run today"}</h1></div>
    ${resume}
    ${hero ? sessionCard(hero, true) : ""}
    ${section("morning", "Morning")}
    ${section("night", `Tonight · from ${hourLabel(R.settings().nightFrom)}`)}
    ${all.length ? "" : `<p class="sub">Routines with timed steps show up here. Hair care and other check-off routines stay in Orario.</p>`}
    <div class="grow"></div>
    <button class="ghost wide" data-view="journal">${ICON.book}Journal</button>
  </main>`;
}

function hourLabel(h) {
  const d = new Date();
  d.setHours(h, 0, 0, 0);
  return d.toLocaleTimeString([], { hour: "numeric" });
}

function viewBefore() {
  const [id, slot] = ui.pick.split("|");
  const routine = R.routine(id);
  if (!routine) return viewToday();
  const day = R.today();
  const steps = R.stepsOn(routine, day, slot);
  const n = R.dayNumber(routine, day);
  const total = steps.reduce((t, st) => t + estimate(st), 0);
  return `<main>
    <header><button class="icon" data-home aria-label="Back">${ICONS.left}</button><div class="col"><small class="sub">${esc(routine.name)}${n ? ` · Day ${n.n} of ${n.of}` : ""} · ${slotLabel(slot)}</small><h2>Before you start</h2></div></header>
    <div class="list">${steps
      .map((st, i) => {
        const done = R.isDone(id, day, slot, st.id);
        const { name } = split(st.title);
        return `<div class="planrow ${done ? "was" : ""}"><span class="num">${done ? ICONS.check : i + 1}</span><span class="grow"><b>${esc(name)}</b><small>${esc(howLabel(st))}</small></span><span class="amt">${runOf(st).type === "tap" ? "" : (runOf(st).type === "log" ? "log" : "~" + minutes(estimate(st)) + " min")}</span></div>`;
      })
      .join("")}</div>
    <div class="card opts">
      <label class="opt"><span>Chime and buzz at each change</span><input type="checkbox" class="switch" data-pref="sound" ${pref("sound", "1") ? "checked" : ""}></label>
      <label class="opt"><span>Wait for a tap before each step</span><input type="checkbox" class="switch" data-pref="hold" ${pref("hold", "0") ? "checked" : ""}></label>
    </div>
    <div class="grow"></div>
    <p class="sub center-text">The screen stays on until you finish.</p>
    <button class="primary xl" data-start="${id}|${slot}">${ICON.play}Start · about ${minutes(total)} min</button>
  </main>`;
}

function viewJournal() {
  document.body.dataset.mood = "";
  const q = ui.query.trim().toLowerCase();
  const list = R.entries().filter((e) => e.tag !== "feel" && e.tag !== "template" && (ui.tag === "all" || e.tag === ui.tag) && (!q || JSON.stringify([e.text, e.lines, e.notes, e.title]).toLowerCase().includes(q)));
  let lastKey = "";
  const items = list
    .map((e) => {
      const key = e.day + e.slot;
      const head = key !== lastKey ? `<span class="kicker plain">${esc(dayTitle(e.day, { weekday: "long", day: "numeric", month: "long" }))}${e.slot === "morning" ? " · morning" : e.slot === "night" ? " · night" : ""}</span>` : "";
      lastKey = key;
      let body = "";
      if (e.tag === "run") body = `${e.km ? `${e.km} km` : ""}${e.km && e.seconds ? " in " : ""}${e.seconds ? clock(e.seconds) : ""}${e.km && e.seconds ? ` · ${pace(e.seconds, e.km)}` : ""}${e.notes ? `<br>${esc(e.notes)}` : ""}`;
      else if (e.lines && e.prompts) body = e.prompts.map((p, i) => (e.lines[i] ? `<b>${esc(p)}</b><br>${esc(e.lines[i])}` : "")).filter(Boolean).join("<br>");
      else if (e.lines) body = e.lines.filter(Boolean).map((l, i) => `${i + 1}. ${esc(l)}`).join("<br>");
      else body = esc(e.text || "");
      if (!body) return head;
      const long = ui.open !== e.id && (e.text || "").length > 220;
      return `${head}<button class="card entry" data-open="${esc(e.id)}"><span class="tag">${esc(e.title || TAG_LABEL[e.tag] || e.tag)}</span><span class="${long ? "clamp4" : ""}">${body}</span>${long ? `<small>Read more</small>` : ""}</button>`;
    })
    .join("");
  return `<main>
    ${header("Journal", true)}
    <label class="search">${ICON.search}<input data-query placeholder="Search what you wrote" value="${esc(ui.query)}" aria-label="Search"></label>
    <div class="chips scroll">${TAGS.map(([k, label]) => `<button class="chip ${ui.tag === k ? "on" : ""}" data-tag="${k}">${label}</button>`).join("")}</div>
    <div class="col gap" data-keep-scroll="journal">${items || `<p class="sub">Nothing here yet. Gratitude, wins, scripts and runs you log show up here.</p>`}</div>
  </main>`;
}

function viewSettings() {
  const st = store.snapshot();
  const last = st.lastSync ? new Date(st.lastSync) : null;
  return `<main>
    ${header("Settings", true)}
    <div class="card opts">
      <label class="opt"><span>Chime and buzz at each change</span><input type="checkbox" class="switch" data-pref="sound" ${pref("sound", "1") ? "checked" : ""}></label>
      <label class="opt"><span>Wait for a tap before each step</span><input type="checkbox" class="switch" data-pref="hold" ${pref("hold", "0") ? "checked" : ""}></label>
    </div>
    <div class="card opts">
      <div class="opt"><span>This device</span><input class="inline" data-device value="${esc(st.device)}" aria-label="Device name"></div>
      <div class="opt"><span>Last synced</span><span class="sub">${last ? last.toLocaleString([], { hour: "numeric", minute: "2-digit", month: "short", day: "numeric" }) : "never"}</span></div>
      <div class="opt"><span>Waiting to upload</span><span class="sub">${store.pendingCount()}</span></div>
      ${st.problem ? `<div class="warn">${esc(st.problem)}</div>` : ""}
      <div class="row gap wrap"><button class="ghost" data-sync>Sync now</button><button class="ghost" data-export>Download journal</button><button class="ghost danger" data-signout>Disconnect</button></div>
    </div>
    <p class="sub">Routines and steps come from Orario. Change them on the Mac; Kairos picks them up on its own.</p>
  </main>`;
}

function viewSetup() {
  return `<main class="setup">
    <div class="card">
      <div class="row gap"><span class="logo"></span><h1 class="title">${APP_NAME}</h1></div>
      <p class="sub">Runs your routines one step at a time. Paste your Pocket setup link.</p>
      <form data-form="server" class="col gap">
        <input name="link" placeholder="https://gaone1906.github.io/Pocket/kairos/#connect=…" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
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

function render() {
  const app = $("#app");
  if (!store.signedIn()) {
    app.innerHTML = viewSetup();
    return;
  }
  if (run && ui.view !== "done" && ui.view !== "run" && !session()) {
    run = null;
    saveRun();
  }
  const scrollY = window.scrollY;
  const views = { today: viewToday, before: viewBefore, run: viewRun, done: viewDone, journal: viewJournal, settings: viewSettings };
  if (!views[ui.view]) ui.view = "today";
  if (ui.view !== "run") document.body.dataset.mood = "";
  app.innerHTML = (views[ui.view] || viewToday)() + (ui.toast ? `<div class="toast">${esc(ui.toast)}</div>` : "");
  if (ui.view === "journal") window.scrollTo(0, scrollY);
}

function tickClock() {
  if (!run || ui.view !== "run" || ui.steps) return;
  const s = session();
  if (!s || !s.beat) return;
  const b = s.beat;
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
    if (left <= 0) return advance();
  }
  const soft = softLeft(b);
  const softEl = document.querySelector("[data-soft]");
  if (softEl && soft != null) softEl.textContent = clock(soft);
  const leftEl = document.querySelector("[data-left]");
  if (leftEl) leftEl.textContent = minutes(sessionLeft(s));
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

function go(view) {
  ui.view = view;
  ui.steps = false;
  render();
  window.scrollTo(0, 0);
}

function saveLog() {
  const s = session();
  if (!s || s.beat.kind !== "log") return;
  const time = parseDuration(document.querySelector('[data-log="time"]')?.value);
  const kmText = document.querySelector('[data-log="km"]')?.value.replace(",", ".");
  const km = kmText ? Math.round(Number(kmText) * 100) / 100 : null;
  const notes = document.querySelector('[data-log="notes"]')?.value.trim() || "";
  const patch = { seconds: time || null, km: Number.isFinite(km) && km > 0 ? km : null, notes };
  if (!patch.seconds && !patch.km && !notes) return;
  R.saveEntry(entryBase(s), patch);
  const p = document.querySelector("[data-pace]");
  if (p) p.textContent = patch.seconds && patch.km ? "Pace " + pace(patch.seconds, patch.km) : "";
}

function saveWrite() {
  const s = session();
  if (!s || s.beat.kind !== "write") return;
  const base = entryBase(s);
  const lineEls = [...document.querySelectorAll("[data-line]")];
  if (lineEls.length) {
    const lines = lineEls.map((el) => el.value.trim());
    if (lines.some(Boolean) || R.entry(base.id)) R.saveEntry(base, { lines });
  } else {
    const text = document.querySelector("[data-para]")?.value.trim() || "";
    if (text || R.entry(base.id)) R.saveEntry(base, { text });
  }
}

let writeTimer = null;

document.addEventListener("input", (e) => {
  if (e.target.matches("[data-line], [data-para]")) {
    clearTimeout(writeTimer);
    writeTimer = setTimeout(saveWrite, 700);
  } else if (e.target.matches("[data-log]")) {
    clearTimeout(writeTimer);
    writeTimer = setTimeout(saveLog, 700);
  } else if (e.target.matches("[data-query]")) {
    ui.query = e.target.value;
    const pos = e.target.selectionStart;
    render();
    const el = $("[data-query]");
    if (el) {
      el.focus();
      el.setSelectionRange(pos, pos);
    }
  }
});

document.addEventListener("change", (e) => {
  if (e.target.matches("[data-pref]")) setPref(e.target.dataset.pref, e.target.checked);
  if (e.target.matches("[data-device]")) store.setDevice(e.target.value);
});

document.addEventListener("click", async (e) => {
  if (e.target.matches("[data-close-sheet]")) {
    ui.steps = false;
    render();
    return;
  }
  const t = e.target.closest("button");
  if (!t || t.disabled) return;
  const d = t.dataset;
  if (d.view) return go(d.view);
  if (d.home !== undefined) {
    if (ui.view === "done") {
      run = null;
      saveRun();
    }
    return go("today");
  }
  if (d.before) {
    ui.pick = d.before;
    if (run && session() && `${run.routineId}|${run.slot}` === d.before && run.day === R.today()) return go("run");
    return go("before");
  }
  if (d.start) {
    const [id, slot] = d.start.split("|");
    return startSession(id, R.today(), slot);
  }
  if (d.resume !== undefined) return go("run");
  if (d.end !== undefined) {
    if (confirm("End this session? Steps you finished stay ticked in Orario.")) endRun();
    return;
  }
  if (d.steps !== undefined) {
    ui.steps = true;
    return render();
  }
  if (d.jump) {
    const s = session();
    const i = s.beats.findIndex((b) => b.step === Number(d.jump));
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
    const next = s.beats[run.i + 1];
    if (!next) {
      run.finished = Date.now();
      saveRun();
      ui.view = "done";
      keepAwake(false);
      return render();
    }
    run.i += 1;
    enterBeat(next, next.step !== s.beat.step);
    return render();
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
  if (d.feel) {
    const s = session();
    if (s) R.saveEntry({ id: R.entryId(s.routine.id, run.day, run.slot, "feel"), routine: s.routine.id, routineName: s.routine.name, day: run.day, slot: run.slot, step: "feel", title: s.routine.name, tag: "feel" }, { feel: d.feel });
    return render();
  }
  if (d.tag) {
    ui.tag = d.tag;
    return render();
  }
  if (d.open) {
    ui.open = ui.open === d.open ? null : d.open;
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
    a.download = `runner-journal-${new Date().toISOString().slice(0, 10)}.json`;
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
  if (ui.view === "run" && active && active.matches && active.matches("textarea, input")) return;
  if (ui.view === "journal" && active && active.matches && active.matches("[data-query]")) return;
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
setInterval(() => {
  if (ui.view === "today") render();
}, 60000);
if (store.signedIn()) store.syncNow();
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
