import { esc, ICONS } from "./util.js";
import { avatar, card, posterStyle, runtime } from "./films.js";
import { attach, fly } from "./drag.js";

export const MAX_MEMBERS = 8;

export function caller(base, headers = {}) {
  return async (body) => {
    let res;
    try {
      res = await fetch(base, { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });
    } catch (e) {
      const err = new Error(navigator.onLine ? "Can't reach Fabula right now" : "You're offline");
      err.status = 0;
      throw err;
    }
    let data = null;
    try {
      data = await res.json();
    } catch (e) {}
    if (!res.ok) {
      const err = new Error((data && data.error) || "Something went wrong");
      err.status = res.status;
      throw err;
    }
    return data;
  };
}

export function createRoom({ call, code = null, member = null, save = () => {}, onChange = () => {} }) {
  const room = { code, member, state: null, error: null, busy: false, pending: new Set(), timer: null, visible: false };

  const set = (patch) => {
    Object.assign(room, patch);
    onChange();
  };

  const adopt = (s) => {
    if (!s || !s.code) return;
    room.state = s;
    room.code = s.code;
    if (s.me && s.me.id) room.member = s.me.id;
    for (const id of [...room.pending]) if ((s.swiped || []).includes(id)) room.pending.delete(id);
    room.error = null;
    save(room.code, room.member);
    if (s.matched) stop();
  };

  const fail = (e) => {
    if (e.status === 404 || e.status === 403) {
      stop();
      save(null, null);
      if (!(room.state && room.state.matched)) room.state = null;
    }
    room.error = { message: e.message, status: e.status };
  };

  async function run(body) {
    try {
      adopt(await call(body));
    } catch (e) {
      fail(e);
    }
    onChange();
  }

  room.create = async (name, langs, genres) => {
    set({ busy: true, error: null, state: null });
    await run({ action: "create", name, langs, genres });
    room.busy = false;
    onChange();
    if (room.member) poll();
  };

  room.join = async (name) => {
    set({ busy: true, error: null });
    await run({ action: "join", code: room.code, name });
    room.busy = false;
    onChange();
    if (room.member) poll();
  };

  room.refresh = async () => {
    if (!room.code || !room.member) return;
    try {
      adopt(await call({ action: "state", code: room.code, member: room.member }));
    } catch (e) {
      if (e.status) fail(e);
    }
    onChange();
  };

  room.start = () => run({ action: "start", code: room.code, member: room.member });

  room.swipe = (tmdb, yes) => {
    room.pending.add(tmdb);
    onChange();
    return run({ action: "swipe", code: room.code, member: room.member, tmdb, yes });
  };

  room.leave = async () => {
    const { code: c, member: m } = room;
    stop();
    save(null, null);
    Object.assign(room, { code: null, member: null, state: null, error: null, pending: new Set() });
    onChange();
    if (c && m) {
      try {
        await call({ action: "leave", code: c, member: m });
      } catch (e) {}
    }
  };

  room.current = () => {
    const s = room.state;
    if (!s || !s.started) return null;
    const done = new Set([...(s.swiped || []), ...room.pending]);
    return (s.deck || []).filter((f) => !done.has(f.tmdb));
  };

  function stop() {
    clearInterval(room.timer);
    room.timer = null;
  }

  function poll() {
    stop();
    if (!room.member || (room.state && room.state.matched)) return;
    room.timer = setInterval(() => {
      if (document.visibilityState === "visible" && room.visible) room.refresh();
    }, 2000);
  }

  room.poll = poll;
  room.stop = stop;
  room.show = (on) => {
    room.visible = on;
    if (on && room.member && !(room.state && room.state.matched)) {
      if (!room.timer) poll();
      room.refresh();
    }
  };

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && room.visible) room.refresh();
  });

  return room;
}

function hostName(s) {
  const h = (s.members || []).find((m) => m.host);
  return h ? h.name : "";
}

export function nightTitle(s, host) {
  if (host || !s) return "Match night";
  const name = hostName(s);
  return name ? `${name}'s movie night` : "Movie night";
}

function memberRows(s, host) {
  const rows = (s.members || []).map(
    (m, i) => `<div class="member">${avatar(m.name, i)}<span class="mname">${esc(m.name)}${m.me && !host ? " (you)" : ""}</span><span class="mtag ${m.host ? "" : "ok"}">${m.host ? "host" : "joined"}</span></div>`
  );
  if ((s.members || []).length < MAX_MEMBERS) rows.push(`<div class="member wait"><span class="avatar empty"></span><span class="mname">Waiting for more…</span></div>`);
  return rows.join("");
}

export function lobbyView(room, { host, link = "", top = "" }) {
  const s = room.state;
  const n = (s.members || []).length;
  return `<main class="screen match">
    ${top}
    <div class="mhead"><h1>${esc(nightTitle(s, host))}</h1></div>
    ${
      host
        ? `<div class="linkbox"><span class="mono">${esc(link.replace(/^https?:\/\//, ""))}</span><div class="two">
        <button class="btn" data-act="match-share">Share link</button><button class="btn ghost" data-act="match-copy">Copy</button></div></div>`
        : ""
    }
    <div class="members"><span class="section">In the room · ${n} of ${MAX_MEMBERS}</span>${memberRows(s, host)}</div>
    <div class="foot">${
      host
        ? `<button class="btn big" data-act="match-start" ${n < 2 ? "disabled" : ""}>Start swiping with ${n}</button>`
        : `<div class="status">Waiting for ${esc(hostName(s) || "the host")} to start</div>`
    }</div>
  </main>`;
}

export function swipeView(room, { host, top = "" }) {
  const s = room.state;
  const left = room.current() || [];
  const total = s.total || (s.deck || []).length;
  const k = Math.min(total, total - left.length + 1);
  const everyone = (s.members || []).every((m) => m.swiped >= total);
  const me = (s.members || []).find((m) => m.me);
  let body;
  if (left.length) {
    body = `<div class="stack">${card(left[1], { why: false })}${card(left[0], { top: true, why: false })}</div>
      <div class="votes"><button class="vote no" data-act="match-no" aria-label="No">${ICONS.close}</button><button class="vote yes" data-act="match-yes" aria-label="Yes">${ICONS.check}</button></div>`;
  } else {
    body = `<div class="stack"><div class="done"><b>${everyone ? "No match this time" : "No match yet"}</b>${
      everyone ? "" : `<span>Waiting for the others</span>`
    }</div></div><div class="votes"></div>`;
  }
  return `<main class="screen match swiping">
    ${top}
    <div class="mhead row"><h1 class="small">${esc(nightTitle(s, host))}</h1>${!host && me ? `<span class="faint">${esc(me.name)}</span>` : ""}</div>
    <div class="faces">${(s.members || []).map((m, i) => avatar(m.name, i, "sm")).join("")}<span class="muted">${left.length ? `Card ${k} of ${total} · no match yet` : `${total} of ${total}`}</span></div>
    ${body}
  </main>`;
}

export function matchedView(room, { host }) {
  const s = room.state;
  const f = s.matched;
  const n = (s.members || []).length;
  const at = (s.deck || []).findIndex((d) => d.tmdb === f.tmdb) + 1;
  const crew = [f.year, runtime(f.runtime), (f.genres || []).slice(0, 2).join(", "), f.director].filter(Boolean).join(" · ");
  return `<main class="screen matched">
    <h1 class="big">It's a match!</h1>
    <span class="muted">${n === 2 ? "Both of you" : `All ${n} of you`} said yes${at ? ` on card ${at}` : ""}</span>
    <div class="mposter" style="${posterStyle(f, "w500")}"><span>${esc(f.title)}</span></div>
    <div class="stackfaces">${(s.members || []).map((m, i) => avatar(m.name, i, "lg")).join("")}</div>
    <span class="muted">${esc(crew)}</span>
    ${f.providers && f.providers.length ? `<span class="stream">Streaming on ${esc(f.providers[0])} in India</span>` : ""}
    ${host ? `<div class="foot"><button class="btn big" data-act="match-watch">Watching this</button></div>` : ""}
  </main>`;
}

export function notice(title, sub = "", action = "") {
  return `<div class="notice"><img class="bigtile" src="logo-96.png" alt=""><b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ""}${action}</div>`;
}

export function noticeView(title, sub = "", action = "") {
  return `<main class="screen match">${notice(title, sub, action)}</main>`;
}

export function nameSheet(value, busy, error = "") {
  const ok = value.trim() && !busy;
  return `<div class="sheet open name" data-sheet="name"><form class="panel" data-form="name">
    <div class="grip"></div>
    <h2>What's your name?</h2>
    <input class="field" name="name" data-input="name" aria-label="Your name" placeholder="Your name" maxlength="20" autocomplete="given-name" value="${esc(value)}">
    ${error ? `<div class="warn">${esc(error)}</div>` : ""}
    <button type="submit" class="btn big" ${ok ? "" : "disabled"}>Join</button>
  </form></div>`;
}

export function bindSwipe(root, room) {
  const el = root.querySelector(".match [data-card]");
  if (!el) return;
  const id = Number(el.dataset.card);
  let busy = false;
  const go = async (dir) => {
    if (busy) return;
    busy = true;
    await fly(el, dir);
    room.swipe(id, dir === "right");
  };
  attach(el, { up: false, onRelease: (dir) => dir && go(dir) });
  root.querySelectorAll("[data-act=match-no],[data-act=match-yes]").forEach((b) =>
    b.addEventListener("click", (e) => {
      e.stopPropagation();
      go(b.dataset.act === "match-yes" ? "right" : "left");
    })
  );
  return go;
}
