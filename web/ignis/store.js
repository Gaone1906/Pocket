const KEY = "aurelius.cloud.v1";
const OTHER_KEYS = ["pomodoro.cloud.v1", "pocket.cloud.v1", "orario.cloud.v1"];
const EPOCH_2001 = 978307200;
const SHARED = "00000000-0000-0000-0000-000000000000";

const listeners = new Set();
let state = load();
let pulling = false;
let flushing = false;
let flushTimer = null;
let pollTimer = null;

function blank() {
  return {
    config: null,
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
    if (raw) {
      const saved = { ...blank(), ...JSON.parse(raw) };
      if (saved.config) saved.config = cleanConfig(saved.config.url, saved.config.key);
      return saved;
    }
    for (const k of OTHER_KEYS) {
      const other = JSON.parse(localStorage.getItem(k) || "null");
      if (other && other.config && other.config.url && other.config.key) {
        const seeded = blank();
        seeded.config = cleanConfig(other.config.url, other.config.key);
        if (other.device) seeded.device = other.device;
        return seeded;
      }
    }
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

function cleanConfig(url, key) {
  return {
    url: String(url || "").replace(/[^\x21-\x7e]/g, "").replace(/\/+$/, ""),
    key: String(key || "").replace(/[^A-Za-z0-9._-]/g, ""),
  };
}

export function configure(url, key) {
  state.config = cleanConfig(url, key);
  state.cursor = "1970-01-01T00:00:00Z";
  state.problem = null;
  emit();
  syncNow();
  startPolling();
}

export function signedIn() {
  return !!state.config;
}

async function call(path, options = {}) {
  const { url, key } = state.config;
  const headers = { apikey: key, "Content-Type": "application/json", ...(options.headers || {}) };
  if (!key.startsWith("sb_")) headers.Authorization = "Bearer " + key;
  let res;
  try {
    res = await fetch(url + path, { ...options, headers });
  } catch (e) {
    throw new Error(navigator.onLine ? "Can't reach the database. Check the setup link, or Disconnect and paste it again." : "Offline. Changes are kept on this device.");
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

export function disconnect() {
  const device = state.device;
  clearInterval(pollTimer);
  state = blank();
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
    return { user_id: SHARED, kind: r.kind, id: r.id, data: r.data, deleted: r.deleted, device: state.device };
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
  const before = { problem: state.problem, pending: pendingCount(), minute: (state.lastSync || "").slice(0, 16) };
  let changed = false;
  try {
    await flush();
    changed = await pull();
    state.lastSync = new Date().toISOString();
    state.problem = null;
  } catch (e) {
    state.problem = e.message || "Sync failed";
  } finally {
    flushing = false;
    pulling = false;
    const quiet = !changed && before.problem === state.problem && before.pending === pendingCount() && before.minute === (state.lastSync || "").slice(0, 16);
    if (quiet) persist();
    else emit();
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

if (signedIn()) startPolling();
