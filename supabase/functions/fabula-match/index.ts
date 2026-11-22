import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-pocket-source",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const MAX_MEMBERS = 8;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function code() {
  const abc = "abcdefghjkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return Array.from(bytes, (b) => abc[b % abc.length]).join("");
}

function cleanName(raw: unknown) {
  const s = String(raw ?? "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, 20);
  return s;
}

async function hostKeyValid(key: string | null) {
  if (!key) return false;
  const res = await fetch(`${URL_}/rest/v1/movies?select=tmdb&limit=1`, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
  return res.ok;
}

async function room(c: string) {
  if (typeof c !== "string" || !/^[a-z0-9]{8,20}$/.test(c)) return null;
  const { data } = await db.from("match_room").select("*").eq("code", c).maybeSingle();
  return data;
}

async function member(roomId: string, id: unknown) {
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/.test(id)) return null;
  const { data } = await db.from("match_member").select("*").eq("room", roomId).eq("id", id).maybeSingle();
  return data;
}

async function movies(ids: number[]) {
  if (!ids.length) return [];
  const { data } = await db.from("movies").select("tmdb,title,year,runtime,language,genres,director,cast,overview,poster,backdrop,vote,providers,kind,seasons,episodes,format,imdb_rating,imdb_votes,mal_score").in("tmdb", ids);
  const byId = new Map((data || []).map(({ imdb_rating, imdb_votes, mal_score, ...m }: any) => [m.tmdb, {
    ...m, cast: (m.cast || []).slice(0, 3),
    imdb: (imdb_votes ?? 0) >= (m.kind === "show" ? 500 : 1000) ? imdb_rating : null,
    mal: m.kind === "anime" ? mal_score : null,
  }]));
  return ids.map((id) => byId.get(id)).filter(Boolean);
}

async function state(r: any, me: any) {
  const { data: members } = await db.from("match_member").select("id,name,is_host,joined_at").eq("room", r.id).order("joined_at");
  const { data: swipes } = await db.from("match_swipe").select("member,tmdb,yes").eq("room", r.id);
  const done = new Map<string, number>();
  for (const s of swipes || []) done.set(s.member, (done.get(s.member) || 0) + 1);
  const mine = new Set((swipes || []).filter((s: any) => s.member === me.id).map((s: any) => s.tmdb));
  const deck = await movies(r.deck);
  const matched = r.matched ? (await movies([r.matched]))[0] ?? null : null;
  return {
    code: r.code,
    me: { id: me.id, name: me.name, host: me.is_host },
    started: !!r.started_at,
    members: (members || []).map((m: any) => ({ name: m.name, host: m.is_host, swiped: done.get(m.id) || 0, me: m.id === me.id })),
    deck,
    swiped: [...mine],
    matched,
    total: r.deck.length,
  };
}

async function checkMatch(r: any) {
  const { count } = await db.from("match_member").select("id", { count: "exact", head: true }).eq("room", r.id);
  const { data: yes } = await db.from("match_swipe").select("tmdb").eq("room", r.id).eq("yes", true);
  const tally = new Map<number, number>();
  for (const y of yes || []) tally.set(y.tmdb, (tally.get(y.tmdb) || 0) + 1);
  const winner = r.deck.find((id: number) => (tally.get(id) || 0) >= (count || 0) && (count || 0) >= 2);
  if (winner) {
    await db.from("match_room").update({ matched: winner, matched_at: new Date().toISOString() }).eq("id", r.id).is("matched", null);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Body must be JSON" }, 400); }
  try {
    switch (body?.action) {
      case "create": {
        if (!(await hostKeyValid(req.headers.get("apikey")))) return json({ error: "Only the Fabula owner can start a room" }, 403);
        const name = cleanName(body.name) || "Host";
        const langs = Array.isArray(body.langs) ? body.langs.map(String).slice(0, 12) : null;
        const genres = Array.isArray(body.genres) ? body.genres.map(String).slice(0, 14) : null;
        const kind = ["show", "anime"].includes(body.kind) ? body.kind : "movie";
        const who = ["pranav", "momo"].includes(body.who) ? body.who : "pranav";
        const { data: deck, error } = await db.rpc("fabula_deck", { p_who: who, p_kind: kind, p_langs: langs, p_genres: genres, p_limit: 40, p_exclude: [] });
        if (error) return json({ error: error.message }, 502);
        const ids = (deck || []).map((m: any) => m.tmdb);
        if (!ids.length) return json({ error: "Nothing matches those filters" }, 400);
        const { data: r, error: e2 } = await db.from("match_room").insert({ code: code(), deck: ids }).select().single();
        if (e2) return json({ error: e2.message }, 502);
        const { data: me } = await db.from("match_member").insert({ room: r.id, name, is_host: true }).select().single();
        return json(await state(r, me));
      }
      case "join": {
        const r = await room(body.code);
        if (!r) return json({ error: "This link has expired" }, 404);
        if (r.started_at) return json({ error: "This movie night has already started" }, 409);
        const base = cleanName(body.name);
        if (!base) return json({ error: "Name is required" }, 400);
        const { data: members } = await db.from("match_member").select("name").eq("room", r.id);
        if ((members || []).length >= MAX_MEMBERS) return json({ error: "This room is full" }, 409);
        const taken = new Set((members || []).map((m: any) => m.name.toLowerCase()));
        let name = base;
        for (let n = 2; taken.has(name.toLowerCase()); n++) name = `${base} ${n}`;
        const { data: me } = await db.from("match_member").insert({ room: r.id, name }).select().single();
        return json(await state(r, me));
      }
      case "state": {
        const r = await room(body.code);
        if (!r) return json({ error: "This link has expired" }, 404);
        const me = await member(r.id, body.member);
        if (!me) return json({ error: "Join first" }, 403);
        return json(await state(r, me));
      }
      case "start": {
        const r = await room(body.code);
        if (!r) return json({ error: "This link has expired" }, 404);
        const me = await member(r.id, body.member);
        if (!me || !me.is_host) return json({ error: "Only the host can start" }, 403);
        if (!r.started_at) await db.from("match_room").update({ started_at: new Date().toISOString() }).eq("id", r.id);
        return json(await state({ ...r, started_at: r.started_at || new Date().toISOString() }, me));
      }
      case "swipe": {
        const r = await room(body.code);
        if (!r) return json({ error: "This link has expired" }, 404);
        const me = await member(r.id, body.member);
        if (!me) return json({ error: "Join first" }, 403);
        if (!r.started_at) return json({ error: "Not started yet" }, 409);
        const tmdb = Number(body.tmdb);
        if (!r.deck.includes(tmdb)) return json({ error: "Not in this room's films" }, 400);
        await db.from("match_swipe").upsert({ room: r.id, member: me.id, tmdb, yes: !!body.yes }, { onConflict: "member,tmdb" });
        if (body.yes && !r.matched) await checkMatch(r);
        const fresh = await room(body.code);
        return json(await state(fresh, me));
      }
      case "leave": {
        const r = await room(body.code);
        if (!r) return json({ ok: true });
        const me = await member(r.id, body.member);
        if (me?.is_host) await db.from("match_room").delete().eq("id", r.id);
        else if (me) await db.from("match_member").delete().eq("id", me.id);
        return json({ ok: true });
      }
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 500);
  }
});
