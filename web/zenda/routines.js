import * as store from "./store.js";
import { dayKey, weekday, isoWeekday, isoNow, shiftDay, spanDays } from "./util.js";
import { isGuided, isMindful } from "../ventus/plan.js";

export function settings() {
  const s = store.get("schedule.settings", "book") || {};
  return { nightFrom: s.nightFrom ?? 16, dayFrom: s.dayFrom ?? 4 };
}

export function today() {
  return dayKey(new Date(Date.now() - settings().dayFrom * 3600000));
}

export function slotNow() {
  const { nightFrom, dayFrom } = settings();
  const h = new Date().getHours();
  return h >= nightFrom || h < dayFrom ? "night" : "morning";
}

export function allRoutines() {
  return store.all("schedule.routine").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
}

export function routines() {
  return allRoutines().filter(isMindful);
}

export function routine(id) {
  return store.get("schedule.routine", id);
}

export function runsOn(r, day) {
  return r.starts <= day && (!r.ends || day <= r.ends);
}

export function stepsOn(r, day, slot) {
  const dated = r.dated && r.dated[`${day}-${slot}`];
  return dated || (r.plan && r.plan[`${weekday(day)}-${slot}`]) || [];
}

export function checkId(routineId, day, slot, stepId) {
  return `${routineId}|${day}|${slot}|${stepId}`;
}

export function isDone(routineId, day, slot, stepId) {
  return !!store.get("schedule.check", checkId(routineId, day, slot, stepId));
}

export function tick(routineId, day, slot, stepId) {
  const id = checkId(routineId, day, slot, stepId);
  if (store.get("schedule.check", id)) return false;
  store.put("schedule.check", id, { id, routine: routineId, day, slot, step: stepId, done: isoNow() });
  return true;
}

export function sessionOf(r, day, slot) {
  const steps = stepsOn(r, day, slot);
  if (!steps.length || !steps.some(isGuided)) return null;
  const done = steps.filter((s) => isDone(r.id, day, slot, s.id)).length;
  return { routine: r, slot, day, steps, done, total: steps.length };
}

export function sessions(day) {
  const out = [];
  for (const slot of ["morning", "night"]) {
    for (const r of routines()) {
      if (!runsOn(r, day)) continue;
      const x = sessionOf(r, day, slot);
      if (x) out.push(x);
    }
  }
  return out;
}

export function entryId(routineId, day, slot, stepId) {
  return `${routineId}|${day}|${slot}|${stepId}`;
}

export function entry(id) {
  return store.get("runner.entry", id);
}

export function saveEntry(base, patch) {
  const prev = store.get("runner.entry", base.id) || {};
  store.put("runner.entry", base.id, { ...prev, ...base, ...patch, updated: isoNow() });
}

export const BOOKS = [
  ["gratitude", "Gratitude"],
  ["win", "Wins"],
  ["script", "Scripts"],
  ["action", "Actions"],
  ["review", "Reviews"],
  ["note", "Notes"],
];

export const BOOK_TAGS = new Set(BOOKS.map((b) => b[0]));

export function entries(tag) {
  return store
    .all("runner.entry")
    .filter((e) => BOOK_TAGS.has(e.tag) && (!tag || e.tag === tag))
    .filter((e) => (e.text && e.text.trim()) || (e.lines && e.lines.some((l) => String(l).trim())));
}

export function projects() {
  return store.all("zenda.project").sort((a, b) => String(a.start).localeCompare(String(b.start)) || String(a.name).localeCompare(String(b.name)));
}

export function applies(p, day) {
  return p.start <= day && day <= p.end && (p.days || []).includes(isoWeekday(day));
}

export function dayOf(p, day) {
  return { n: spanDays(p.start, day) + 1, of: spanDays(p.start, p.end) + 1 };
}

export function shortName(p) {
  const words = String(p.name || "").trim().split(/\s+/);
  return words[words.length - 1] || "";
}

export function projectSessions(p, from, to) {
  const r = routine(p.routine);
  const out = [];
  if (!r) return out;
  for (let d = from; d <= to; d = shiftDay(d, 1)) {
    if (!applies(p, d) || !runsOn(r, d)) continue;
    for (const slot of ["morning", "night"]) {
      const x = sessionOf(r, d, slot);
      if (x) out.push(x);
    }
  }
  return out;
}

export function scopeSessions(ps, from, to) {
  const seen = new Map();
  for (const p of ps) {
    for (const x of projectSessions(p, from, to)) {
      const key = `${x.routine.id}|${x.day}|${x.slot}`;
      if (!seen.has(key)) seen.set(key, x);
    }
  }
  return [...seen.values()];
}
