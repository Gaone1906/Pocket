import { createServer } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import { extname, join, normalize } from "node:path";
import { randomUUID } from "node:crypto";

const port = Number(process.env.PORT || 8790);
const root = new URL("..", import.meta.url).pathname;
const dbFile = process.env.POCKET_DEV_DB || "";
const db = dbFile && existsSync(dbFile) ? JSON.parse(readFileSync(dbFile, "utf8")) : { users: {}, records: [], tokens: {}, refresh: {} };
const types = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json", ".json": "application/json" };
let clock = 0;

function stamp() {
  clock = Math.max(clock + 1, Date.now() * 1000);
  const ms = Math.floor(clock / 1000);
  const micro = String(clock % 1000).padStart(3, "0");
  return new Date(ms).toISOString().replace("Z", micro + "+00:00");
}

async function save() {
  if (dbFile) await writeFile(dbFile, JSON.stringify(db));
}

function send(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "*",
    "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
  });
  res.end(body === undefined ? "" : JSON.stringify(body));
}

function session(userId) {
  const access = "at-" + randomUUID();
  const refresh = "rt-" + randomUUID();
  db.tokens[access] = userId;
  db.refresh[refresh] = userId;
  return { access_token: access, refresh_token: refresh, expires_in: 3600, token_type: "bearer", user: { id: userId, email: db.users[userId] } };
}

function body(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        resolve(null);
      }
    });
  });
}

function caller(req) {
  const auth = req.headers.authorization || "";
  return db.tokens[auth.replace(/^Bearer /, "")];
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (req.method === "OPTIONS") return send(res, 204);
  const path = url.pathname;

  if (path === "/auth/v1/otp" && req.method === "POST") {
    const { email } = (await body(req)) || {};
    if (!email) return send(res, 400, { msg: "email required" });
    console.log(`otp email=${email} code=123456`);
    return send(res, 200, {});
  }
  if (path === "/auth/v1/verify" && req.method === "POST") {
    const { email, token } = (await body(req)) || {};
    if (token !== "123456") return send(res, 403, { msg: "Token has expired or is invalid" });
    let id = Object.keys(db.users).find((k) => db.users[k] === email);
    if (!id) {
      id = randomUUID();
      db.users[id] = email;
    }
    const s = session(id);
    await save();
    return send(res, 200, s);
  }
  if (path === "/auth/v1/token" && url.searchParams.get("grant_type") === "refresh_token") {
    const { refresh_token } = (await body(req)) || {};
    const id = db.refresh[refresh_token];
    if (!id) return send(res, 400, { error: "invalid_grant", error_description: "Invalid Refresh Token: Refresh Token Not Found" });
    delete db.refresh[refresh_token];
    const s = session(id);
    await save();
    return send(res, 200, s);
  }
  if (path === "/auth/v1/logout") return send(res, 204);

  if (path === "/rest/v1/records") {
    const user = caller(req);
    if (!user) return send(res, 401, { message: "JWT expired" });
    if (req.method === "GET") {
      const gt = (url.searchParams.get("updated_at") || "gt.1970-01-01T00:00:00Z").slice(3);
      const limit = Number(url.searchParams.get("limit") || 1000);
      const offset = Number(url.searchParams.get("offset") || 0);
      const since = new Date(gt).getTime();
      const rows = db.records
        .filter((r) => r.user_id === user && (new Date(r.updated_at).getTime() > since || (new Date(r.updated_at).getTime() === since && r.updated_at > gt)))
        .sort((a, b) => (a.updated_at < b.updated_at ? -1 : 1))
        .slice(offset, offset + limit)
        .map(({ kind, id, data, deleted, updated_at }) => ({ kind, id, data, deleted, updated_at }));
      return send(res, 200, rows);
    }
    if (req.method === "POST") {
      const rows = await body(req);
      if (!Array.isArray(rows) && (rows === null || typeof rows !== "object")) return send(res, 400, { message: "bad body" });
      for (const r of Array.isArray(rows) ? rows : [rows]) {
        if ((r.user_id || user) !== user) return send(res, 403, { message: "new row violates row-level security policy" });
        const existing = db.records.find((x) => x.user_id === user && x.kind === r.kind && x.id === r.id);
        const next = { user_id: user, kind: r.kind, id: r.id, data: r.data ?? {}, deleted: !!r.deleted, device: r.device ?? null, updated_at: stamp() };
        if (existing) Object.assign(existing, next);
        else db.records.push(next);
      }
      await save();
      return send(res, 201);
    }
  }

  if (req.method === "GET" && !path.startsWith("/auth") && !path.startsWith("/rest")) {
    const file = normalize(join(root, path === "/" ? "index.html" : path));
    if (!file.startsWith(root) || file.includes("/dev/")) return send(res, 404, { error: "not found" });
    try {
      const data = await readFile(file);
      res.writeHead(200, { "Content-Type": types[extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
      return res.end(data);
    } catch (e) {
      return send(res, 404, { error: "not found" });
    }
  }
  send(res, 404, { error: "no route" });
});

server.listen(port, "127.0.0.1", () => console.log(`pocket dev backend http://127.0.0.1:${port} code=123456`));
