import { createClient } from "jsr:@supabase/supabase-js@2";

const TMDB = "https://api.themoviedb.org/3";
const ANTHROPIC = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-haiku-5-5";
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
const STRENGTHS = ["more", "much more", "less", "much less"];
const PREFIXES = ["g:", "k:", "d:", "l:"];

class BadInput extends Error {}
class Upstream extends Error {}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function ints(v: unknown, field: string, max: number): number[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max || !v.every((x) => Number.isInteger(x) && x > 0)) throw new BadInput(`${field} must be an array of up to ${max} positive integers`);
  return v as number[];
}

function strings(v: unknown, field: string, max: number, maxLen = 500): string[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > max || !v.every((x) => typeof x === "string" && x.trim().length > 0 && x.length <= maxLen)) {
    throw new BadInput(`${field} must be an array of up to ${max} non-empty strings of at most ${maxLen} characters`);
  }
  return (v as string[]).map((x) => x.trim());
}

async function tmdb(path: string, params: Record<string, string | number> = {}) {
  const url = new URL(TMDB + path);
  for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v));
  for (let attempt = 0; attempt < 4; attempt++) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${Deno.env.get("TMDB_TOKEN")}`, Accept: "application/json" } });
    if (res.status === 429) { await new Promise((r) => setTimeout(r, 1000 * (attempt + 1))); continue; }
    if (!res.ok) {
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "tmdb", path, status: res.status }));
      throw new Error(`tmdb ${res.status} ${path}`);
    }
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
    vote: d.vote_average ?? null,
    votes: d.vote_count ?? null,
    popularity: d.popularity ?? null,
    collection: d.belongs_to_collection?.id ?? null,
    providers: (india?.flatrate || []).map((p: any) => p.provider_name),
    recs: (d.recommendations?.results || []).slice(0, 20).map((r: any) => r.id),
    updated: new Date().toISOString(),
  };
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
    if (error) {
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "upsert movies", ids: out.length, error: error.message }));
      throw new Error(error.message);
    }
  }
  return out;
}

function norm(s: string) {
  return s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();
}

async function resolveOnTmdb(title: string, y?: number | null) {
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

function film(m: any, why: string | null) {
  return {
    tmdb: m.tmdb, title: m.title, year: m.year, runtime: m.runtime, language: m.language,
    genres: m.genres, director: m.director, cast: (m.cast || []).slice(0, 3), overview: m.overview,
    poster: m.poster, backdrop: m.backdrop, vote: m.vote, providers: m.providers, why,
  };
}

async function claude(call: string, system: string, user: string, accept: (v: any) => any): Promise<any> {
  const key = Deno.env.get("ANT_KEY");
  if (!key) throw new Upstream("AI is not configured");
  for (let attempt = 1; attempt <= 2; attempt++) {
    const started = Date.now();
    let res: Response;
    try {
      res = await fetch(ANTHROPIC, {
        method: "POST",
        headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
        body: JSON.stringify({ model: MODEL, max_tokens: 2000, system, messages: [{ role: "user", content: user }] }),
        signal: AbortSignal.timeout(50_000),
      });
    } catch (e) {
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "anthropic", call, attempt, error: String((e as Error).message || e), ms: Date.now() - started }));
      if (attempt === 2) throw new Upstream("AI is unavailable right now");
      continue;
    }
    if (!res.ok) {
      const detail = (await res.text().catch(() => "")).slice(0, 300);
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "anthropic", call, attempt, status: res.status, detail, ms: Date.now() - started }));
      if (attempt === 2 || (res.status < 500 && res.status !== 429)) throw new Upstream("AI is unavailable right now");
      continue;
    }
    const payload = await res.json();
    const text = (payload.content || []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
    const parsed = extractJson(text);
    const accepted = parsed === null ? null : accept(parsed);
    if (accepted) return accepted;
    console.error(JSON.stringify({ fn: "fabula-ai", upstream: "anthropic", call, attempt, error: "unparseable or invalid output", chars: text.length, stop: payload.stop_reason, ms: Date.now() - started }));
  }
  throw new Upstream("AI returned an unreadable answer, try again");
}

function extractJson(text: string): any {
  const start = text.indexOf("{");
  if (start < 0) return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === "{") depth++;
    else if (c === "}") {
      depth--;
      if (depth === 0) {
        try { return JSON.parse(text.slice(start, i + 1)); } catch { return null; }
      }
    }
  }
  return null;
}

async function recordRows(kind: string) {
  const rows: any[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await db.from("records")
      .select("tmdb:data->>tmdb, rating:data->>rating, verdict:data->>verdict")
      .eq("user_id", USER).eq("kind", kind).or("deleted.is.null,deleted.eq.false")
      .range(from, from + 999);
    if (error) {
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "select records", kind, error: error.message }));
      throw new Error(error.message);
    }
    rows.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  return rows.filter((r) => r.tmdb !== null && Number.isInteger(Number(r.tmdb))).map((r) => ({ tmdb: Number(r.tmdb), rating: r.rating === null ? null : Number(r.rating), verdict: r.verdict as string | null }));
}

async function movieRows(ids: number[], columns: string) {
  const out: any[] = [];
  const unique = [...new Set(ids)];
  for (let i = 0; i < unique.length; i += 200) {
    const { data, error } = await db.from("movies").select(columns).in("tmdb", unique.slice(i, i + 200));
    if (error) {
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "select movies", ids: unique.length, error: error.message }));
      throw new Error(error.message);
    }
    out.push(...(data || []));
  }
  return out;
}

async function refine(body: any) {
  const langs = strings(body.langs, "langs", 20);
  const genres = strings(body.genres, "genres", 20);
  const exclude = ints(body.exclude, "exclude", 1000);
  const { data, error } = await db.rpc("fabula_refine", { p_langs: langs, p_genres: genres, p_exclude: exclude, p_limit: 10 });
  if (error) {
    console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "rpc fabula_refine", langs, genres, exclude: exclude.length, error: error.message }));
    throw new Upstream(error.message);
  }
  const films = Array.isArray(data) ? data : [];
  return { result: { films }, sizes: { langs: langs.length, genres: genres.length, exclude: exclude.length }, out: { films: films.length } };
}

function describeFilm(m: any, rating?: number | null) {
  const parts = [`${m.title}${m.year ? ` (${m.year})` : ""}`];
  if (m.director) parts.push(`dir. ${m.director}`);
  if ((m.genres || []).length) parts.push((m.genres as string[]).join("/"));
  if (rating !== undefined && rating !== null) parts.push(`rated ${rating}/10`);
  return parts.join(", ");
}

function describeRated(m: any, rating: number) {
  const parts = [describeFilm(m, rating)];
  if (m.language) parts.push(m.language);
  if ((m.keywords || []).length) parts.push(`keywords: ${(m.keywords as string[]).slice(0, 8).join(", ")}`);
  return parts.join(", ");
}

const TASTE_SYSTEM = `You maintain a film taste profile for one person. Reply with a single JSON object and nothing else, in exactly this shape:
{"summary": string, "changes": [{"label": string, "dir": "up" | "down", "strength": "more" | "much more" | "less" | "much less"}], "weights": {"g:<genre>": number, "k:<keyword>": number, "d:<director>": number, "l:<language>": number}}
Rules: summary is one warm sentence in second person describing their taste. changes has 3 to 6 items, each a short plain label such as "Slow-burn thrillers" or "Mainstream sequels", dir up when the new ratings say they want more of it and down for less, strength says how strongly. weights holds at most 40 entries; each value is between -1 and 1 (positive means recommend more of it, negative means less); keys must start with g: (genre), k: (keyword), d: (director) or l: (language) followed by a name spelled exactly as it appears in the film data you are given.`;

function acceptTaste(v: any) {
  if (!v || typeof v.summary !== "string" || !v.summary.trim() || !Array.isArray(v.changes)) return null;
  const changes = v.changes
    .filter((c: any) => c && typeof c.label === "string" && c.label.trim() && (c.dir === "up" || c.dir === "down") && STRENGTHS.includes(c.strength))
    .slice(0, 6)
    .map((c: any) => ({ label: c.label.trim().slice(0, 80), dir: c.dir, strength: c.strength }));
  if (changes.length < 1) return null;
  const weights: Record<string, number> = {};
  const entries = v.weights && typeof v.weights === "object" ? Object.entries(v.weights) : [];
  for (const [k, raw] of entries) {
    const n = Number(raw);
    if (!PREFIXES.some((p) => k.startsWith(p)) || k.length <= 2 || k.length > 120 || !Number.isFinite(n)) continue;
    if (Object.keys(weights).length >= 40) break;
    weights[k] = Math.max(-1, Math.min(1, n));
  }
  return { summary: v.summary.trim().slice(0, 400), changes, weights };
}

async function taste(body: any) {
  if (!Array.isArray(body.rated) || body.rated.length > 300 ||
    !body.rated.every((r: any) => r && Number.isInteger(r.tmdb) && r.tmdb > 0 && typeof r.rating === "number" && r.rating >= 0 && r.rating <= 10)) {
    throw new BadInput("rated must be an array of up to 300 {tmdb, rating} with rating 0-10");
  }
  const rated: { tmdb: number; rating: number }[] = body.rated;
  const unseen = ints(body.unseen, "unseen", 1000);
  if (unseen.length) {
    const { error } = await db.from("fabula_refined").upsert(unseen.map((tmdb) => ({ tmdb })), { onConflict: "tmdb" });
    if (error) {
      console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "upsert fabula_refined", unseen: unseen.length, error: error.message }));
      throw new Upstream(error.message);
    }
  }
  const logs = (await recordRows("ortus.log")).filter((l) => l.rating !== null) as { tmdb: number; rating: number }[];
  const byRating = [...logs].sort((a, b) => b.rating - a.rating);
  const best = byRating.slice(0, 25);
  const worst = byRating.slice(-15).reverse().filter((w) => !best.some((b) => b.tmdb === w.tmdb));
  const cols = "tmdb,title,year,director,genres,keywords,language";
  const meta = new Map((await movieRows([...best, ...worst, ...rated].map((x) => x.tmdb), cols)).map((m: any) => [m.tmdb as number, m]));
  const line = (x: { tmdb: number; rating: number }, full: boolean) => {
    const m = meta.get(x.tmdb);
    if (!m) return null;
    return full ? describeRated(m, x.rating) : describeFilm(m, x.rating);
  };
  const user = [
    "Their best-rated logged films:",
    ...best.map((x) => line(x, false)).filter(Boolean),
    "",
    "Their worst-rated logged films:",
    ...worst.map((x) => line(x, false)).filter(Boolean),
    "",
    "New ratings just given in a refining session (these matter most):",
    ...rated.map((x) => line(x, true)).filter(Boolean),
    "",
    `Films they said they have not seen: ${unseen.length}`,
  ].join("\n");
  const result = await claude("taste", TASTE_SYSTEM, user, acceptTaste);
  const { error } = await db.from("fabula_taste").upsert({
    id: 1, summary: result.summary, changes: result.changes, weights: result.weights, updated: new Date().toISOString(),
  }, { onConflict: "id" });
  if (error) {
    console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "upsert fabula_taste", error: error.message }));
    throw new Upstream(error.message);
  }
  return {
    result: { summary: result.summary, changes: result.changes },
    sizes: { rated: rated.length, unseen: unseen.length, logs: logs.length },
    out: { changes: result.changes.length, weights: Object.keys(result.weights).length },
  };
}

const MOOD_SYSTEM = `You are a film recommender. Reply with a single JSON object and nothing else, in exactly this shape:
{"films": [{"title": string, "year": number, "why": string}]}
Rules: suggest real, released feature films that match the mood and the person's taste. title is the English title as listed on TMDB, year is the release year. why is one short sentence in second person explaining why this suits their mood, with no spoilers. Never suggest a film on the avoid list. Mix well-known and lesser-known picks.`;

function acceptFilms(v: any) {
  if (!v || !Array.isArray(v.films)) return null;
  const films = v.films
    .filter((f: any) => f && typeof f.title === "string" && f.title.trim() && Number.isFinite(Number(f.year)))
    .map((f: any) => ({ title: f.title.trim().slice(0, 200), year: Number(f.year), why: typeof f.why === "string" ? f.why.trim().slice(0, 300) : null }));
  return films.length ? films : null;
}

function likePattern(s: string) {
  return s.replace(/[\\%_]/g, (c) => `\\${c}`);
}

async function resolveCandidate(c: { title: string; year: number }) {
  const { data, error } = await db.from("movies").select("*").ilike("title", likePattern(c.title)).gte("year", c.year - 1).lte("year", c.year + 1).limit(5);
  if (error) {
    console.error(JSON.stringify({ fn: "fabula-ai", upstream: "db", op: "select movies by title", title: c.title, year: c.year, error: error.message }));
    return null;
  }
  const rows = (data || []).sort((a: any, b: any) => Math.abs(a.year - c.year) - Math.abs(b.year - c.year) || (b.votes || 0) - (a.votes || 0));
  if (rows.length) return { row: rows[0], added: false };
  try {
    const id = await resolveOnTmdb(c.title, c.year);
    if (!id) return null;
    const { data: have } = await db.from("movies").select("*").eq("tmdb", id).maybeSingle();
    if (have) return { row: have, added: false };
    const [m] = await addMovies([id]);
    return m ? { row: m, added: true } : null;
  } catch (e) {
    console.error(JSON.stringify({ fn: "fabula-ai", op: "resolve candidate", title: c.title, year: c.year, error: String((e as Error).message || e) }));
    return null;
  }
}

async function mood(body: any) {
  if (typeof body.text !== "string" || !body.text.trim() || body.text.length > 500) throw new BadInput("text must be 1-500 characters");
  const text = body.text.trim();
  const notes = strings(body.notes, "notes", 10);
  const exclude = ints(body.exclude, "exclude", 1000);

  const [logs, swipes, tasteRow, excludedRows] = await Promise.all([
    recordRows("ortus.log"),
    recordRows("ortus.swipe"),
    db.from("fabula_taste").select("summary").eq("id", 1).maybeSingle(),
    exclude.length ? movieRows(exclude, "tmdb,title,year") : Promise.resolve([] as any[]),
  ]);
  const blocked = new Set<number>([...logs.map((l) => l.tmdb), ...swipes.map((s) => s.tmdb), ...exclude]);
  const topLogs = logs.filter((l) => l.rating !== null).sort((a, b) => (b.rating as number) - (a.rating as number)).slice(0, 20);
  const topMeta = new Map((await movieRows(topLogs.map((l) => l.tmdb), "tmdb,title,year")).map((m: any) => [m.tmdb as number, m]));
  const loved = topLogs.map((l) => topMeta.get(l.tmdb)).filter(Boolean).map((m: any) => `${m.title}${m.year ? ` (${m.year})` : ""}`);
  const avoid = excludedRows.map((m: any) => `${m.title}${m.year ? ` (${m.year})` : ""}`);
  const summary = tasteRow.data?.summary || "";

  const prompt = (more: string[]) => [
    `Mood: ${text}`,
    notes.length ? `Fine-tune notes from earlier rounds, oldest first:\n${notes.map((n) => `- ${n}`).join("\n")}` : "",
    summary ? `Their taste: ${summary}` : "",
    loved.length ? `Their highest-rated films: ${loved.join("; ")}` : "",
    avoid.length || more.length ? `Avoid list (already shown): ${[...avoid, ...more].join("; ")}` : "",
    "Give 10 candidate films.",
  ].filter(Boolean).join("\n\n");

  const picked: { film: any; why: string | null }[] = [];
  const seenTitles = new Set<string>();
  const proposed: string[] = [];
  let candidates = 0;
  let added = 0;
  let rounds = 0;
  while (picked.length < 4 && rounds < 2) {
    rounds++;
    const films: { title: string; year: number; why: string | null }[] = await claude(`mood-${rounds}`, MOOD_SYSTEM, prompt(proposed), acceptFilms);
    candidates += films.length;
    proposed.push(...films.map((f) => `${f.title} (${f.year})`));
    const resolved = await Promise.all(films.map((f) => resolveCandidate(f)));
    resolved.forEach((r, i) => {
      if (!r || picked.length >= 4) return;
      const m = r.row;
      const key = norm(m.title);
      if (blocked.has(m.tmdb) || seenTitles.has(key)) return;
      if (r.added) added++;
      seenTitles.add(key);
      blocked.add(m.tmdb);
      picked.push({ film: film(m, films[i].why), why: films[i].why });
    });
  }
  if (!picked.length) throw new Upstream("Couldn't find matching films this time, try rephrasing");
  return {
    result: { films: picked.map((p) => p.film) },
    sizes: { text: text.length, notes: notes.length, exclude: exclude.length },
    out: { films: picked.length, candidates, rounds, addedFromTmdb: added },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const started = Date.now();
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Body must be JSON" }, 400); }
  const action = String(body?.action ?? "");
  try {
    let done: { result: unknown; sizes: Record<string, number>; out: Record<string, number> };
    switch (action) {
      case "refine": done = await refine(body); break;
      case "taste": done = await taste(body); break;
      case "mood": done = await mood(body); break;
      default: throw new BadInput("Unknown action");
    }
    console.log(JSON.stringify({ fn: "fabula-ai", action, status: 200, in: done.sizes, out: done.out, ms: Date.now() - started }));
    return json(done.result);
  } catch (e) {
    const message = String((e as Error).message || e);
    const status = e instanceof BadInput ? 400 : 502;
    console.log(JSON.stringify({ fn: "fabula-ai", action, status, error: message, ms: Date.now() - started }));
    return json({ error: message }, status);
  }
});
