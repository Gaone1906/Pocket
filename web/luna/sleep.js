export const DEFAULTS = { bed: "23:00", wake: "06:30", hours: 8, deep: 15, rem: 20, tolerance: 20 };
export const STAGES = ["deep", "core", "rem", "awake"];
const SLEEP_VALUES = new Set(["InBed", "Asleep", "Core", "Deep", "REM", "Awake"]);
const RANK = { InBed: 1, Awake: 2, Asleep: 3, Core: 3, REM: 4, Deep: 5 };
const STAGE_OF_RANK = ["awake", "awake", "awake", "core", "rem", "deep"];
const MIN = 60000;
const GAP = 90 * MIN;
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function normalValue(v) {
  const s = String(v ?? "").toLowerCase();
  if (s.includes("deep")) return "Deep";
  if (s.includes("rem")) return "REM";
  if (s.includes("core")) return "Core";
  if (s.includes("awake")) return "Awake";
  if (s.includes("bed")) return "InBed";
  if (s.includes("hrv") || s.includes("variability")) return "HRV";
  if (s.includes("hr") || s.includes("heart")) return "HR";
  return "Asleep";
}

export function number(q) {
  if (typeof q === "number") return Number.isFinite(q) ? q : null;
  const m = String(q ?? "").match(/-?\d+(?:[.,]\d+)?/);
  return m ? Number(m[0].replace(",", ".")) : null;
}

export function normalise(d) {
  if (!d || !d.s || !d.e) return null;
  const s = Date.parse(d.s);
  const e = Date.parse(d.e);
  if (!Number.isFinite(s) || !Number.isFinite(e) || e < s) return null;
  const v = normalValue(d.v);
  return { s, e, v, q: v === "HR" || v === "HRV" ? number(d.q) : null };
}

export function settings(raw) {
  const r = raw || {};
  const out = { ...DEFAULTS };
  if (/^\d{1,2}:\d{2}$/.test(r.bed || "")) out.bed = r.bed;
  if (/^\d{1,2}:\d{2}$/.test(r.wake || "")) out.wake = r.wake;
  for (const k of ["hours", "deep", "rem", "tolerance"]) if (Number(r[k]) > 0) out[k] = Number(r[k]);
  return out;
}

const pad = (n) => String(n).padStart(2, "0");
export const keyOf = (ms) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
export const parseKey = (k) => {
  const [y, m, d] = k.split("-").map(Number);
  return new Date(y, m - 1, d);
};
export const shiftKey = (k, n) => {
  const d = parseKey(k);
  return keyOf(new Date(d.getFullYear(), d.getMonth(), d.getDate() + n).getTime());
};
export const weekStart = (k) => shiftKey(k, -((parseKey(k).getDay() + 6) % 7));
export const weekKeys = (k) => Array.from({ length: 7 }, (_, i) => shiftKey(weekStart(k), i));
export const monthKeys = (k) => {
  const d = parseKey(k);
  const n = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  return Array.from({ length: n }, (_, i) => keyOf(new Date(d.getFullYear(), d.getMonth(), i + 1).getTime()));
};
export const monthShift = (k, n) => {
  const d = parseKey(k);
  return keyOf(new Date(d.getFullYear(), d.getMonth() + n, 1).getTime());
};
export const today = () => keyOf(Date.now());
export const monthName = (k) => MONTHS[parseKey(k).getMonth()];
export const dayName = (k) => DAYS[parseKey(k).getDay()];

const hm = (t) => {
  const [h, m] = t.split(":").map(Number);
  return h * 60 + m;
};
const clockMinutes = (ms) => {
  const d = new Date(ms);
  return d.getHours() * 60 + d.getMinutes();
};
export const wrap = (m) => ((((m + 720) % 1440) + 1440) % 1440) - 720;

export function duration(minutes) {
  const m = Math.round(minutes);
  return `${Math.floor(m / 60)}h ${pad(m % 60)}m`;
}

export function clock(ms) {
  const d = new Date(ms);
  const h = d.getHours();
  return `${h % 12 || 12}:${pad(d.getMinutes())} ${h < 12 ? "am" : "pm"}`;
}

export function clockOf(t, suffix = true) {
  const m = hm(t);
  const h = Math.floor(m / 60) % 24;
  return `${h % 12 || 12}:${pad(m % 60)}${suffix ? (h < 12 ? " am" : " pm") : ""}`;
}

export const hoursText = (h) => (Number.isInteger(h) ? String(h) : String(Math.round(h * 10) / 10));

export function scoreTone(score) {
  if (score == null) return null;
  return score >= 80 ? "good" : score >= 70 ? "fair" : "poor";
}

function clusters(stages) {
  const out = [];
  let cur = null;
  for (const x of stages) {
    if (cur && x.s <= cur.end + GAP) {
      cur.items.push(x);
      if (x.e > cur.end) cur.end = x.e;
    } else {
      cur = { start: x.s, end: x.e, items: [x] };
      out.push(cur);
    }
  }
  return out;
}

function build(c) {
  const bed = c.start;
  const wake = c.end;
  const n = Math.floor((wake - bed) / MIN);
  const rank = new Uint8Array(n);
  for (const x of c.items) {
    const r = RANK[x.v];
    const a = Math.max(0, Math.ceil((x.s - bed) / MIN));
    const b = Math.min(n, Math.ceil((x.e - bed) / MIN));
    for (let i = a; i < b; i++) if (rank[i] < r) rank[i] = r;
  }
  const counts = { deep: 0, core: 0, rem: 0, awake: 0 };
  const segments = [];
  for (let i = 0; i < n; i++) {
    const st = STAGE_OF_RANK[rank[i]];
    counts[st]++;
    const last = segments[segments.length - 1];
    if (last && last.stage === st) last.end = i + 1;
    else segments.push({ stage: st, start: i, end: i + 1 });
  }
  const asleep = counts.deep + counts.core + counts.rem;
  return {
    key: keyOf(wake),
    bed,
    wake,
    ...counts,
    asleep,
    inBed: n,
    segments: segments.map((s) => ({ stage: s.stage, start: bed + s.start * MIN, end: bed + s.end * MIN })),
  };
}

function mean(xs) {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
}

function spread(xs) {
  if (!xs.length) return null;
  const m = mean(xs);
  return Math.sqrt(mean(xs.map((x) => (x - m) * (x - m))));
}

export function score(n, st) {
  const deepPct = n.asleep ? (n.deep / n.asleep) * 100 : 0;
  const remPct = n.asleep ? (n.rem / n.asleep) * 100 : 0;
  return Math.round(
    40 * Math.min(n.asleep / (st.hours * 60), 1) +
      20 * Math.min(deepPct / st.deep, 1) +
      20 * Math.min(remPct / st.rem, 1) +
      10 * Math.max(0, 1 - Math.abs(n.bedDelta) / 90) +
      10 * (n.inBed ? n.asleep / n.inBed : 0)
  );
}

export function nights(rawSamples, rawSettings) {
  const st = settings(rawSettings);
  const all = rawSamples.map(normalise).filter(Boolean);
  const stages = all.filter((x) => SLEEP_VALUES.has(x.v)).sort((a, b) => a.s - b.s || a.e - b.e);
  const hr = all.filter((x) => x.v === "HR" && x.q != null).sort((a, b) => a.s - b.s);
  const hrv = all.filter((x) => x.v === "HRV" && x.q != null).sort((a, b) => a.s - b.s);
  const byKey = new Map();
  for (const c of clusters(stages)) {
    const n = build(c);
    if (n.asleep < 60) continue;
    const prev = byKey.get(n.key);
    if (!prev || n.asleep > prev.asleep) byKey.set(n.key, n);
  }
  const inside = (list, n) => {
    const v = list.filter((x) => x.s >= n.bed && x.s <= n.wake).map((x) => x.q);
    return v.length ? Math.round(mean(v)) : null;
  };
  return [...byKey.values()]
    .sort((a, b) => (a.key < b.key ? -1 : 1))
    .map((n) => {
      n.hr = inside(hr, n);
      n.hrv = inside(hrv, n);
      n.deepPct = n.asleep ? (n.deep / n.asleep) * 100 : 0;
      n.remPct = n.asleep ? (n.rem / n.asleep) * 100 : 0;
      n.bedDelta = wrap(clockMinutes(n.bed) - hm(st.bed));
      n.wakeDelta = wrap(clockMinutes(n.wake) - hm(st.wake));
      n.score = score(n, st);
      return n;
    });
}

function pick(lines, max) {
  const fixes = lines.filter((l) => l.kind === "fix").slice(0, Math.min(2, max));
  const oks = lines.filter((l) => l.kind === "ok").slice(0, max - fixes.length);
  return [...oks, ...fixes];
}

const ok = (text) => ({ kind: "ok", text });
const fix = (text) => ({ kind: "fix", text });

export function nightComments(n, raw) {
  const st = settings(raw);
  const tol = st.tolerance;
  const out = [];
  const asleep = duration(n.asleep);
  out.push(n.asleep >= st.hours * 60 - 30 ? ok(`${asleep} asleep`) : fix(`${asleep}, under ${hoursText(st.hours)}h`));
  out.push(n.deepPct >= st.deep ? ok(`Deep ${duration(n.deep)}, above ${st.deep}%`) : fix(`Deep ${Math.round(n.deepPct)}%, under ${st.deep}%`));
  out.push(n.remPct >= st.rem ? ok(`REM ${duration(n.rem)}, above ${st.rem}%`) : fix(`REM ${Math.round(n.remPct)}%, under ${st.rem}%`));
  if (Math.abs(n.bedDelta) <= tol) out.push(ok(`In bed by ${clock(n.bed)}`));
  else if (n.bedDelta > tol) out.push(fix(`Bed ${n.bedDelta} min after ${clockOf(st.bed, false)}`));
  else out.push(ok(`Bed ${-n.bedDelta} min early`));
  if (Math.abs(n.wakeDelta) <= tol) out.push(ok(`Woke within ${tol} min of ${clockOf(st.wake, false)}`));
  else if (n.wakeDelta > tol) out.push(fix(`Woke ${n.wakeDelta} min after ${clockOf(st.wake, false)}`));
  return pick(out, 3);
}

function inKeys(all, keys) {
  const set = new Set(keys);
  return all.filter((n) => set.has(n.key));
}

function stageAverages(list) {
  const out = {};
  for (const s of STAGES) out[s] = list.length ? mean(list.map((n) => n[s])) : 0;
  return out;
}

export function week(all, k, raw) {
  const st = settings(raw);
  const keys = weekKeys(k);
  const list = inKeys(all, keys);
  const prev = inKeys(all, weekKeys(shiftKey(keys[0], -7)));
  const avgAsleep = mean(list.map((n) => n.asleep));
  const prevAsleep = mean(prev.map((n) => n.asleep));
  const hrs = list.filter((n) => n.hr != null).map((n) => n.hr);
  const prevHrs = prev.filter((n) => n.hr != null).map((n) => n.hr);
  const avgHr = mean(hrs);
  const prevHr = mean(prevHrs);
  const goal = (st.hours - 1) * 60;
  const over = list.filter((n) => n.asleep >= goal).length;
  const bedSpread = spread(list.map((n) => n.bedDelta));
  const lines = [];
  if (list.length) {
    const text = `${over} of ${list.length} nights over ${hoursText(st.hours - 1)}h`;
    lines.push(over / list.length >= 0.7 ? ok(text) : fix(text));
    const late = list.reduce((a, b) => (b.bedDelta > a.bedDelta ? b : a));
    if (late.bedDelta > 60) lines.push(fix(`${dayName(late.key)} bed ${clock(late.bed)}`));
    if (prevAsleep != null) {
      const d = avgAsleep - prevAsleep;
      if (d >= 10) lines.push(ok(`${Math.round(d)}m more than last week`));
      else if (d <= -10) lines.push(fix(`${Math.round(-d)}m less than last week`));
    }
    if (avgHr != null && prevHr != null) {
      const d = avgHr - prevHr;
      if (d <= -1) lines.push(ok(`Resting heart down ${Math.round(-d)}`));
      else if (d >= 2) lines.push(fix(`Resting heart up ${Math.round(d)}`));
    }
  }
  return {
    keys,
    nights: list,
    avgAsleep,
    avgScore: list.length ? Math.round(mean(list.map((n) => n.score))) : null,
    spread: bedSpread == null ? null : Math.round(bedSpread),
    over,
    count: list.length,
    change: avgAsleep != null && prevAsleep != null ? Math.round(avgAsleep - prevAsleep) : null,
    stages: stageAverages(list),
    hr: keys.map((key) => {
      const n = list.find((x) => x.key === key);
      return n ? n.hr : null;
    }),
    comments: pick(lines, 3),
  };
}

export function month(all, k, raw) {
  const st = settings(raw);
  const keys = monthKeys(k);
  const list = inKeys(all, keys);
  const prevKey = monthShift(k, -1);
  const prev = inKeys(all, monthKeys(prevKey));
  const avgAsleep = mean(list.map((n) => n.asleep));
  const bedSpread = spread(list.map((n) => n.bedDelta));
  const lines = [];
  if (list.length) {
    if (prev.length) {
      const d = mean(list.map((n) => n.deep)) - mean(prev.map((n) => n.deep));
      if (d >= 5) lines.push(ok(`Deep up ${Math.round(d)} min vs ${monthName(prevKey)}`));
      else if (d <= -5) lines.push(fix(`Deep down ${Math.round(-d)} min vs ${monthName(prevKey)}`));
    }
    const weekend = list.filter((n) => [0, 6].includes(parseKey(n.key).getDay())).map((n) => n.bedDelta);
    const weekdays = list.filter((n) => ![0, 6].includes(parseKey(n.key).getDay())).map((n) => n.bedDelta);
    if (weekend.length && weekdays.length) {
      const d = mean(weekend) - mean(weekdays);
      if (d >= 30) lines.push(fix(`Weekends ${Math.round(d)} min later`));
    }
    const sd = Math.round(bedSpread);
    lines.push(sd <= 30 ? ok(`Bedtime within ±${sd}m`) : fix(`Bedtime varies ±${sd}m`));
    lines.push(avgAsleep >= st.hours * 60 - 30 ? ok(`${duration(avgAsleep)} average`) : fix(`${duration(avgAsleep)} average, under ${hoursText(st.hours)}h`));
  }
  return {
    keys,
    nights: list,
    avgAsleep,
    avgScore: list.length ? Math.round(mean(list.map((n) => n.score))) : null,
    spread: bedSpread == null ? null : Math.round(bedSpread),
    stages: stageAverages(list),
    comments: pick(lines, 2),
  };
}
