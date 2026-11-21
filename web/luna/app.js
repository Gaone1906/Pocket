import * as store from "./store.js";
import { $, esc, ICONS, readLocal, writeLocal, readSession, writeSession, isoNow } from "./util.js";
import * as S from "./sleep.js";

const SHORTCUT = "Luna%20Sync";
const LANES = ["awake", "rem", "core", "deep"];
const LANE_NAMES = { awake: "Awake", rem: "REM", core: "Core", deep: "Deep" };
const COLOURS = { awake: "var(--awake)", rem: "var(--rem)", core: "var(--core)", deep: "var(--deep)" };
const TONES = { good: "var(--accent)", fair: "var(--rem)", poor: "var(--awake)" };
const LETTERS = ["M", "T", "W", "T", "F", "S", "S"];

const ui = {
  view: readLocal("luna.view", "night"),
  key: null,
  back: "night",
  toast: "",
  setupError: "",
};

let cache = { rev: -1, nights: [], settings: null };

function model() {
  const rev = store.revision();
  if (cache.rev !== rev) {
    const raw = store.get("sleep.settings", "book");
    cache = { rev, settings: raw, nights: S.nights(store.all("sleep.sample"), raw) };
  }
  return cache;
}

const selected = () => ui.key || S.today();
const tone = (score) => TONES[S.scoreTone(score)] || "var(--line)";
const dur = (min) => (Math.round(min) < 60 ? `${Math.round(min)}m` : S.duration(min));
const dayLabel = (k) => `${S.dayName(k)} ${S.parseKey(k).getDate()}`;
const tipAttr = (id, ...lines) => ` data-tid="${esc(id)}" data-tip="${esc(lines.join("\n"))}"`;

function shares(t) {
  const asleep = t.deep + t.core + t.rem;
  const pct = (v, of) => (of > 0 ? Math.round((v / of) * 100) : 0);
  return { deep: pct(t.deep, asleep), core: pct(t.core, asleep), rem: pct(t.rem, asleep), awake: pct(t.awake, asleep + t.awake) };
}

function stageTip(id, t, k) {
  return tipAttr(id, `${dur(t[k])} · ${LANE_NAMES[k]} · ${shares(t)[k]}%`);
}

function header() {
  return `<header class="hd"><div class="tile"><img src="icon-192.png" alt=""></div><h1>Luna</h1><button class="circ" data-sync aria-label="Sync">${ICONS.sync}</button><button class="circ" data-go="settings" aria-label="Settings">${ICONS.settings}</button></header>
  <nav class="seg">${["night", "week", "month"].map((v) => `<button class="${ui.view === v ? "on" : ""}" data-go="${v}">${v[0].toUpperCase() + v.slice(1)}</button>`).join("")}</nav>`;
}

function arrows(prev, next, label, canNext) {
  return `<div class="range"><button class="chev" data-key="${prev}" aria-label="Earlier">${ICONS.left}</button><span>${esc(label)}</span><button class="chev${canNext ? "" : " off"}" ${canNext ? `data-key="${next}"` : "disabled"} aria-label="Later">${ICONS.right}</button></div>`;
}

function strip(m, k) {
  const keys = S.weekKeys(k);
  const now = S.today();
  const next = S.shiftKey(k, 7);
  const canNext = S.weekStart(next) <= now;
  return `<div class="card strip"><button class="chev" data-key="${S.shiftKey(k, -7)}" aria-label="Earlier">${ICONS.left}</button>${keys
    .map((d) => {
      const n = m.nights.find((x) => x.key === d);
      const dot = n ? `<i class="dot" style="background:${tone(n.score)}"></i>` : `<i class="dot${d > now ? " far" : ""}"></i>`;
      return `<button class="d${d === k ? " on" : ""}" data-key="${d}"${n ? tipAttr(`d-${d}`, `${dur(n.asleep)} · ${n.score}`) : ""}><span class="w">${S.dayName(d)}</span><span class="n">${S.parseKey(d).getDate()}</span>${dot}</button>`;
    })
    .join("")}<button class="chev${canNext ? "" : " off"}" ${canNext ? `data-key="${next > now ? now : next}"` : "disabled"} aria-label="Later">${ICONS.right}</button></div>`;
}

function ring(score, size, stroke, center, sub, tip = "") {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const f = Math.max(0, Math.min(100, score)) / 100;
  return `<div class="ring" style="width:${size}px;height:${size}px"${tip}><svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="var(--track)" stroke-width="${stroke}"/><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${tone(score)}" stroke-width="${stroke}" stroke-linecap="round" stroke-dasharray="${(c * f).toFixed(1)} ${c.toFixed(1)}"/></svg><div class="mid">${center}<span>${sub}</span></div></div>`;
}

function hourLabel(h, full) {
  const hh = ((h % 24) + 24) % 24;
  return `${hh % 12 || 12}${full ? (hh < 12 ? " am" : " pm") : ""}`;
}

function hypnogram(n) {
  const W = 320;
  const LW = 52;
  const H = 132;
  const w = W - LW;
  const lh = H / 4;
  const span = n.wake - n.bed;
  const x = (t) => LW + ((t - n.bed) / span) * w;
  let s = "";
  let prev = null;
  const hits = [];
  for (const [i, seg] of n.segments.entries()) {
    const lane = LANES.indexOf(seg.stage);
    const x0 = x(seg.start);
    const y = lane * lh;
    if (prev != null) {
      const y1 = Math.min(prev, lane) * lh + lh / 2;
      const y2 = Math.max(prev, lane) * lh + lh / 2;
      s += `<rect x="${(x0 - 0.75).toFixed(1)}" y="${y1.toFixed(1)}" width="1.5" height="${(y2 - y1).toFixed(1)}" fill="var(--line)"/>`;
    }
    s += `<rect x="${x0.toFixed(1)}" y="${(y + lh * 0.18).toFixed(1)}" width="${Math.max(x(seg.end) - x0, 2).toFixed(1)}" height="${(lh * 0.64).toFixed(1)}" rx="${Math.min(4, lh * 0.2).toFixed(1)}" fill="${COLOURS[seg.stage]}"/>`;
    const x1 = x(seg.end);
    const hw = Math.max(x1 - x0, 6);
    const mins = (seg.end - seg.start) / 60000;
    hits.push({ mins, rect: `<rect class="hit" x="${((x0 + x1) / 2 - hw / 2).toFixed(1)}" y="0" width="${hw.toFixed(1)}" height="${H}" fill="transparent"${tipAttr(`h-${n.key}-${i}`, `${dur(mins)} · ${LANE_NAMES[seg.stage]}`, `${S.clock(seg.start)} – ${S.clock(seg.end)}`)}/>` });
    prev = lane;
  }
  const hitText = hits
    .sort((a, b) => b.mins - a.mins)
    .map((h) => h.rect)
    .join("");
  const labels = LANES.map((l, i) => `<text x="0" y="${(i * lh + lh / 2 + 4).toFixed(1)}" class="lane">${LANE_NAMES[l]}</text>`).join("");
  const step = span > 5 * 3600000 ? 2 : 1;
  const first = new Date(n.bed);
  first.setMinutes(0, 0, 0);
  if (first.getTime() < n.bed) first.setHours(first.getHours() + 1);
  const ticks = [];
  for (let t = first.getTime(); t <= n.wake; t += step * 3600000) ticks.push(t);
  const tickText = ticks
    .map((t, i) => {
      const px = x(t);
      const anchor = px > W - 14 ? "end" : "middle";
      return `<text x="${px.toFixed(1)}" y="${H + 20}" text-anchor="${anchor}" class="tick">${hourLabel(new Date(t).getHours(), i === 0 || i === ticks.length - 1)}</text>`;
    })
    .join("");
  return `<svg class="chart" viewBox="0 0 ${W} ${H + 26}" role="img" aria-label="Hypnogram">${labels}${s}${tickText}${hitText}</svg>`;
}

function stackBar(t, h, id) {
  const tot = S.STAGES.reduce((a, k) => a + t[k], 0) || 1;
  return `<div class="stack" style="height:${h}px;border-radius:${h / 2}px">${S.STAGES.map((k) => (t[k] > 0 ? `<i style="flex:${(t[k] / tot).toFixed(4)};background:${COLOURS[k]}"${stageTip(`b-${id}-${k}`, t, k)}></i>` : "")).join("")}</div>`;
}

function legend(t, id) {
  return `<div class="legend">${[
    ["deep", "Deep"],
    ["core", "Core"],
    ["rem", "REM"],
    ["awake", "Awake"],
  ]
    .map(([k, n]) => `<div${stageTip(`l-${id}-${k}`, t, k)}><span><i class="sw" style="background:${COLOURS[k]}"></i>${n}</span><b>${S.duration(t[k])}</b></div>`)
    .join("")}</div>`;
}

function says(lines) {
  if (!lines.length) return "";
  return `<div class="card says">${lines.map((l) => `<div class="say"><span class="ic ${l.kind === "ok" ? "ok" : "up"}">${l.kind === "ok" ? ICONS.ok : ICONS.up}</span><span>${esc(l.text)}</span></div>`).join("")}</div>`;
}

function viewNight() {
  const m = model();
  const k = selected();
  const n = m.nights.find((x) => x.key === k);
  if (!n) {
    return `<main class="fill">${header()}${strip(m, k)}<div class="card empty"><div class="moon">${ICONS.moon}</div><button class="btn wide" data-sync>${ICONS.sync}<span>Sync</span></button></div></main>`;
  }
  return `<main>${header()}${strip(m, k)}
    <div class="card top">${ring(n.score, 140, 13, `<b class="big">${n.score}</b>`, S.duration(n.asleep), tipAttr(`r-${n.key}`, `Score ${n.score}`, `${dur(n.asleep)} asleep`))}<div class="facts"><div class="kv"><span>Bed</span><b>${S.clock(n.bed)}</b></div><div class="kv"><span>Wake</span><b>${S.clock(n.wake)}</b></div><div class="rule"></div><div class="kv"><span>In bed</span><b>${dur(n.inBed)}</b></div><div class="kv"><span>Awake</span><b>${dur(n.awake)}</b></div></div></div>
    <div class="card hyp">${hypnogram(n)}${legend(n, "n")}</div>
    ${says(S.nightComments(n, m.settings))}
  </main>`;
}

function shortDate(k) {
  const d = S.parseKey(k);
  return `${d.getDate()} ${d.toLocaleDateString("en-GB", { month: "short" })}`;
}

function sinceNoon(ms) {
  const d = new Date(ms);
  return (((d.getHours() * 60 + d.getMinutes() - 720) % 1440) + 1440) % 1440;
}

function targetSinceNoon(t) {
  const [h, mm] = t.split(":").map(Number);
  return (((h * 60 + mm - 720) % 1440) + 1440) % 1440;
}

function windowChart(wk, st) {
  const W = 320;
  const AX = 48;
  const H = 250;
  const w = W - AX;
  const bw = w / 7;
  const tb = targetSinceNoon(st.bed);
  const tw = targetSinceNoon(st.wake);
  const beds = wk.nights.map((n) => sinceNoon(n.bed));
  const wakes = wk.nights.map((n) => sinceNoon(n.wake));
  const top = Math.floor((Math.min(tb, ...beds) - 30) / 60) * 60;
  const bottom = Math.ceil((Math.max(tw, ...wakes) + 30) / 60) * 60;
  const y = (v) => ((v - top) / (bottom - top)) * H;
  const now = S.today();
  let s = "";
  let hits = "";
  for (const v of [tb, tw]) s += `<line x1="${AX}" x2="${W}" y1="${y(v).toFixed(1)}" y2="${y(v).toFixed(1)}" stroke="var(--accent)" stroke-dasharray="3 4" opacity=".55"/>`;
  const firstHour = Math.ceil(top / 60);
  const bedHour = Math.floor(tb / 60);
  let lastPm = null;
  for (let h = firstHour; h * 60 <= bottom; h++) {
    if ((h - bedHour) % 2 !== 0) continue;
    const clockH = (h + 12) % 24;
    const pm = clockH >= 12;
    const full = lastPm === null || lastPm !== pm;
    lastPm = pm;
    s += `<text x="${AX - 8}" y="${(y(h * 60) + 4).toFixed(1)}" text-anchor="end" class="tick">${hourLabel(clockH, full)}</text>`;
  }
  wk.keys.forEach((k, i) => {
    const cx = AX + i * bw + bw / 2;
    const n = wk.nights.find((x) => x.key === k);
    if (n) {
      const y1 = y(sinceNoon(n.bed));
      const y2 = Math.max(y1 + 22, y(sinceNoon(n.wake)));
      s += `<rect x="${(cx - 11).toFixed(1)}" y="${y1.toFixed(1)}" width="22" height="${(y2 - y1).toFixed(1)}" rx="11" fill="${tone(n.score)}"/>`;
      hits += `<rect class="hit" data-pick="${k}" x="${(cx - bw / 2).toFixed(1)}" y="0" width="${bw.toFixed(1)}" height="${H}" fill="transparent"${tipAttr(`w-${k}`, dayLabel(k), `${S.clock(n.bed)} – ${S.clock(n.wake)}`, `${dur(n.asleep)} · ${n.score}`)}/>`;
    } else if (k >= now) {
      s += `<rect x="${(cx - 11).toFixed(1)}" y="${y(tb).toFixed(1)}" width="22" height="${(y(tw) - y(tb)).toFixed(1)}" rx="11" fill="none" stroke="var(--line)" stroke-dasharray="3 3"/>`;
    }
    s += `<text x="${cx.toFixed(1)}" y="${H + 26}" text-anchor="middle" class="day">${LETTERS[i]}</text>`;
  });
  return `<svg class="chart" viewBox="0 0 ${W} ${H + 32}" role="img" aria-label="Sleep window">${s}${hits}</svg>`;
}

function viewWeek() {
  const m = model();
  const k = selected();
  const st = S.settings(m.settings);
  const wk = S.week(m.nights, k, m.settings);
  const now = S.today();
  const next = S.shiftKey(k, 7);
  const chip = wk.change == null ? "" : `<span class="chip ${wk.change >= 0 ? "g" : "o"}">${wk.change >= 0 ? "+" : "−"}${Math.abs(wk.change)}m</span>`;
  return `<main>${header()}
    ${arrows(S.shiftKey(k, -7), next > now ? now : next, rangeLabelWeek(wk.keys), S.weekStart(next) <= now)}
    <div class="card"><div class="wtop"><div><div class="big xl">${wk.avgAsleep == null ? "–" : S.duration(wk.avgAsleep)}</div><div class="lbl">avg${wk.avgScore == null ? "" : ` · ${wk.avgScore}`}</div></div>${chip}</div>${windowChart(wk, st)}</div>
    ${wk.count ? `<div class="card stages">${stackBar(wk.stages, 14, "w")}${legend(wk.stages, "w")}</div>` : ""}
    ${says(wk.comments)}
  </main>`;
}

function rangeLabelWeek(keys) {
  const a = S.parseKey(keys[0]);
  const b = S.parseKey(keys[6]);
  return a.getMonth() === b.getMonth() ? `${a.getDate()} – ${shortDate(keys[6])}` : `${shortDate(keys[0])} – ${shortDate(keys[6])}`;
}

function lineChart(mo, st) {
  const W = 320;
  const H = 92;
  const pts = mo.keys.map((k) => {
    const n = mo.nights.find((x) => x.key === k);
    return n ? n.asleep / 60 : null;
  });
  const vals = pts.filter((v) => v != null);
  const lo = Math.min(st.hours - 3, ...vals.map((v) => v - 0.25));
  const hi = Math.max(st.hours + 1.25, ...vals.map((v) => v + 0.25));
  const x = (i) => 4 + (i / Math.max(1, pts.length - 1)) * (W - 8);
  const y = (v) => H - ((v - lo) / (hi - lo)) * H;
  let p = "";
  pts.forEach((v, i) => {
    if (v == null) return;
    p += (i && pts[i - 1] != null ? "L" : "M") + x(i).toFixed(1) + "," + y(v).toFixed(1);
  });
  const band = `<rect x="0" y="${y(st.hours + 1).toFixed(1)}" width="${W}" height="${(y(st.hours - 0.5) - y(st.hours + 1)).toFixed(1)}" fill="var(--accent-soft)" opacity=".6" rx="6"/>`;
  const target = `<line x1="0" x2="${W}" y1="${y(st.hours).toFixed(1)}" y2="${y(st.hours).toFixed(1)}" stroke="var(--accent)" stroke-dasharray="3 4" opacity=".6"/>`;
  const dots = pts.map((v, i) => (v == null ? "" : `<circle cx="${x(i).toFixed(1)}" cy="${y(v).toFixed(1)}" r="2.6" fill="var(--card)" stroke="var(--accent)" stroke-width="1.6"/>`)).join("");
  const step = (W - 8) / Math.max(1, pts.length - 1);
  const hits = pts
    .map((v, i) => (v == null ? "" : `<rect class="hit" data-pick="${mo.keys[i]}" x="${(x(i) - step / 2).toFixed(1)}" y="0" width="${step.toFixed(1)}" height="${H}" fill="transparent"${tipAttr(`p-${mo.keys[i]}`, `${dayLabel(mo.keys[i])} · ${dur(v * 60)}`)}/>`))
    .join("");
  return `<svg class="chart line" viewBox="0 0 ${W} ${H}" role="img" aria-label="Hours asleep">${band}${target}<path d="${p}" fill="none" stroke="var(--accent)" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>${dots}${hits}</svg>`;
}

function viewMonth() {
  const m = model();
  const k = selected();
  const st = S.settings(m.settings);
  const mo = S.month(m.nights, k, m.settings);
  const now = S.today();
  const d = S.parseKey(k);
  const next = S.monthShift(k, 1);
  const lead = (S.parseKey(mo.keys[0]).getDay() + 6) % 7;
  const label = S.monthName(k) + (d.getFullYear() === new Date().getFullYear() ? "" : ` ${d.getFullYear()}`);
  const cells = mo.keys
    .map((day) => {
      const n = mo.nights.find((x) => x.key === day);
      const cls = n ? `c ${S.scoreTone(n.score)}` : "c none";
      return `<button class="${cls}${day === now ? " sel" : ""}" data-pick="${day}"${n ? tipAttr(`m-${day}`, dayLabel(day), `${dur(n.asleep)} · ${n.score}`) : ""}>${S.parseKey(day).getDate()}</button>`;
    })
    .join("");
  return `<main>${header()}
    ${arrows(S.monthShift(k, -1), next > now ? now : next, label, next <= now)}
    <div class="card"><div class="mgrid">${LETTERS.map((l) => `<span class="w">${l}</span>`).join("")}${"<span></span>".repeat(lead)}${cells}</div></div>
    <div class="card"><div class="stats"><div><b class="big">${mo.avgAsleep == null ? "–" : S.duration(mo.avgAsleep)}</b><span class="lbl">avg</span></div><div><b class="big">${mo.spread == null ? "–" : `±${mo.spread}m`}</b><span class="lbl">bedtime</span></div><div class="end"><b class="big">${mo.avgScore ?? "–"}</b><span class="lbl">score</span></div></div>${lineChart(mo, st)}</div>
    ${says(mo.comments)}
  </main>`;
}

function hoursOptions(cur) {
  const list = [];
  for (let h = 4; h <= 12; h += 0.5) list.push(h);
  if (!list.includes(cur)) list.push(cur);
  return list.sort((a, b) => a - b);
}

function pctOptions(from, to, cur) {
  const list = [];
  for (let p = from; p <= to; p++) list.push(p);
  if (!list.includes(cur)) list.push(cur);
  return list.sort((a, b) => a - b);
}

function pill(field, text, control) {
  return `<label class="r"><span>${field}</span><span class="v p">${esc(text)}${control}</span></label>`;
}

function viewSettings() {
  const m = model();
  const st = S.settings(m.settings);
  const snap = store.snapshot();
  const last = snap.lastSync ? new Date(snap.lastSync) : null;
  const synced = last ? (S.keyOf(last.getTime()) === S.today() ? S.clock(last.getTime()) : `${shortDate(S.keyOf(last.getTime()))}, ${S.clock(last.getTime())}`) : "–";
  const pad = (t) => t.padStart(5, "0");
  return `<main>
    <header class="hd"><button class="circ" data-go="${ui.back || "night"}" aria-label="Back">${ICONS.left}</button><h1 class="sm">Settings</h1></header>
    <div class="card set">
      ${pill("Bed", S.clockOf(st.bed), `<input type="time" data-field="bed" value="${pad(st.bed)}" aria-label="Bed">`)}
      ${pill("Wake", S.clockOf(st.wake), `<input type="time" data-field="wake" value="${pad(st.wake)}" aria-label="Wake">`)}
      ${pill("Sleep", `${S.hoursText(st.hours)}h`, `<select data-field="hours" aria-label="Sleep">${hoursOptions(st.hours).map((h) => `<option value="${h}" ${h === st.hours ? "selected" : ""}>${S.hoursText(h)}h</option>`).join("")}</select>`)}
      ${pill("Deep", `${st.deep}%`, `<select data-field="deep" aria-label="Deep">${pctOptions(5, 30, st.deep).map((p) => `<option value="${p}" ${p === st.deep ? "selected" : ""}>${p}%</option>`).join("")}</select>`)}
      ${pill("REM", `${st.rem}%`, `<select data-field="rem" aria-label="REM">${pctOptions(10, 35, st.rem).map((p) => `<option value="${p}" ${p === st.rem ? "selected" : ""}>${p}%</option>`).join("")}</select>`)}
    </div>
    <div class="card set">
      <button class="r" data-shortcut><span>Luna Sync</span><span class="v">${ICONS.ext}</span></button>
      <div class="r"><span>Synced</span><span class="m">${synced}</span></div>
    </div>
    ${snap.problem ? `<div class="warn">${esc(snap.problem)}</div>` : ""}
    <div class="card set">
      <button class="r" data-export><span>Download a copy</span><span class="v">${ICONS.right}</span></button>
      <button class="r" data-signout><span class="danger">Disconnect</span></button>
    </div>
  </main>`;
}

function viewConnect() {
  return `<main class="connect">
    <div class="hero"><div class="bigtile"><img src="icon-512.png" alt=""></div><div class="big name">Luna</div></div>
    <form data-form="connect" class="col">
      <input name="link" placeholder="Setup link" autocomplete="off" autocapitalize="off" spellcheck="false" aria-label="Setup link">
      <button class="btn">Connect</button>
      ${ui.setupError ? `<div class="warn">${esc(ui.setupError)}</div>` : ""}
    </form>
  </main>`;
}

function render() {
  const app = $("#app");
  if (!store.signedIn()) {
    app.innerHTML = viewConnect();
    return;
  }
  const views = { night: viewNight, week: viewWeek, month: viewMonth, settings: viewSettings };
  if (!views[ui.view]) ui.view = "night";
  app.innerHTML = views[ui.view]() + (ui.toast ? `<div class="toast">${ICONS.ok}<span>${esc(ui.toast)}</span></div>` : "");
  keepTip();
}

const tip = { node: null, el: null, id: null, x: 0, y: 0, touch: false, swallow: false };

function tipNode() {
  if (!tip.node) {
    tip.node = document.createElement("div");
    tip.node.className = "tip";
    tip.node.setAttribute("role", "tooltip");
    document.body.appendChild(tip.node);
  }
  return tip.node;
}

function showTip(target, x, y) {
  const node = tipNode();
  const id = target.dataset.tid;
  if (tip.id !== id) {
    const [head, ...rest] = target.dataset.tip.split("\n");
    node.innerHTML = `<b>${esc(head)}</b>${rest.map((l) => `<span>${esc(l)}</span>`).join("")}`;
  }
  if (tip.el && tip.el !== target) tip.el.classList.remove("act");
  target.classList.add("act");
  tip.el = target;
  tip.id = id;
  tip.x = x;
  tip.y = y;
  node.classList.add("on");
  const w = node.offsetWidth;
  const h = node.offsetHeight;
  const left = Math.max(8, Math.min(window.innerWidth - w - 8, x - w / 2));
  const gap = tip.touch ? 30 : 14;
  const top = y - h - gap < 8 ? y + gap : y - h - gap;
  node.style.transform = `translate(${Math.round(left)}px, ${Math.round(top)}px)`;
}

function hideTip() {
  if (!tip.id) return;
  tip.id = null;
  if (tip.el) tip.el.classList.remove("act");
  tip.el = null;
  tipNode().classList.remove("on");
}

function keepTip() {
  if (!tip.id) return;
  const t = document.querySelector(`[data-tid="${CSS.escape(tip.id)}"]`);
  if (t) showTip(t, tip.x, tip.y);
  else hideTip();
}

document.addEventListener("pointermove", (e) => {
  if (e.pointerType !== "mouse") return;
  tip.touch = false;
  const t = e.target.closest && e.target.closest("[data-tip]");
  if (t) showTip(t, e.clientX, e.clientY);
  else hideTip();
});

document.addEventListener("pointerdown", (e) => {
  tip.swallow = false;
  tip.touch = e.pointerType !== "mouse";
});

document.addEventListener("pointerup", (e) => {
  if (e.pointerType === "mouse") return;
  const t = e.target.closest && e.target.closest("[data-tip]");
  if (!t) return hideTip();
  const again = tip.id === t.dataset.tid;
  showTip(t, e.clientX, e.clientY);
  if (t.dataset.pick && !again) tip.swallow = true;
});

document.documentElement.addEventListener("pointerleave", (e) => {
  if (e.pointerType === "mouse") hideTip();
});
window.addEventListener("scroll", hideTip, { passive: true });
window.addEventListener("resize", hideTip);

function toast(text) {
  ui.toast = text;
  render();
  clearTimeout(toast.t);
  toast.t = setTimeout(() => {
    ui.toast = "";
    render();
  }, 2600);
}

function go(view) {
  if (view === "settings") ui.back = ui.view === "settings" ? ui.back : ui.view;
  ui.view = view;
  ui.setupError = "";
  if (view !== "settings") writeLocal("luna.view", view);
  render();
  window.scrollTo(0, 0);
}

function nightKeys() {
  return model().nights.map((n) => n.key);
}

function onApple() {
  const ua = navigator.userAgent;
  return /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
}

async function pullAndReport(before) {
  await store.syncNow();
  await store.syncNow();
  const known = new Set(before);
  const fresh = nightKeys().filter((k) => !known.has(k)).length;
  const problem = store.snapshot().problem;
  if (problem) {
    ui.toast = "";
    render();
    return;
  }
  toast(fresh ? `${fresh} ${fresh === 1 ? "night" : "nights"}` : "Up to date");
}

function startSync() {
  const before = nightKeys();
  if (!onApple()) return pullAndReport(before);
  writeSession("luna.before", JSON.stringify(before));
  if (standalone()) {
    pending = { before, at: Date.now() };
    location.href = `shortcuts://run-shortcut?name=${SHORTCUT}`;
    return;
  }
  const back = location.href.split("#")[0] + "#synced";
  location.href = `shortcuts://x-callback-url/run-shortcut?name=${SHORTCUT}&x-success=${encodeURIComponent(back)}`;
}

let pending = null;

function standalone() {
  return navigator.standalone === true || (window.matchMedia && window.matchMedia("(display-mode: standalone)").matches);
}

function backInApp() {
  if (document.visibilityState !== "visible" || !pending) return;
  const { before, at } = pending;
  pending = null;
  writeSession("luna.before", null);
  if (Date.now() - at < 1500) {
    pending = { before, at };
    return;
  }
  setTimeout(() => pullAndReport(before), 600);
}

function returnedFromShortcut() {
  if (location.hash !== "#synced") return;
  history.replaceState(null, "", location.pathname + location.search);
  if (!store.signedIn()) return;
  let before = null;
  try {
    before = JSON.parse(readSession("luna.before") || "null");
  } catch (e) {}
  writeSession("luna.before", null);
  pullAndReport(Array.isArray(before) ? before : nightKeys());
}

function saveSetting(field, value) {
  const raw = store.get("sleep.settings", "book") || {};
  store.put("sleep.settings", "book", { ...S.settings(raw), ...raw, [field]: value, updated: isoNow() });
}

document.addEventListener("click", async (e) => {
  if (tip.swallow) {
    tip.swallow = false;
    return;
  }
  const t = e.target.closest("[data-go],[data-key],[data-pick],[data-sync],[data-shortcut],[data-export],[data-signout]");
  if (!t) return;
  const d = t.dataset;
  if (d.go) return go(d.go);
  if (d.key) {
    ui.key = d.key === S.today() ? null : d.key;
    return render();
  }
  if (d.pick) {
    ui.key = d.pick === S.today() ? null : d.pick;
    return go("night");
  }
  if (d.sync !== undefined) return startSync();
  if (d.shortcut !== undefined) {
    location.href = `shortcuts://open-shortcut?name=${SHORTCUT}`;
    return;
  }
  if (d.export !== undefined) {
    const blob = new Blob([JSON.stringify(store.exportDocuments(), null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `luna-${S.today()}.json`;
    a.click();
    return;
  }
  if (d.signout !== undefined) {
    if (confirm("Disconnect?")) store.disconnect();
  }
});

document.addEventListener("change", (e) => {
  const t = e.target;
  const field = t.dataset && t.dataset.field;
  if (!field) return;
  if (field === "bed" || field === "wake") {
    if (!/^\d{2}:\d{2}$/.test(t.value)) return;
    saveSetting(field, t.value);
  } else {
    const v = Number(t.value);
    if (!(v > 0)) return;
    saveSetting(field, v);
  }
  t.blur();
  render();
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const form = e.target;
  if (form.dataset.form !== "connect") return;
  const found = parseLink(new FormData(form).get("link") || "");
  if (!found) {
    ui.setupError = "Not a setup link";
    return render();
  }
  ui.setupError = "";
  store.configure(found.url, found.key);
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
  if (active && active.matches && active.matches("input, select")) return;
  render();
}

readSetupLink();
store.subscribe(onStore);
render();
if (location.hash === "#synced") returnedFromShortcut();
else if (store.signedIn()) store.syncNow();
window.addEventListener("hashchange", returnedFromShortcut);
document.addEventListener("visibilitychange", backInApp);
setInterval(() => {
  if (!(document.activeElement && document.activeElement.matches("input, select"))) render();
}, 60000);
if ("serviceWorker" in navigator && location.protocol !== "file:") navigator.serviceWorker.register("sw.js").catch(() => {});
