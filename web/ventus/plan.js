const TIMED_TYPES = new Set(["timed", "box", "moves", "intervals", "rounds", "log", "say", "write"]);
const BREATH = ["Breathe in", "Hold", "Breathe out", "Hold"];
const REP_SECONDS = 3;

export function split(title) {
  const text = String(title || "");
  const bar = text.indexOf("|");
  if (bar < 0) return { name: text.trim(), detail: "" };
  return { name: text.slice(0, bar).trim(), detail: text.slice(bar + 1).trim() };
}

export function runOf(step) {
  const run = step && step.run && typeof step.run === "object" ? step.run : null;
  if (run && run.type) return run;
  const m = split(step && step.title).detail.match(/(\d+)\s*min\b/);
  if (m) return { type: "timed", seconds: Number(m[1]) * 60 };
  return { type: "tap" };
}

export function isGuided(step) {
  return TIMED_TYPES.has(runOf(step).type);
}

const num = (v, d = 0) => (Number.isFinite(Number(v)) && Number(v) > 0 ? Math.round(Number(v)) : d);
const list = (v) => (Array.isArray(v) ? v : []);

export function dayNumber(day) {
  const m = String(day || "").match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return 0;
  return Math.floor(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) / 86400000);
}

export function pick(pool, count, day) {
  const lines = list(pool).map(String).filter(Boolean);
  const take = Math.min(num(count), lines.length);
  if (!take) return lines;
  const start = (((dayNumber(day) * take) % lines.length) + lines.length) % lines.length;
  return Array.from({ length: take }, (_, i) => lines[(start + i) % lines.length]);
}

export function pattern(run) {
  const p = list(run.pattern).map((v) => Math.max(0, Math.round(Number(v) || 0)));
  return p.length === 4 && p.some((v) => v > 0) ? p : [4, 4, 4, 4];
}

export function breath(box, elapsed) {
  const cycle = box.reduce((a, b) => a + b, 0) || 16;
  let t = ((elapsed % cycle) + cycle) % cycle;
  for (let i = 0; i < 4; i++) {
    if (!box[i]) continue;
    if (t < box[i]) return { index: i, label: BREATH[i], fraction: t / box[i], left: Math.ceil(box[i] - t) };
    t -= box[i];
  }
  return { index: 0, label: BREATH[0], fraction: 0, left: box[0] };
}

function moveBeat(base, move, extra = {}) {
  const seconds = num(move.seconds);
  return {
    ...base,
    kind: seconds ? "count" : "reps",
    seconds,
    name: String(move.name || base.name),
    reps: num(move.reps),
    detail: String(move.detail || ""),
    ...extra,
  };
}

export function beatsFor(step, index, day = "") {
  const run = runOf(step);
  const { name, detail } = split(step.title);
  const base = { step: index, name, detail: detail, tip: step.tip || "", type: run.type, guide: num(run.seconds), quiet: !!run.quiet };
  const moves = list(run.moves).filter((m) => m && m.name);
  switch (run.type) {
    case "timed":
    case "box":
      return [{ ...base, kind: "count", seconds: num(run.seconds, run.type === "box" ? 240 : 60), cues: list(run.cues).filter((c) => c && c.text).map((c) => ({ at: num(c.at), text: String(c.text) })).sort((a, b) => a.at - b.at), box: run.type === "box" ? pattern(run) : null, reads: pick(run.reads, run.pick, day), every: num(run.every, 20) }];
    case "moves":
      if (!moves.length) return [{ ...base, kind: "reps" }];
      return moves.map((m, i) => moveBeat(base, m, { list: moves, at: i, label: `${name} · move ${i + 1} of ${moves.length}` }));
    case "intervals": {
      const rounds = num(run.rounds, 1);
      const names = list(run.names).map(String);
      const out = [];
      for (let i = 0; i < rounds; i++) {
        const label = names.length ? names[i % names.length] : String(run.onName || name);
        const following = names.length ? names[(i + 1) % names.length] : label;
        out.push({ ...base, kind: "count", seconds: num(run.on, 30), name: label, label: `${run.onLabel || "Go"} · ${run.unit || "interval"} ${i + 1} of ${rounds}`, round: i, rounds, hot: true, then: i < rounds - 1 && num(run.off) ? { rest: num(run.off), name: following, restName: run.offName || "Rest" } : null });
        if (i < rounds - 1 && num(run.off)) out.push({ ...base, kind: "rest", seconds: num(run.off), name: String(run.offName || "Rest"), label: `${run.unit ? run.unit[0].toUpperCase() + run.unit.slice(1) : "Interval"} ${i + 1} of ${rounds} done`, round: i, rounds, nextName: following, intervals: true });
      }
      return out;
    }
    case "rounds": {
      const rounds = num(run.rounds, 1);
      const unit = run.unit || "round";
      const out = [];
      if (!moves.length) return [{ ...base, kind: "reps" }];
      for (let r = 0; r < rounds; r++) {
        moves.forEach((m, i) => out.push(moveBeat(base, m, { list: moves, at: i, round: r, rounds, label: `${name} · ${unit} ${r + 1} of ${rounds}` })));
        if (r < rounds - 1 && num(run.rest)) out.push({ ...base, kind: "rest", seconds: num(run.rest), name: "Rest", label: `${unit[0].toUpperCase() + unit.slice(1)} ${r + 1} of ${name} done`, round: r, rounds, unit, nextName: moves[0].name, nextReps: num(moves[0].reps), nextList: moves.map((m) => m.name) });
      }
      return out;
    }
    case "log":
      return [{ ...base, kind: "log", plan: String(run.plan || detail || name) }];
    case "say":
      return [{ ...base, kind: "say", lines: list(run.lines).map(String).concat(list(run.pool).length ? pick(run.pool, run.pick, day) : []), times: num(run.times, 1) }];
    case "write":
      return [{ ...base, kind: "write", fields: num(run.fields, 0), prompt: String(run.prompt || ""), tag: String(run.tag || "note") }];
    default:
      return [{ ...base, kind: "reps", label: "", detail: run.detail ? String(run.detail) : detail }];
  }
}

export function beatsForSteps(steps, day = "") {
  return steps.flatMap((s, i) => beatsFor(s, i, day));
}

export function estimate(step) {
  const run = runOf(step);
  const beats = beatsFor(step, 0);
  const counted = beats.reduce((sum, b) => sum + (b.seconds || 0) + (b.kind === "reps" ? Math.max(20, (b.reps || 10) * REP_SECONDS) : 0), 0);
  if (run.type === "log") return num(run.seconds, 15 * 60);
  return Math.max(counted, num(run.seconds));
}

export function howLabel(step) {
  const run = runOf(step);
  const moves = list(run.moves);
  switch (run.type) {
    case "timed":
      return list(run.reads).length ? "Timer · lines to read if it's hard to picture" : "Timer";
    case "box":
      return `Box breathing ${pattern(run).join("-")} · follow the ball`;
    case "moves":
      return moves.length ? `${moves.length} moves, each named` : "Tap Done when finished";
    case "intervals":
      return `${num(run.rounds, 1)} × ${num(run.on, 30)}s on${num(run.off) ? `, ${num(run.off)}s ${String(run.offName || "rest").toLowerCase()}` : ""}${list(run.names).length > 1 ? " · moves rotate" : ""}`;
    case "rounds":
      return `${num(run.rounds, 1)} ${run.unit || "round"}s of ${moves.length} move${moves.length === 1 ? "" : "s"}${num(run.rest) ? ` · ${num(run.rest)}s rest` : ""}`;
    case "log":
      return "Do it, then enter time and distance";
    case "say":
      return `Out loud · ${list(run.lines).length + (list(run.pool).length ? Math.min(num(run.pick, list(run.pool).length), list(run.pool).length) : 0)} lines${list(run.pool).length ? " (fresh daily)" : ""}, ${num(run.times, 1)} times each`;
    case "write":
      return num(run.fields) > 1 ? `Write ${num(run.fields)} lines` : "Write it down";
    default:
      return "Tap Done when finished";
  }
}

export function plainDetail(detail) {
  return String(detail || "").replace(/,?\s*\d+\s*min\b.*$/, "").trim();
}

export function clock(seconds) {
  const s = Math.max(0, Math.round(seconds));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function minutes(seconds) {
  return Math.max(1, Math.round(seconds / 60));
}

const FITNESS_TYPES = new Set(["moves", "intervals", "rounds", "log"]);

export function isMindful(routine) {
  const steps = [];
  for (const key in (routine && routine.plan) || {}) steps.push(...list(routine.plan[key]));
  for (const key in (routine && routine.dated) || {}) steps.push(...list(routine.dated[key]));
  const runs = steps.map(runOf);
  if (runs.some((r) => FITNESS_TYPES.has(r.type))) return false;
  return runs.some((r) => r.type === "box" || r.type === "say" || r.type === "write" || (r.type === "timed" && (list(r.reads).length || r.quiet)));
}
