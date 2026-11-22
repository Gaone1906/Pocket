import { createClient } from "jsr:@supabase/supabase-js@2";

const MAL = "https://api.myanimelist.net/v2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-pocket-source",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const ANIME = 200_000_000;
const FIELDS = [
  "alternative_titles", "start_date", "end_date", "synopsis", "mean", "num_list_users", "num_scoring_users", "nsfw",
  "genres", "media_type", "status", "num_episodes", "start_season", "average_episode_duration", "rating", "studios",
  "main_picture", "popularity",
].join(",");
const GENRES: Record<string, string> = {
  "Action": "Action", "Adventure": "Adventure", "Avant Garde": "Avant Garde", "Award Winning": "Award Winning",
  "Boys Love": "Boys Love", "Comedy": "Comedy", "Drama": "Drama", "Fantasy": "Fantasy", "Girls Love": "Girls Love",
  "Gourmet": "Gourmet", "Horror": "Horror", "Mystery": "Mystery", "Romance": "Romance", "Sci-Fi": "Sci-fi",
  "Slice of Life": "Slice of Life", "Sports": "Sports", "Supernatural": "Supernatural", "Suspense": "Thriller",
};
const BLOCKED = new Set(["Hentai", "Erotica"]);
const FORMATS: Record<string, string> = { tv: "TV", movie: "Movie", ova: "OVA", ona: "ONA", special: "Special", tv_special: "Special" };
const STATUS: Record<string, string> = { finished_airing: "Ended", currently_airing: "Running", not_yet_aired: "Upcoming" };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

async function mal(path: string, params: Record<string, string | number> = {}) {
  const url = new URL(MAL + path);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(url, { headers: { "X-MAL-CLIENT-ID": Deno.env.get("MAL_CLIENT_ID")!, Accept: "application/json" } });
    if (res.status === 429 || res.status >= 500) { await new Promise((r) => setTimeout(r, 1500 * (attempt + 1))); continue; }
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`mal ${res.status} ${path}`);
    return await res.json();
  }
  throw new Error(`mal unavailable ${path}`);
}

function date(d?: string) {
  if (!d) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(d)) return d;
  if (/^\d{4}-\d{2}$/.test(d)) return d + "-01";
  if (/^\d{4}$/.test(d)) return d + "-01-01";
  return null;
}

function synopsis(s?: string) {
  if (!s) return null;
  return s.replace(/\s*\[Written by MAL Rewrite\]\s*$/i, "").replace(/\s*\(Source:[^)]*\)\s*$/i, "").trim() || null;
}

function allowed(a: any) {
  if (!a || !FORMATS[a.media_type]) return false;
  if (a.nsfw === "black" || a.rating === "rx") return false;
  return !(a.genres || []).some((g: any) => BLOCKED.has(g.name));
}

function shape(a: any) {
  const names: string[] = (a.genres || []).map((g: any) => g.name);
  const y = a.start_season?.year ?? (a.start_date ? Number(a.start_date.slice(0, 4)) : null);
  const season = a.start_season ? `${a.start_season.season[0].toUpperCase()}${a.start_season.season.slice(1)} ${a.start_season.year}` : null;
  const en = a.alternative_titles?.en?.trim();
  return {
    tmdb: ANIME + a.id,
    kind: "anime",
    title: en || a.title,
    original_title: a.title,
    year: y,
    released: date(a.start_date),
    runtime: a.average_episode_duration ? Math.max(1, Math.round(a.average_episode_duration / 60)) : null,
    lang: "ja",
    language: "Japanese",
    genres: [...new Set(names.filter((n) => GENRES[n]).map((n) => GENRES[n]))],
    keywords: names.filter((n) => !GENRES[n]).slice(0, 25),
    director: (a.studios || [])[0]?.name ?? null,
    cast: [],
    overview: synopsis(a.synopsis),
    poster: a.main_picture?.large || a.main_picture?.medium || null,
    backdrop: null,
    vote: a.mean ?? null,
    votes: a.num_list_users ?? null,
    popularity: a.num_list_users ?? null,
    providers: [],
    recs: [],
    episodes: a.num_episodes || null,
    format: FORMATS[a.media_type],
    season,
    status: STATUS[a.status] || null,
    ended: a.end_date && a.status === "finished_airing" ? Number(a.end_date.slice(0, 4)) : null,
    mal_score: a.mean ?? null,
    mal_members: a.num_list_users ?? null,
    mal_scorers: a.num_scoring_users ?? null,
    updated: new Date().toISOString(),
  };
}

async function save(rows: any[]) {
  if (!rows.length) return;
  const { error } = await db.from("movies").upsert(rows, { onConflict: "tmdb" });
  if (error) throw new Error(error.message);
}

async function admin(key: string) {
  const { data } = await db.from("fabula_admin").select("value").eq("key", key).maybeSingle();
  return data?.value;
}

async function authorised(token: unknown) {
  const real = await admin("ingest_token");
  return typeof token === "string" && token.length > 0 && token === real;
}

async function ingest(maxOffset: number, floor: number) {
  const start = Date.now();
  let cursor = (await admin("anime_cursor")) || { offset: 0 };
  let added = 0;
  let done = false;
  while (Date.now() - start < 110_000 && !done) {
    const res = await mal("/anime/ranking", { ranking_type: "bypopularity", limit: 500, offset: cursor.offset, fields: FIELDS, nsfw: "true" });
    const list: any[] = (res?.data || []).map((d: any) => d.node);
    const rows = list.filter(allowed).map(shape).filter((r) => r.year && r.year >= 1990 && r.year <= 2026);
    await save(rows);
    added += rows.length;
    const last = list[list.length - 1];
    cursor = { offset: cursor.offset + 500 };
    done = !list.length || !res?.paging?.next || cursor.offset >= maxOffset || (last?.num_list_users ?? 0) < floor;
    await db.from("fabula_admin").upsert({ key: "anime_cursor", value: { ...cursor, done }, updated: new Date().toISOString() });
  }
  const { count } = await db.from("movies").select("tmdb", { count: "exact", head: true }).eq("kind", "anime");
  return { added, cursor, done, anime: count };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Body must be JSON" }, 400); }
  try {
    switch (body?.action) {
      case "search": {
        const q = String(body.q || "").trim();
        if (q.length < 3 || q.length > 64) return json({ error: "q must be 3-64 characters" }, 400);
        const res = await mal("/anime", { q, limit: 20, fields: FIELDS, nsfw: "true" });
        const results = (res?.data || []).map((d: any) => d.node).filter(allowed).slice(0, 12).map((a: any) => {
          const s = shape(a);
          return { tmdb: s.tmdb, kind: "anime", title: s.title, original_title: s.original_title, year: s.year, language: s.language, poster: s.poster, votes: s.mal_members, format: s.format };
        });
        return json({ results });
      }
      case "add": {
        const id = Number(body.tmdb);
        if (!Number.isInteger(id) || id <= ANIME || id >= ANIME + 100_000_000) return json({ error: "tmdb must be an anime id" }, 400);
        const { data: have } = await db.from("movies").select("*").eq("tmdb", id).maybeSingle();
        if (have && !body.refresh) return json({ movie: have });
        const a = await mal(`/anime/${id - ANIME}`, { fields: FIELDS, nsfw: "true" });
        if (!a || !allowed(a)) return json({ error: "Not found on MyAnimeList" }, 404);
        const row = shape(a);
        await save([row]);
        return json({ movie: row });
      }
      case "ingest": {
        if (!(await authorised(body.token))) return json({ error: "Not allowed" }, 403);
        const maxOffset = Math.min(Number(body.max) || 15000, 30000);
        const floor = Math.max(Number(body.floor) || 1000, 0);
        return json(await ingest(maxOffset, floor));
      }
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 502);
  }
});
