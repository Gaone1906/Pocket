import * as store from "./store.js";
import * as R from "./routines.js";
import { shiftDay, weekStart, parseDay, isoNow } from "./util.js";
import { runOf, split, estimate, minutes, clock } from "./plan.js";

const FIT_TYPES = new Set(["moves", "intervals", "rounds", "log"]);
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const PICK_KEY = "runner.project";

export const isDay = (v) => typeof v === "string" && DAY_RE.test(v) && !Number.isNaN(parseDay(v).getTime());

export function span(a, b) {
  return Math.round((new Date(b + "T12:00:00") - new Date(a + "T12:00:00")) / 86400000);
}

function allSteps(r) {
  const out = [];
  for (const group of [r.plan, r.dated]) {
    if (!group || typeof group !== "object") continue;
    for (const k in group) if (Array.isArray(group[k])) out.push(...group[k]);
  }
  return out;
}

export function isFitness(r) {
  return !!r && allSteps(r).some((s) => s && s.run && typeof s.run === "object" && FIT_TYPES.has(s.run.type));
}

export function fitnessRoutines() {
  return R.routines().filter((r) => r && r.id && isFitness(r));
}

function lastDated(r) {
  const keys = Object.keys(r.dated || {})
    .map((k) => k.slice(0, 10))
    .filter(isDay)
    .sort();
  return keys[keys.length - 1] || null;
}

function firstDated(r) {
  const keys = Object.keys(r.dated || {})
    .map((k) => k.slice(0, 10))
    .filter(isDay)
    .sort();
  return keys[0] || null;
}

const strings = (v) => (Array.isArray(v) ? v.map((x) => String(x ?? "").trim()).filter(Boolean) : []);

export function projectId(routineId) {
  return `project|${routineId}`;
}

export function project(r) {
  const e = store.get("runner.entry", projectId(r.id));
  const valid = e && typeof e === "object" && !Array.isArray(e);
  const start = (valid && isDay(e.day) && e.day) || (isDay(r.starts) && r.starts) || firstDated(r) || R.today();
  let end = (valid && isDay(e.notes) && e.notes) || (isDay(r.ends) && r.ends) || lastDated(r) || shiftDay(start, 27);
  if (end < start) end = start;
  const targets = valid ? strings(e.lines) : [];
  const achieved = new Set(
    valid && e.feel != null
      ? String(e.feel)
          .split(",")
          .map((x) => Number(x.trim()))
          .filter((n) => Number.isInteger(n) && n >= 0 && n < targets.length)
      : []
  );
  const milestones = (valid ? strings(e.prompts) : [])
    .map((p) => {
      const bar = p.indexOf("|");
      const day = bar < 0 ? "" : p.slice(0, bar).trim();
      return { day, label: bar < 0 ? p : p.slice(bar + 1).trim() };
    })
    .filter((m) => isDay(m.day))
    .sort((a, b) => a.day.localeCompare(b.day));
  return {
    id: r.id,
    routine: r,
    name: (valid && String(e.title || "").trim()) || String(r.name || "Project"),
    goal: valid ? String(e.text || "") : "",
    start,
    end,
    targets,
    achieved,
    milestones,
    entry: valid ? e : null,
  };
}

export function projects() {
  return fitnessRoutines().map(project);
}

export function readPick() {
  try {
    return localStorage.getItem(PICK_KEY) || "";
  } catch (e) {
    return "";
  }
}

export function writePick(id) {
  try {
    localStorage.setItem(PICK_KEY, id);
  } catch (e) {}
}

export function current(list = projects()) {
  if (!list.length) return null;
  const pick = readPick();
  const chosen = list.find((p) => p.id === pick);
  if (chosen) return chosen;
  const day = R.today();
  return list.find((p) => p.start <= day && day <= p.end) || list[0];
}

export function saveProject(p, patch) {
  const prev = p.entry || {};
  const data = {
    ...prev,
    id: projectId(p.id),
    routine: p.id,
    routineName: String(p.routine.name || ""),
    tag: "project",
    step: "project",
    slot: "",
    title: p.name,
    text: p.goal,
    day: p.start,
    notes: p.end,
    lines: p.targets,
    prompts: p.milestones.map((m) => `${m.day}|${m.label}`),
    ...patch,
    updated: isoNow(),
  };
  if (data.feel === "" || data.feel == null) delete data.feel;
  store.put("runner.entry", data.id, data);
}

export function toggleTarget(p, index) {
  const set = new Set(p.achieved);
  if (set.has(index)) set.delete(index);
  else set.add(index);
  const feel = [...set].sort((a, b) => a - b).join(",");
  saveProject(p, { feel: feel || null });
}

export function sessionsOn(r, day) {
  if (!R.runsOn(r, day)) return [];
  const out = [];
  for (const slot of ["morning", "night"]) {
    const steps = R.stepsOn(r, day, slot).filter((s) => s && typeof s === "object");
    if (steps.length) out.push({ routine: r, day, slot, steps, done: steps.filter((s) => R.isDone(r.id, day, slot, s.id)).length });
  }
  return out;
}

export function dayInfo(p, day) {
  const sessions = sessionsOn(p.routine, day);
  const steps = sessions.flatMap((s) => s.steps);
  const total = steps.length;
  const done = sessions.reduce((n, s) => n + s.done, 0);
  const seconds = steps.reduce((n, s) => n + estimate(s), 0);
  const doneSeconds = sessions.reduce((n, s) => n + s.steps.filter((st) => R.isDone(p.id, day, s.slot, st.id)).reduce((m, st) => m + estimate(st), 0), 0);
  const rest = total > 0 && steps.every(isRestStep);
  const today = R.today();
  let status = "none";
  if (total) status = done >= total ? "done" : done ? "part" : day < today ? "missed" : day === today ? "today" : "future";
  return { day, sessions, steps, total, done, seconds, doneSeconds, rest, status };
}

export function isRestStep(step) {
  return /stretch|mobility|cool.?down|recovery|rest/i.test(split(step && step.title).name);
}

export function dayNumber(p, day) {
  return { n: span(p.start, day) + 1, of: span(p.start, p.end) + 1 };
}

export function daysOf(p, from = p.start, to = p.end) {
  const out = [];
  let d = from < p.start ? p.start : from;
  const last = to > p.end ? p.end : to;
  let guard = 0;
  while (d <= last && guard++ < 800) {
    out.push(d);
    d = shiftDay(d, 1);
  }
  return out;
}

export function weeks(p) {
  const out = [];
  let w = weekStart(p.start);
  const last = weekStart(p.end);
  let guard = 0;
  while (w <= last && guard++ < 120) {
    out.push(w);
    w = shiftDay(w, 7);
  }
  return out;
}

export function streak(p) {
  const today = R.today();
  let n = 0;
  let d = today > p.end ? p.end : today;
  let guard = 0;
  while (d >= p.start && guard++ < 800) {
    const info = dayInfo(p, d);
    if (info.status === "done") n += 1;
    else if (!(d === today || info.total === 0 || info.rest)) break;
    d = shiftDay(d, -1);
  }
  return n;
}

export function nextMilestone(p) {
  const today = R.today();
  return p.milestones.find((m) => m.day >= today) || null;
}

export function nextSession(p, after) {
  let d = shiftDay(after, 1);
  let guard = 0;
  while (d <= p.end && guard++ < 60) {
    const info = dayInfo(p, d);
    if (info.total) return info;
    d = shiftDay(d, 1);
  }
  return null;
}

export function shortName(name) {
  return /rope|skip/i.test(name) ? "Rope" : name;
}

const SIDE = /warm|stretch|cool|calves|shins|mobility/i;

export function sessionTitle(steps) {
  const names = [];
  for (const s of steps) {
    const n = split(s.title).name;
    if (n && !names.includes(n)) names.push(n);
  }
  const main = names.filter((n) => !SIDE.test(n));
  const pick = main.length ? main.slice(0, 2) : names.slice(0, 2);
  return pick.map(shortName).join(" + ") || "Session";
}

const num = (v) => (Number.isFinite(Number(v)) && Number(v) > 0 ? Math.round(Number(v)) : 0);

function secs(n) {
  if (!n) return "";
  return n % 60 === 0 ? `${n / 60}` : clock(n);
}

export function compact(step) {
  const run = runOf(step);
  const moves = Array.isArray(run.moves) ? run.moves.filter((m) => m && m.name) : [];
  switch (run.type) {
    case "intervals": {
      const on = num(run.on) || 30;
      const off = num(run.off);
      const unitMin = on % 60 === 0 && (!off || off % 60 === 0);
      return `${num(run.rounds) || 1} × ${unitMin ? secs(on) : on}${off ? `/${unitMin ? secs(off) : off}` : ""}`;
    }
    case "rounds": {
      const rounds = num(run.rounds) || 1;
      const reps = moves.map((m) => num(m.reps));
      if (moves.length && reps.every((r) => r && r === reps[0])) return `${rounds} × ${reps[0]}`;
      return `${rounds} × ${moves.length || 1}`;
    }
    case "log":
      return String(run.plan || split(step.title).detail || "").slice(0, 24);
    default:
      return `${minutes(estimate(step))}m`;
  }
}

export function amount(step) {
  const run = runOf(step);
  const moves = Array.isArray(run.moves) ? run.moves.filter((m) => m && m.name) : [];
  if (run.type === "rounds" && moves.length === 1 && num(moves[0].reps)) return String((num(run.rounds) || 1) * num(moves[0].reps));
  if (run.type === "rounds") return compact(step);
  return `${minutes(estimate(step))}m`;
}

export function segments(step) {
  const run = runOf(step);
  if (run.type !== "intervals") return null;
  const rounds = Math.min(num(run.rounds) || 1, 40);
  const on = num(run.on) || 30;
  const off = num(run.off);
  const names = Array.isArray(run.names) ? run.names.map(String) : [];
  const onName = String(run.onName || (names.length === 1 ? names[0] : names.length ? "Work" : "Work"));
  const offName = String(run.offName || "Rest");
  const bars = [];
  for (let i = 0; i < rounds; i++) {
    bars.push("on");
    if (off) bars.push("off");
  }
  return { bars, on, off, onName, offName };
}

export function sets(step) {
  const run = runOf(step);
  const moves = Array.isArray(run.moves) ? run.moves.filter((m) => m && m.name) : [];
  if (run.type !== "rounds" || !moves.length) return null;
  const rounds = Math.min(num(run.rounds) || 1, 30);
  if (moves.length === 1) return Array.from({ length: rounds }, () => (num(moves[0].reps) ? String(num(moves[0].reps)) : clock(num(moves[0].seconds))));
  return null;
}

export function entries() {
  return store.all("runner.entry").filter((e) => e && typeof e === "object" && e.id);
}

export function workouts(routineIds) {
  return entries().filter((e) => e.tag === "workout" && isDay(e.day) && (!routineIds || routineIds.has(e.routine)));
}

export function runs(routineIds) {
  return entries()
    .filter((e) => isDay(e.day) && (!routineIds || routineIds.has(e.routine)) && (e.tag === "run" || (e.tag === "workout" && e.step === "run")))
    .filter((e) => Number(e.km) > 0 || Number(e.seconds) > 0)
    .sort((a, b) => (a.day === b.day ? String(b.updated || "").localeCompare(String(a.updated || "")) : b.day.localeCompare(a.day)));
}

const FEEL_NUM = { easy: 2, right: 3, hard: 4, "too-hard": 4 };

export function feels(routineIds) {
  return entries()
    .filter((e) => isDay(e.day) && (!routineIds || routineIds.has(e.routine)))
    .map((e) => {
      let v = null;
      if (e.tag === "feel") v = FEEL_NUM[e.feel] || null;
      else if (e.tag === "workout") v = Number(e.feel);
      return Number.isInteger(v) && v >= 1 && v <= 5 ? { day: e.day, updated: String(e.updated || ""), v } : null;
    })
    .filter(Boolean)
    .sort((a, b) => (a.day === b.day ? a.updated.localeCompare(b.updated) : a.day.localeCompare(b.day)))
    .slice(-7);
}

export function bestFor(target, routineIds) {
  const want = Number((String(target).match(/(\d+(?:[.,]\d+)?)/) || [])[1]?.replace(",", "."));
  if (!Number.isFinite(want) || want <= 0) return null;
  if (/\bkm\b/i.test(target)) {
    const best = runs(routineIds).reduce((m, e) => Math.max(m, Number(e.km) || 0), 0);
    return { have: Math.round(best * 100) / 100, want, unit: "km" };
  }
  if (/rope|skip/i.test(target)) {
    const best = workouts(routineIds)
      .filter((e) => e.step === "rope")
      .reduce((m, e) => Math.max(m, Number(e.text) || 0), 0);
    return { have: best, want, unit: "" };
  }
  return null;
}
