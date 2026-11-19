import * as store from "./store.js";
import { dayKey, weekday, isoNow } from "./util.js";
import { isGuided } from "./plan.js";

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

export function routines() {
  return store.all("schedule.routine").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
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

export function dayNumber(r, day) {
  if (!r.ends) return null;
  const span = (a, b) => Math.round((new Date(b + "T12:00:00") - new Date(a + "T12:00:00")) / 86400000);
  return { n: span(r.starts, day) + 1, of: span(r.starts, r.ends) + 1 };
}

export function sessions(day) {
  const out = [];
  for (const slot of ["morning", "night"]) {
    for (const r of routines()) {
      if (!runsOn(r, day)) continue;
      const steps = stepsOn(r, day, slot);
      if (!steps.length || !steps.some(isGuided)) continue;
      const done = steps.filter((s) => isDone(r.id, day, slot, s.id)).length;
      out.push({ routine: r, slot, day, steps, done, total: steps.length });
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

export function entries() {
  return store.all("runner.entry").sort((a, b) => (a.day === b.day ? (a.slot === b.slot ? String(b.updated).localeCompare(String(a.updated)) : a.slot === "night" ? -1 : 1) : b.day.localeCompare(a.day)));
}
