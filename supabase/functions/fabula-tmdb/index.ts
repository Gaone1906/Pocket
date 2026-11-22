import { createClient } from "jsr:@supabase/supabase-js@2";

const TMDB = "https://api.themoviedb.org/3";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const USER = "00000000-0000-0000-0000-000000000000";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-pocket-source",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const LANGS: Record<string, string> = {
  en: "English", hi: "Hindi", te: "Telugu", ta: "Tamil", ml: "Malayalam", kn: "Kannada", bn: "Bengali", mr: "Marathi",
  ko: "Korean", ja: "Japanese", zh: "Mandarin", cn: "Cantonese", es: "Spanish", fr: "French", de: "German", it: "Italian",
  pt: "Portuguese", ru: "Russian", sv: "Swedish", da: "Danish", no: "Norwegian", fa: "Persian", tr: "Turkish", th: "Thai",
  id: "Indonesian", pl: "Polish", nl: "Dutch", ar: "Arabic", he: "Hebrew",
};
const GENRE: Record<string, string> = { "Science Fiction": "Sci-fi" };
const TV_GENRE: Record<string, string[]> = {
  "Action & Adventure": ["Action", "Adventure"], "Sci-Fi & Fantasy": ["Sci-fi", "Fantasy"], "War & Politics": ["War"],
  "Kids": ["Family"],
};
const SHOW = 100_000_000;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

async function tmdb(path: string, params: Record<string, string | number> = {}) {
  const url = new URL(TMDB + path);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${Deno.env.get("TMDB_TOKEN")}`, Accept: "application/json" } });
    if (res.status === 429) { await new Promise((r) => setTimeout(r, 1000 * (attempt + 1))); continue; }
    if (!res.ok) throw new Error(`tmdb ${res.status} ${path}`);
    return await res.json();
  }
  throw new Error(`tmdb rate limited ${path}`);
}

function year(d?: string) {
  return d && d.length >= 4 ? Number(d.slice(0, 4)) : null;
}

function shape(d: any) {
  const lang = d.original_language as string;
  const spoken = (d.spoken_languages || []).find((s: any) => s.iso_639_1 === lang);
  const director = (d.credits?.crew || []).find((c: any) => c.job === "Director")?.name ?? null;
  const india = d["watch/providers"]?.results?.IN;
  return {
    tmdb: d.id,
    title: d.title,
    original_title: d.original_title,
    year: year(d.release_date),
    released: d.release_date || null,
    runtime: d.runtime || null,
    lang,
    language: LANGS[lang] || spoken?.english_name || lang,
    genres: (d.genres || []).map((g: any) => GENRE[g.name] || g.name),
    keywords: (d.keywords?.keywords || []).slice(0, 25).map((k: any) => k.name),
    director,
    cast: (d.credits?.cast || []).slice(0, 6).map((c: any) => c.name),
    overview: d.overview || null,
    poster: d.poster_path || null,
    backdrop: d.backdrop_path || null,
    imdb_id: d.imdb_id || null,
    vote: d.vote_average ?? null,
    votes: d.vote_count ?? null,
    popularity: d.popularity ?? null,
    collection: d.belongs_to_collection?.id ?? null,
    providers: (india?.flatrate || []).map((p: any) => p.provider_name),
    recs: (d.recommendations?.results || []).slice(0, 20).map((r: any) => r.id),
    updated: new Date().toISOString(),
  };
}

function shapeTv(d: any) {
  const lang = d.original_language as string;
  const india = d["watch/providers"]?.results?.IN;
  const ended = ["Ended", "Canceled"].includes(d.status) ? year(d.last_air_date) : null;
  const run = (d.episode_run_time || [])[0] || d.last_episode_to_air?.runtime || null;
  return {
    tmdb: SHOW + d.id,
    kind: "show",
    title: d.name,
    original_title: d.original_name,
    year: year(d.first_air_date),
    released: d.first_air_date || null,
    runtime: run,
    lang,
    language: LANGS[lang] || lang,
    genres: [...new Set((d.genres || []).flatMap((g: any) => TV_GENRE[g.name] || [GENRE[g.name] || g.name]))],
    keywords: (d.keywords?.results || []).slice(0, 25).map((k: any) => k.name),
    director: (d.created_by || [])[0]?.name ?? null,
    cast: (d.aggregate_credits?.cast || d.credits?.cast || []).slice(0, 6).map((c: any) => c.name),
    overview: d.overview || null,
    poster: d.poster_path || null,
    backdrop: d.backdrop_path || null,
    imdb_id: d.external_ids?.imdb_id || null,
    vote: d.vote_average ?? null,
    votes: d.vote_count ?? null,
    popularity: d.popularity ?? null,
    providers: (india?.flatrate || []).map((p: any) => p.provider_name),
    recs: (d.recommendations?.results || []).slice(0, 20).map((r: any) => SHOW + r.id),
    seasons: d.number_of_seasons ?? null,
    episodes: d.number_of_episodes ?? null,
    network: (d.networks || [])[0]?.name ?? null,
    status: d.status || null,
    ended,
    updated: new Date().toISOString(),
  };
}

async function tvDetails(id: number) {
  const d = await tmdb(`/tv/${id}`, { append_to_response: "aggregate_credits,keywords,recommendations,watch/providers,external_ids", language: "en-US" });
  return shapeTv(d);
}

async function addShows(ids: number[]) {
  const out: any[] = [];
  for (let i = 0; i < ids.length; i += 10) {
    const batch = await Promise.all(ids.slice(i, i + 10).map((id) => tvDetails(id).catch(() => null)));
    out.push(...batch.filter(Boolean));
  }
  if (out.length) {
    const { error } = await db.from("movies").upsert(out, { onConflict: "tmdb" });
    if (error) throw new Error(error.message);
  }
  return out;
}

function showPlans() {
  const list: { y: number; lang: string; min: number }[] = [];
  for (let y = 1990; y <= 2026; y++) {
    list.push({ y, lang: "en", min: y >= 2025 ? 10 : 25 });
    list.push({ y, lang: "ko", min: y >= 2025 ? 5 : 10 });
    list.push({ y, lang: "hi", min: y >= 2025 ? 2 : 4 });
  }
  return list;
}

async function ingestShows() {
  const start = Date.now();
  const all = showPlans();
  let cursor = (await admin("shows_cursor")) || { plan: 0, page: 1 };
  let added = 0;
  while (Date.now() - start < 110_000 && cursor.plan < all.length) {
    const p = all[cursor.plan];
    const res = await tmdb("/discover/tv", {
      first_air_date_year: p.y, with_original_language: p.lang, "vote_count.gte": p.min, sort_by: "vote_count.desc",
      include_adult: "false", without_genres: "10763,10764,10767", page: cursor.page,
    });
    const ids: number[] = (res.results || []).map((r: any) => r.id);
    if (ids.length) {
      const { data: have } = await db.from("movies").select("tmdb").in("tmdb", ids.map((id) => SHOW + id));
      const known = new Set((have || []).map((h: any) => h.tmdb - SHOW));
      added += (await addShows(ids.filter((id) => !known.has(id)))).length;
    }
    const last = Math.min(res.total_pages || 1, 40);
    cursor = cursor.page >= last ? { plan: cursor.plan + 1, page: 1 } : { plan: cursor.plan, page: cursor.page + 1 };
    await db.from("fabula_admin").upsert({ key: "shows_cursor", value: cursor, updated: new Date().toISOString() });
  }
  const { count } = await db.from("movies").select("tmdb", { count: "exact", head: true }).eq("kind", "show");
  return { added, cursor, plans: all.length, done: cursor.plan >= all.length, shows: count };
}

async function imdbFill(kind: string, only: boolean) {
  const ids = new Map<string, number[]>();
  for (let from = 0; ; from += 1000) {
    let q = db.from("movies").select("tmdb, imdb_id").eq("kind", kind).not("imdb_id", "is", null).range(from, from + 999);
    if (only) q = q.is("imdb_rating", null);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    for (const r of data || []) ids.set(r.imdb_id, [...(ids.get(r.imdb_id) || []), r.tmdb]);
    if (!data || data.length < 1000) break;
  }
  const res = await fetch("https://datasets.imdbws.com/title.ratings.tsv.gz");
  if (!res.ok || !res.body) throw new Error(`imdb ${res.status}`);
  const lines = res.body.pipeThrough(new DecompressionStream("gzip")).pipeThrough(new TextDecoderStream());
  const rows: { tmdb: number; rating: number; votes: number }[] = [];
  let rest = "";
  for await (const chunk of lines) {
    const parts = (rest + chunk).split("\n");
    rest = parts.pop() || "";
    for (const line of parts) {
      const tab = line.indexOf("\t");
      const hit = ids.get(line.slice(0, tab));
      if (!hit) continue;
      const [, r, v] = line.split("\t");
      for (const tmdb of hit) rows.push({ tmdb, rating: Number(r), votes: Number(v) });
    }
  }
  for (let i = 0; i < rows.length; i += 1000) {
    const { error } = await db.rpc("fabula_set_imdb", { p_rows: rows.slice(i, i + 1000) });
    if (error) throw new Error(error.message);
  }
  return { asked: ids.size, rated: rows.length };
}

async function details(id: number) {
  const d = await tmdb(`/movie/${id}`, { append_to_response: "credits,keywords,recommendations,watch/providers", language: "en-US" });
  return shape(d);
}

async function addMovies(ids: number[]) {
  const out: any[] = [];
  for (let i = 0; i < ids.length; i += 10) {
    const batch = await Promise.all(ids.slice(i, i + 10).map((id) => details(id).catch(() => null)));
    out.push(...batch.filter(Boolean));
  }
  if (out.length) {
    const { error } = await db.from("movies").upsert(out, { onConflict: "tmdb" });
    if (error) throw new Error(error.message);
  }
  return out;
}

function plans() {
  const list: { y: number; lang: string | null; min: number }[] = [];
  for (let y = 1990; y <= 2026; y++) {
    const min = y >= 2026 ? 15 : y >= 2025 ? 40 : y >= 2024 ? 90 : 200;
    list.push({ y, lang: null, min });
    for (const lang of ["hi", "te", "ta", "ml", "kn"]) list.push({ y, lang, min: y >= 2025 ? 5 : 20 });
  }
  return list;
}

async function admin(key: string) {
  const { data } = await db.from("fabula_admin").select("value").eq("key", key).maybeSingle();
  return data?.value;
}

async function authorised(token: unknown) {
  const real = await admin("ingest_token");
  return typeof token === "string" && token.length > 0 && token === real;
}

async function ingest() {
  const start = Date.now();
  const all = plans();
  let cursor = (await admin("ingest_cursor")) || { plan: 0, page: 1 };
  let added = 0;
  while (Date.now() - start < 110_000 && cursor.plan < all.length) {
    const p = all[cursor.plan];
    const params: Record<string, string | number> = {
      primary_release_year: p.y, "vote_count.gte": p.min, sort_by: "vote_count.desc", include_adult: "false",
      without_genres: "99", page: cursor.page,
    };
    if (p.lang) params.with_original_language = p.lang;
    const res = await tmdb("/discover/movie", params);
    const ids: number[] = (res.results || []).map((r: any) => r.id);
    if (ids.length) {
      const { data: have } = await db.from("movies").select("tmdb").in("tmdb", ids);
      const known = new Set((have || []).map((h: any) => h.tmdb));
      const fresh = ids.filter((id) => !known.has(id));
      added += (await addMovies(fresh)).length;
    }
    const last = Math.min(res.total_pages || 1, 60);
    cursor = cursor.page >= last ? { plan: cursor.plan + 1, page: 1 } : { plan: cursor.plan, page: cursor.page + 1 };
    await db.from("fabula_admin").upsert({ key: "ingest_cursor", value: cursor, updated: new Date().toISOString() });
  }
  const { count } = await db.from("movies").select("tmdb", { count: "exact", head: true });
  return { added, cursor, plans: all.length, done: cursor.plan >= all.length, movies: count };
}

function norm(s: string) {
  return s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();
}

async function resolve(title: string, y?: number | null) {
  const tries: Record<string, string | number>[] = [];
  if (y) tries.push({ query: title, primary_release_year: y });
  tries.push({ query: title });
  for (const t of tries) {
    const res = await tmdb("/search/movie", { ...t, include_adult: "false", language: "en-US" });
    const results: any[] = res.results || [];
    if (!results.length) continue;
    const scored = results.map((r) => {
      const ry = year(r.release_date);
      let s = 0;
      if (norm(r.title) === norm(title) || norm(r.original_title || "") === norm(title)) s += 3;
      if (y && ry === y) s += 3; else if (y && ry && Math.abs(ry - y) <= 1) s += 1.5;
      s += Math.min(1, (r.vote_count || 0) / 2000);
      return { r, s };
    }).sort((a, b) => b.s - a.s);
    if (scored[0].s >= 2.5 || !y) return scored[0].r.id as number;
  }
  return null;
}

async function importLog(items: any[]) {
  const missing: string[] = [];
  const now = new Date().toISOString();
  const rows: any[] = [];
  for (let i = 0; i < items.length; i += 8) {
    const chunk = items.slice(i, i + 8);
    const found = await Promise.all(chunk.map(async (it) => {
      try {
        const id = await resolve(String(it.title), it.year ? Number(it.year) : null);
        if (!id) return null;
        const [m] = await addMovies([id]);
        return m ? { it, m } : null;
      } catch { return null; }
    }));
    found.forEach((f, k) => {
      if (!f) { missing.push(`${chunk[k].title} (${chunk[k].year})`); return; }
      const { it, m } = f;
      rows.push({
        user_id: USER, kind: "ortus.log", id: String(m.tmdb), deleted: false, device: "fabula-import",
        data: {
          tmdb: m.tmdb, title: m.title, year: m.year, rating: Number(it.rating), comment: it.comment || "",
          poster: m.poster, language: m.language, genres: m.genres, director: m.director, runtime: m.runtime,
          logged: now, updated: now,
        },
      });
    });
  }
  if (rows.length) {
    const { error } = await db.from("records").upsert(rows, { onConflict: "user_id,kind,id" });
    if (error) throw new Error(error.message);
  }
  return { imported: rows.length, missing };
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
        if (q.length < 2 || q.length > 100) return json({ error: "q must be 2-100 characters" }, 400);
        const params: Record<string, string | number> = { query: q, include_adult: "false", language: "en-US" };
        if (body.kind === "show") {
          const res = await tmdb("/search/tv", params);
          const results = (res.results || [])
            .filter((r: any) => !(r.original_language === "ja" && (r.genre_ids || []).includes(16)))
            .slice(0, 12).map((r: any) => ({
              tmdb: SHOW + r.id, kind: "show", title: r.name, original_title: r.original_name, year: year(r.first_air_date),
              language: LANGS[r.original_language] || r.original_language, poster: r.poster_path, votes: r.vote_count,
            }));
          return json({ results });
        }
        if (body.year) params.primary_release_year = Number(body.year);
        const res = await tmdb("/search/movie", params);
        const results = (res.results || []).slice(0, 12).map((r: any) => ({
          tmdb: r.id, title: r.title, original_title: r.original_title, year: year(r.release_date),
          language: LANGS[r.original_language] || r.original_language, poster: r.poster_path, votes: r.vote_count,
        }));
        return json({ results });
      }
      case "add": {
        const id = Number(body.tmdb);
        if (!Number.isInteger(id) || id <= 0 || id >= 2 * SHOW) return json({ error: "tmdb must be a positive film or show id" }, 400);
        const { data: have } = await db.from("movies").select("*").eq("tmdb", id).maybeSingle();
        if (have && !body.refresh) return json({ movie: have });
        const [m] = id >= SHOW ? await addShows([id - SHOW]) : await addMovies([id]);
        if (!m) return json({ error: "Not found on TMDB" }, 404);
        return json({ movie: m });
      }
      case "ingest": {
        if (!(await authorised(body.token))) return json({ error: "Not allowed" }, 403);
        return json(await ingest());
      }
      case "ingest_shows": {
        if (!(await authorised(body.token))) return json({ error: "Not allowed" }, 403);
        return json(await ingestShows());
      }
      case "imdb": {
        if (!(await authorised(body.token))) return json({ error: "Not allowed" }, 403);
        const kind = ["movie", "show"].includes(body.kind) ? body.kind : "show";
        return json(await imdbFill(kind, body.only !== false));
      }
      case "import": {
        if (!(await authorised(body.token))) return json({ error: "Not allowed" }, 403);
        if (!Array.isArray(body.items) || body.items.length > 400) return json({ error: "items must be an array of up to 400" }, 400);
        return json(await importLog(body.items));
      }
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 502);
  }
});
