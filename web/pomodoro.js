import * as store from "./store.js";
import { esc, dayKey, units, fmtUnits, fmtTime, readLocal, writeLocal } from "./util.js";

export const ui = { project: readLocal("pomodoro.project", "all"), days: 14 };

function projects() {
  return store.all("board.project").sort((a, b) => (a._pos ?? 0) - (b._pos ?? 0));
}

function sessions() {
  return store
    .all("board.session")
    .map((s) => ({ ...s, at: store.time.fromBoard(s.ended) }))
    .sort((a, b) => b.at - a.at);
}

function tint(p) {
  return p ? `var(--tint-${(p.hue ?? 0) % 8})` : "var(--faint)";
}

function sum(list) {
  return list.reduce((a, s) => a + (s.minutes || 0), 0);
}

function stat(label, minutes, extra) {
  return `<div class="stat card"><b>${fmtUnits(units(minutes))}</b><span>${label}</span><em>${extra ?? `${minutes} min`}</em></div>`;
}

function weekBars(list) {
  const days = [];
  const now = new Date();
  for (let i = 6; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
    const k = dayKey(d);
    days.push({ k, label: d.toLocaleDateString([], { weekday: "narrow" }), minutes: sum(list.filter((s) => dayKey(s.at) === k)) });
  }
  const max = Math.max(25, ...days.map((d) => d.minutes));
  return `<div class="card bars" aria-label="Last 7 days">
    ${days
      .map(
        (d) => `<div class="barcol ${d.k === dayKey(now) ? "today" : ""}"><span class="val">${d.minutes ? fmtUnits(units(d.minutes)) : ""}</span><div class="track"><i style="height:${Math.round((d.minutes / max) * 100)}%"></i></div><span class="lbl">${d.label}</span></div>`
      )
      .join("")}
  </div>`;
}

export function view() {
  const projs = projects();
  const byId = new Map(projs.map((p) => [p.id, p]));
  const all = sessions();
  const filtered = ui.project === "all" ? all : all.filter((s) => (ui.project === "none" ? !s.project || !byId.has(s.project) : s.project === ui.project));
  const now = new Date();
  const todayK = dayKey(now);
  const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7));
  const todayMin = sum(filtered.filter((s) => dayKey(s.at) === todayK));
  const weekMin = sum(filtered.filter((s) => s.at >= monday));
  const allMin = sum(filtered);
  const totals = new Map();
  for (const s of all) {
    const key = s.project && byId.has(s.project) ? s.project : "none";
    totals.set(key, (totals.get(key) || 0) + s.minutes);
  }
  const rows = projs.map((p) => ({ id: p.id, p, minutes: totals.get(p.id) || 0 }));
  if (totals.get("none")) rows.push({ id: "none", p: null, minutes: totals.get("none") });
  rows.sort((a, b) => b.minutes - a.minutes);
  const groups = [];
  const cutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ui.days + 1);
  for (const s of filtered) {
    if (s.at < cutoff) break;
    const k = dayKey(s.at);
    if (!groups.length || groups[groups.length - 1].k !== k) groups.push({ k, at: s.at, list: [] });
    groups[groups.length - 1].list.push(s);
  }
  const older = filtered.some((s) => s.at < cutoff);
  const chips = [["all", "All", null], ...projs.map((p) => [p.id, p.name || "Untitled", p]), ...(totals.get("none") ? [["none", "Unassigned", null]] : [])];
  return `<section class="pomodoro">
    <div class="chips scroll">${chips
      .map(([id, name, p]) => `<button class="chip ${ui.project === id ? "on" : ""}" data-pomo-project="${id}">${id === "all" ? "" : `<i style="background:${tint(p)}"></i>`}${esc(name)}</button>`)
      .join("")}</div>
    <div class="stats">
      ${stat("today", todayMin)}
      ${stat("this week", weekMin)}
      ${stat("all time", allMin, `${Math.round(allMin / 60)} h`)}
    </div>
    ${weekBars(filtered)}
    ${
      ui.project === "all"
        ? `<div class="card list">
      <h3>Projects</h3>
      ${
        rows.length
          ? rows
              .map(
                ({ id, p, minutes }) => `<button class="row" data-pomo-project="${id}"><i class="dot" style="background:${tint(p)}"></i><span class="grow">${esc(p ? p.name || "Untitled" : "Unassigned")}</span><span class="num">${fmtUnits(units(minutes))}</span><span class="sub">${minutes} min</span></button>`
              )
              .join("")
          : `<div class="empty">Sessions from Pocket on your Mac show up here.</div>`
      }
    </div>`
        : ""
    }
    <div class="sessions">
      ${groups
        .map(
          (g) => `<div class="card list">
        <h3>${g.k === todayK ? "Today" : g.at.toLocaleDateString([], { weekday: "long", day: "numeric", month: "short" })}<span class="count right">${fmtUnits(units(sum(g.list)))} · ${sum(g.list)} min</span></h3>
        ${g.list
          .map((s) => {
            const p = s.project ? byId.get(s.project) : null;
            const start = s.started ? store.time.fromBoard(s.started) : new Date(s.at.getTime() - s.minutes * 60000);
            return `<div class="row"><i class="dot" style="background:${tint(p)}"></i><span class="grow">${esc(p ? p.name || "Untitled" : "Unassigned")}${s.declared ? " <small>declared</small>" : ""}</span><span class="sub">${fmtTime(start)} – ${fmtTime(s.at)}</span><span class="num">${s.minutes}m</span></div>`;
          })
          .join("")}
      </div>`
        )
        .join("")}
      ${!groups.length ? `<div class="card empty big">No sessions in the last ${ui.days} days${ui.project === "all" ? "" : " for this project"}.</div>` : ""}
      ${older ? `<button class="ghost wide" data-pomo-more>Show earlier sessions</button>` : ""}
    </div>
  </section>`;
}

export function onClick(d) {
  if (d.pomoProject) {
    ui.project = d.pomoProject;
    ui.days = 14;
    writeLocal("pomodoro.project", ui.project);
    window.scrollTo(0, 0);
    return "render";
  }
  if (d.pomoMore !== undefined) {
    ui.days += 30;
    return "render";
  }
  return false;
}
