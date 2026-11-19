const TIMED_TYPES = new Set(["timed", "moves", "intervals", "rounds", "log", "say", "write"]);
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

export function beatsFor(step, index) {
  const run = runOf(step);
  const { name, detail } = split(step.title);
  const base = { step: index, name, detail: detail, tip: step.tip || "", type: run.type, guide: num(run.seconds), quiet: !!run.quiet };
  const moves = list(run.moves).filter((m) => m && m.name);
  switch (run.type) {
    case "timed":
      return [{ ...base, kind: "count", seconds: num(run.seconds, 60), cues: list(run.cues).filter((c) => c && c.text).map((c) => ({ at: num(c.at), text: String(c.text) })).sort((a, b) => a.at - b.at) }];
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
      return [{ ...base, kind: "say", lines: list(run.lines).map(String), times: num(run.times, 1) }];
    case "write":
      return [{ ...base, kind: "write", fields: num(run.fields, 0), prompt: String(run.prompt || ""), tag: String(run.tag || "note") }];
    default:
      return [{ ...base, kind: "reps", label: "", detail: run.detail ? String(run.detail) : detail }];
  }
}

export function beatsForSteps(steps) {
  return steps.flatMap((s, i) => beatsFor(s, i));
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
      return "Timer";
    case "moves":
      return moves.length ? `${moves.length} moves, each named` : "Tap Done when finished";
    case "intervals":
      return `${num(run.rounds, 1)} × ${num(run.on, 30)}s on${num(run.off) ? `, ${num(run.off)}s ${String(run.offName || "rest").toLowerCase()}` : ""}${list(run.names).length > 1 ? " · moves rotate" : ""}`;
    case "rounds":
      return `${num(run.rounds, 1)} ${run.unit || "round"}s of ${moves.length} move${moves.length === 1 ? "" : "s"}${num(run.rest) ? ` · ${num(run.rest)}s rest` : ""}`;
    case "log":
      return "Do it, then enter time and distance";
    case "say":
      return `Out loud · ${list(run.lines).length} lines, ${num(run.times, 1)} times each`;
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
