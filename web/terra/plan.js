import { dayKey, parseDay, shiftDay, weekStart, monthStart } from "./util.js";

export const KCAL_PER_KG = 7700;
export const ROLLOVER = 4;
export const SLOTS = ["breakfast", "lunch", "snack", "dinner"];

export function today(now = new Date()) {
  return dayKey(new Date(now.getTime() - ROLLOVER * 3600 * 1000));
}

export function between(a, b) {
  return Math.round((parseDay(b) - parseDay(a)) / 86400000);
}

export function slotNow(now = new Date()) {
  const h = now.getHours();
  if (h >= 4 && h < 11) return "breakfast";
  if (h >= 11 && h < 16) return "lunch";
  if (h >= 16 && h < 19) return "snack";
  return "dinner";
}

export function weekDays(k) {
  const start = weekStart(k);
  return Array.from({ length: 7 }, (_, i) => shiftDay(start, i));
}

export function monthDays(k) {
  const d = parseDay(monthStart(k));
  const n = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  return Array.from({ length: n }, (_, i) => shiftDay(monthStart(k), i));
}

export function withDefaults(plan) {
  if (!plan) return null;
  return { pace: "fastest", floor: 1500, watchShare: 0.75, eatBack: false, menuLeft: true, weighAt: "07:00", activity: 1.2, sex: "male", ...plan };
}

export function age(born, day) {
  return Math.floor(between(born, day) / 365.2425);
}

export function bmr(plan, kg, day) {
  return 10 * kg + 6.25 * plan.heightCm - 5 * age(plan.born, day) + (plan.sex === "female" ? -161 : 5);
}

export function base(plan, kg, day) {
  return bmr(plan, kg, day) * plan.activity;
}

export function totalDays(plan) {
  return Math.max(1, between(plan.startDay, plan.goalDay));
}

export function dailyGoal(plan) {
  return Math.max(0, Math.round(((plan.startKg - plan.goalKg) * KCAL_PER_KG) / totalDays(plan)));
}

export function budget(plan, baseBurn) {
  if (plan.pace === "ontime") return Math.max(plan.floor, Math.round(baseBurn - dailyGoal(plan)));
  return plan.floor;
}

export function model(plan, entries, weights, now = today()) {
  plan = withDefaults(plan);
  const byDay = {};
  for (const e of entries) (byDay[e.day] = byDay[e.day] || []).push(e);
  for (const k in byDay) byDay[k].sort((a, b) => String(a.at || "").localeCompare(String(b.at || "")));
  const sortedWeights = [...weights].sort((a, b) => a.day.localeCompare(b.day));
  const weightOn = (k) => (sortedWeights.find((w) => w.day === k) || {}).kg ?? null;
  const asOf = (k) => {
    let found = null;
    for (const w of sortedWeights) if (w.day <= k) found = w.kg;
    return found ?? (plan ? plan.startKg : null);
  };
  const average = (k) => {
    const from = shiftDay(k, -6);
    const list = sortedWeights.filter((w) => w.day >= from && w.day <= k);
    if (!list.length) return asOf(k);
    return Math.round((list.reduce((s, w) => s + w.kg, 0) / list.length) * 10) / 10;
  };
  const summary = (k) => {
    if (!plan) return null;
    const list = byDay[k] || [];
    const eaten = list.filter((e) => e.kind !== "workout").reduce((s, e) => s + e.kcal, 0);
    const raw = list.filter((e) => e.kind === "workout").reduce((s, e) => s + e.kcal, 0);
    const workout = Math.round(raw * plan.watchShare);
    const b = Math.round(base(plan, asOf(k) ?? plan.startKg, k));
    const allowance = budget(plan, b) + (plan.eatBack ? workout : 0);
    const logged = list.some((e) => e.kind !== "workout");
    return { day: k, eaten, workoutRaw: raw, workout, base: b, budget: allowance, logged, left: allowance - eaten, deficit: logged ? b + workout - eaten : 0, over: logged && eaten > allowance };
  };
  const span = (days) => {
    if (!plan) return null;
    const goal = dailyGoal(plan);
    const list = days.map(summary);
    const elapsed = days.filter((k) => k <= now && k >= plan.startDay).length;
    const active = days.filter((k) => k >= plan.startDay && k <= plan.goalDay).length;
    const logged = list.filter((d) => d.logged);
    const deficit = list.reduce((s, d) => s + d.deficit, 0);
    return {
      days: list,
      goal: goal * active,
      due: goal * elapsed,
      deficit,
      avgEaten: logged.length ? logged.reduce((s, d) => s + d.eaten, 0) / logged.length : 0,
      workouts: list.reduce((s, d) => s + d.workout, 0),
      underLimit: deficit >= goal * elapsed,
    };
  };
  const week = (k) => span(weekDays(k));
  const month = (k) => span(monthDays(k));
  const perDayLeft = (w) => {
    const rest = w.days.filter((d) => d.day > now).length;
    return rest ? Math.max(0, Math.round((w.goal - w.deficit) / rest)) : 0;
  };
  const monthLoss = (k) => {
    if (!plan) return null;
    const m = month(k);
    const start = monthStart(k);
    const opening = start <= plan.startDay ? plan.startKg : average(shiftDay(start, -1)) ?? plan.startKg;
    const days = monthDays(k);
    const end = days[days.length - 1] < now ? days[days.length - 1] : now;
    const current = average(end) ?? opening;
    return { lost: Math.round((opening - current) * 10) / 10, target: Math.round((m.goal / KCAL_PER_KG) * 10) / 10, due: m.due / KCAL_PER_KG, span: m };
  };
  const goal = () => {
    if (!plan) return null;
    const current = average(now) ?? plan.startKg;
    const lost = Math.round((plan.startKg - current) * 10) / 10;
    const total = plan.startKg - plan.goalKg;
    const elapsed = Math.max(0, Math.min(totalDays(plan), between(plan.startDay, now)));
    const due = (dailyGoal(plan) * elapsed) / KCAL_PER_KG;
    const recent = Array.from({ length: 14 }, (_, i) => summary(shiftDay(now, -i))).filter((d) => d.logged);
    let eta = plan.goalDay;
    if (recent.length >= 3) {
      const rate = recent.reduce((s, d) => s + d.deficit, 0) / recent.length;
      if (rate > 50) eta = shiftDay(now, Math.ceil((Math.max(0, total - lost) * KCAL_PER_KG) / rate));
    }
    return { lost, total, due, eta };
  };
  return { plan, today: now, entries: (k) => byDay[k] || [], weightOn, asOf, average, summary, span, week, month, perDayLeft, monthLoss, goal };
}

export function parseQuick(text) {
  const m = String(text).trim().match(/^(.*?)\s*([-−]?)\s*(\d+(?:\.\d+)?)\s*(?:kcal|cal)?$/i);
  if (!m || !Number(m[3])) return null;
  return { kind: m[2] ? "workout" : "meal", title: m[1].trim(), kcal: Number(m[3]) };
}

export { dayKey };
