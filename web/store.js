const KEY = "pocket.cloud.v1";
const EPOCH_2001 = 978307200;

const listeners = new Set();
let state = load();
let pulling = false;
let flushing = false;
let flushTimer = null;
let pollTimer = null;

function blank() {
  return {
    config: null,
    session: null,
    device: defaultDevice(),
    cursor: "1970-01-01T00:00:00Z",
    records: {},
    outbox: {},
    lastSync: null,
    problem: null,
  };
}

function defaultDevice() {
  const ua = navigator.userAgent;
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return "iPad";
  if (/iPhone/.test(ua)) return "iPhone";
  if (/Android/.test(ua)) return "Android";
  if (/Mac/.test(ua)) return "Mac browser";
  if (/Windows/.test(ua)) return "Windows";
  return "Browser";
}

function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return { ...blank(), ...JSON.parse(raw) };
  } catch (e) {}
  return blank();
}

function persist() {
  try {
    localStorage.setItem(KEY, JSON.stringify(state));
  } catch (e) {}
}

function emit() {
  persist();
  listeners.forEach((fn) => fn());
}

export function subscribe(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function snapshot() {
  return state;
}

export function all(kind) {
  const out = [];
  for (const key in state.records) {
    const r = state.records[key];
    if (r.kind === kind && !r.deleted) out.push(r.data);
  }
  return out;
}

export function get(kind, id) {
  const r = state.records[kind + "|" + id];
  return r && !r.deleted ? r.data : null;
}

export function put(kind, id, data) {
  const key = kind + "|" + id;
  state.records[key] = { kind, id, data, deleted: false, updated_at: new Date().toISOString() };
  state.outbox[key] = true;
  emit();
  scheduleFlush();
}

export function remove(kind, id) {
  const key = kind + "|" + id;
  const prev = state.records[key];
  state.records[key] = { kind, id, data: prev ? prev.data : {}, deleted: true, updated_at: new Date().toISOString() };
  state.outbox[key] = true;
  emit();
  scheduleFlush();
}

export function pendingCount() {
  return Object.keys(state.outbox).length;
}

export function setDevice(name) {
  state.device = name.trim() || defaultDevice();
  emit();
}

export function configure(url, key) {
  const clean = url.trim().replace(/\/+$/, "");
  state.config = { url: clean, key: key.trim() };
  state.problem = null;
  emit();
}

export function clearConfig() {
  state.config = null;
  emit();
}

export function signedIn() {
  return !!(state.config && state.session);
}

async function call(path, options = {}, retry = true) {
  const { url, key } = state.config;
  const headers = { apikey: key, "Content-Type": "application/json", ...(options.headers || {}) };
  if (state.session && !options.anonymous) headers.Authorization = "Bearer " + state.session.access_token;
  if (!state.session || options.anonymous) headers.Authorization = headers.Authorization || "Bearer " + key;
  const res = await fetch(url + path, { ...options, headers });
  if (res.status === 401 && retry && state.session && !options.anonymous) {
    await refresh();
    return call(path, options, false);
  }
  if (!res.ok) {
    let message = res.status + " " + res.statusText;
    try {
      const body = await res.json();
      message = body.msg || body.message || body.error_description || body.error || message;
    } catch (e) {}
    const err = new Error(message);
    err.status = res.status;
    throw err;
  }
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

function adopt(session) {
  state.session = {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: Date.now() + (session.expires_in || 3600) * 1000,
    user: { id: session.user.id, email: session.user.email },
  };
}

export async function sendCode(email) {
  await call("/auth/v1/otp", { method: "POST", anonymous: true, body: JSON.stringify({ email: email.trim(), create_user: true }) });
}

export async function verifyCode(email, code) {
  const session = await call("/auth/v1/verify", {
    method: "POST",
    anonymous: true,
    body: JSON.stringify({ type: "email", email: email.trim(), token: code.trim() }),
  });
  adopt(session);
  state.cursor = "1970-01-01T00:00:00Z";
  state.problem = null;
  emit();
  await syncNow();
  startPolling();
}

async function refresh() {
  const session = await call("/auth/v1/token?grant_type=refresh_token", {
    method: "POST",
    anonymous: true,
    body: JSON.stringify({ refresh_token: state.session.refresh_token }),
  });
  adopt(session);
  persist();
}

export async function signOut() {
  try {
    if (state.session) await call("/auth/v1/logout", { method: "POST" }, false);
  } catch (e) {}
  const config = state.config;
  const device = state.device;
  state = blank();
  state.config = config;
  state.device = device;
  emit();
}

function scheduleFlush() {
  clearTimeout(flushTimer);
  flushTimer = setTimeout(() => syncNow(), 400);
}

async function flush() {
  const keys = Object.keys(state.outbox);
  if (!keys.length) return;
  const rows = keys.map((key) => {
    const r = state.records[key];
    return { user_id: state.session.user.id, kind: r.kind, id: r.id, data: r.data, deleted: r.deleted, device: state.device };
  });
  for (let i = 0; i < rows.length; i += 500) {
    await call("/rest/v1/records?on_conflict=user_id,kind,id", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(rows.slice(i, i + 500)),
    });
  }
  const sent = new Set(keys);
  for (const key of sent) {
    if (state.outbox[key]) delete state.outbox[key];
  }
}

async function pull() {
  const overlap = new Date(new Date(state.cursor).getTime() - 120000).toISOString();
  let offset = 0;
  let newest = state.cursor;
  let changed = false;
  for (;;) {
    const rows = await call(
      "/rest/v1/records?select=kind,id,data,deleted,updated_at&updated_at=gt." +
        encodeURIComponent(overlap) +
        "&order=updated_at.asc&limit=1000&offset=" +
        offset
    );
    for (const r of rows) {
      const key = r.kind + "|" + r.id;
      if (r.updated_at > newest) newest = r.updated_at;
      if (state.outbox[key]) continue;
      const mine = state.records[key];
      if (mine && mine.deleted === r.deleted && JSON.stringify(mine.data) === JSON.stringify(r.data)) continue;
      state.records[key] = { kind: r.kind, id: r.id, data: r.data, deleted: r.deleted, updated_at: r.updated_at };
      changed = true;
    }
    if (rows.length < 1000) break;
    offset += rows.length;
  }
  state.cursor = newest;
  return changed;
}

export async function syncNow() {
  if (!signedIn() || pulling || flushing) return;
  if (!navigator.onLine) {
    state.problem = "Offline. Changes are kept on this device.";
    emit();
    return;
  }
  flushing = true;
  pulling = true;
  try {
    await flush();
    await pull();
    state.lastSync = new Date().toISOString();
    state.problem = null;
  } catch (e) {
    state.problem = e.status === 400 && /refresh/i.test(e.message) ? "Signed out. Sign in again to keep syncing." : e.message || "Sync failed";
    if (e.status === 400 && /refresh/i.test(e.message)) state.session = null;
  } finally {
    flushing = false;
    pulling = false;
    emit();
  }
}

export function startPolling() {
  clearInterval(pollTimer);
  pollTimer = setInterval(() => {
    if (document.visibilityState === "visible") syncNow();
  }, 4000);
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") syncNow();
});
window.addEventListener("online", () => syncNow());

export const time = {
  fromBoard(seconds) {
    return new Date((seconds + EPOCH_2001) * 1000);
  },
  toBoard(date) {
    return date.getTime() / 1000 - EPOCH_2001;
  },
};

export function uuid() {
  return crypto.randomUUID().toUpperCase();
}

export async function stableUuid(text) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))).slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return (hex.slice(0, 8) + "-" + hex.slice(8, 12) + "-" + hex.slice(12, 16) + "-" + hex.slice(16, 20) + "-" + hex.slice(20)).toUpperCase();
}

export function exportDocuments() {
  const byPos = (a, b) => (a._pos ?? 0) - (b._pos ?? 0);
  const strip = (o) => {
    const { _pos, ...rest } = o;
    return rest;
  };
  const settings = get("schedule.settings", "book") || {};
  return {
    board: {
      projects: all("board.project").sort(byPos).map(strip),
      sessions: all("board.session").sort((a, b) => a.ended - b.ended).map(strip),
    },
    todos: all("todo").sort(byPos).map(strip),
    schedule: {
      ...strip(settings),
      routines: all("schedule.routine").sort(byPos).map(strip),
      checks: all("schedule.check").map(strip),
    },
    calendar: { events: all("calendar.event").sort(byPos).map(strip) },
  };
}

if (signedIn()) startPolling();
