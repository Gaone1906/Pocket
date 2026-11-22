import { createClient } from "jsr:@supabase/supabase-js@2";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const USER = "00000000-0000-0000-0000-000000000000";
const MODEL = "claude-haiku-5-5";
const GENRES = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Family", "Fantasy", "History", "Horror", "Music", "Mystery", "Romance", "Sci-fi", "Thriller", "War", "Western"];
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-pocket-source",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

async function keyValid(key: string | null) {
  if (!key) return false;
  const res = await fetch(`${URL_}/rest/v1/movies?select=tmdb&limit=1`, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
  return res.ok;
}

function clean(s: unknown, max: number) {
  return String(s ?? "").replace(/[\u0000-\u001f]/g, " ").trim().slice(0, max);
}

function antKey() {
  return (Deno.env.get("ANT_KEY") || "").trim().replace(/^["']|["']$/g, "").trim();
}

const TASTE_SCHEMA = {
  type: "object",
  properties: {
    summary: { type: "string" },
    more: { type: "array", items: { type: "string" } },
    less: { type: "array", items: { type: "string" } },
    likes: { type: "object", properties: { genres: { type: "array", items: { type: "string" } }, directors: { type: "array", items: { type: "string" } }, keywords: { type: "array", items: { type: "string" } } } },
    dislikes: { type: "object", properties: { genres: { type: "array", items: { type: "string" } }, directors: { type: "array", items: { type: "string" } }, keywords: { type: "array", items: { type: "string" } } } },
  },
  required: ["summary", "more", "less", "likes", "dislikes"],
};

const MOOD_SCHEMA = {
  type: "object",
  properties: {
    films: {
      type: "array",
      items: { type: "object", properties: { title: { type: "string" }, year: { type: "integer" }, why: { type: "string" } }, required: ["title", "year", "why"] },
    },
  },
  required: ["films"],
};

async function haikuOnce(task: string, system: string, user: string, maxTokens: number, schema: unknown) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": antKey(), "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: maxTokens,
      system,
      tools: [{ name: "answer", description: "Return the answer.", input_schema: schema }],
      tool_choice: { type: "tool", name: "answer" },
      messages: [{ role: "user", content: user }],
    }),
  });
  if (res.status === 401) throw new Error(`The ANT_KEY secret was refused (length ${antKey().length}, starts ${antKey().slice(0, 7)})`);
  if (!res.ok) throw new Error(`anthropic ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const out = await res.json();
  const call = (out.content || []).find((c: any) => c.type === "tool_use" && c.name === "answer");
  if (call && call.input && typeof call.input === "object") return call.input;
  const text = (out.content || []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
  console.warn(JSON.stringify({ event: "fabula_ai_no_answer", task, model: MODEL, stop_reason: out.stop_reason, usage: out.usage, text: text.slice(0, 300) }));
  throw new Error(`Model gave no answer (${out.stop_reason || "unknown"})`);
}

async function haiku(task: string, system: string, user: string, maxTokens: number, schema: unknown) {
  try {
    return await haikuOnce(task, system, user, maxTokens, schema);
  } catch (e) {
    const msg = String((e as Error).message || e);
    if (msg.startsWith("The ANT_KEY") || /anthropic 4\d\d/.test(msg)) throw e;
    console.warn(JSON.stringify({ event: "fabula_ai_retry", task, error: msg }));
    return await haikuOnce(task, system, user, maxTokens, schema);
  }
}

async function records(kinds: string[]) {
  const { data, error } = await db.from("records").select("kind,id,data").eq("user_id", USER).in("kind", kinds).or("deleted.is.null,deleted.eq.false");
  if (error) throw new Error(error.message);
  return data || [];
}

function line(l: any) {
  return `${l.title} (${l.year ?? "?"}) ${l.rating}/10${l.director ? `, ${l.director}` : ""}${l.genres?.length ? `, ${l.genres.slice(0, 3).join("/")}` : ""}`;
}

async function taste(fresh: number[]) {
  const rows = await records(["ortus.log"]);
  const logs = rows.map((r: any) => r.data).filter((d: any) => d && d.rating != null);
  if (!logs.length) throw new Error("No ratings yet");
  const freshSet = new Set(fresh);
  const sorted = [...logs].sort((a: any, b: any) => b.rating - a.rating);
  const recent = sorted.filter((l: any) => freshSet.has(l.tmdb));
  const system = "You profile one person's film taste from their ratings. Scores are 1-10; their average sits near 8, so 7 is a soft no and 9+ is love. Answer by calling the answer tool.";
  const user = [
    `All ratings (${logs.length}):`,
    sorted.map(line).join("\n"),
    recent.length ? `\nJust rated in this session:\n${recent.map(line).join("\n")}` : "",
    `\nFill the answer: {"summary": one sentence under 22 words in second person describing their taste, "more": up to 4 short labels (2-4 words) for what they should get more of, weighted toward this session, "less": up to 3 short labels for what to show less, "likes": {"genres": up to 3 from ${JSON.stringify(GENRES)}, "directors": up to 5 exact names, "keywords": up to 8 lowercase TMDB-style keywords like "twist ending"}, "dislikes": {"genres": up to 2 from the same list, "directors": up to 3, "keywords": up to 5}}`,
  ].join("\n");
  const t = await haiku("taste", system, user, 1400, TASTE_SCHEMA);
  const arr = (v: any, n: number, allow?: string[]) => (Array.isArray(v) ? v : []).map((x) => clean(x, 60)).filter((x) => x && (!allow || allow.includes(x))).slice(0, n);
  const now = new Date().toISOString();
  const data = {
    summary: clean(t.summary, 220),
    more: arr(t.more, 4),
    less: arr(t.less, 3),
    likes: { genres: arr(t.likes?.genres, 3, GENRES), directors: arr(t.likes?.directors, 5), keywords: arr(t.likes?.keywords, 8).map((k) => k.toLowerCase()) },
    dislikes: { genres: arr(t.dislikes?.genres, 2, GENRES), directors: arr(t.dislikes?.directors, 3), keywords: arr(t.dislikes?.keywords, 5).map((k) => k.toLowerCase()) },
    ratings: logs.length,
    updated: now,
  };
  const { error } = await db.from("records").upsert({ user_id: USER, kind: "ortus.taste", id: "book", data, deleted: false, device: "fabula-ai" }, { onConflict: "user_id,kind,id" });
  if (error) throw new Error(error.message);
  return data;
}

function norm(s: string) {
  return s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, " ").trim();
}

async function tmdbFn(body: unknown, fn = "fabula-tmdb") {
  const res = await fetch(`${URL_}/functions/v1/${fn}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  if (!res.ok) return null;
  return await res.json();
}

const FIELDS = "tmdb,title,original_title,year,runtime,language,genres,director,cast,overview,poster,backdrop,vote,providers,imdb_rating,imdb_votes,kind,seasons,episodes,format,mal_score";
const NOUNS: Record<string, string> = { movie: "films", show: "TV series", anime: "Japanese anime titles" };

function animeFilm(m: any) {
  return m.language === "Japanese" && (m.genres || []).includes("Animation");
}

async function find(title: string, y: number | null, kind: string) {
  const t = title.replace(/[%_]/g, "");
  const [a, b] = await Promise.all([
    db.from("movies").select(FIELDS).eq("kind", kind).ilike("title", t).limit(5),
    db.from("movies").select(FIELDS).eq("kind", kind).ilike("original_title", t).limit(5),
  ]);
  const hits = [...(a.data || []), ...(b.data || [])].filter((m: any) => norm(m.title) === norm(title) || norm(m.original_title || "") === norm(title));
  const best = hits.sort((p: any, q: any) => Math.abs((p.year ?? 0) - (y ?? 0)) - Math.abs((q.year ?? 0) - (y ?? 0)))[0];
  if (best && (!y || !best.year || Math.abs(best.year - y) <= 1) && !(kind === "movie" && animeFilm(best))) return best;
  if (best && kind === "movie" && animeFilm(best)) return null;
  const fn = kind === "anime" ? "fabula-anime" : "fabula-tmdb";
  const q = kind === "anime" ? title.slice(0, 64) : title;
  const s = await tmdbFn(kind === "anime" ? { action: "search", q } : { action: "search", q, kind, year: kind === "movie" ? y || undefined : undefined }, fn);
  const list: any[] = s?.results || [];
  const r = list.find((x: any) => (norm(x.title) === norm(title) || norm(x.original_title || "") === norm(title)) && (!y || !x.year || Math.abs(x.year - y) <= 1))
    || list.find((x: any) => norm(x.title) === norm(title) || norm(x.original_title || "") === norm(title))
    || list[0];
  if (!r) return null;
  const added = await tmdbFn({ action: "add", tmdb: r.tmdb }, fn);
  const m = added?.movie;
  if (!m) return null;
  const out: any = {};
  for (const k of FIELDS.split(",")) out[k] = m[k];
  if (kind === "movie" && animeFilm(out)) return null;
  return out;
}

async function mood(text: string, notes: string[], shown: number[], kind: string) {
  const many = NOUNS[kind];
  const rows = await records(["ortus.log", "ortus.swipe", "ortus.taste"]);
  const logs = rows.filter((r: any) => r.kind === "ortus.log").map((r: any) => r.data).filter(Boolean);
  const swipes = rows.filter((r: any) => r.kind === "ortus.swipe").map((r: any) => r.data).filter(Boolean);
  const profile = rows.find((r: any) => r.kind === "ortus.taste" && r.id === "book")?.data;
  const seenIds = new Set<number>([...logs, ...swipes].map((d: any) => Number(d.tmdb)).filter(Boolean));
  const seenTitles = new Set<string>([...logs, ...swipes].map((d: any) => norm(String(d.title || ""))).filter(Boolean));
  const shownSet = new Set(shown);
  const loved = logs.filter((l: any) => l.rating >= 9).sort((a: any, b: any) => b.rating - a.rating).slice(0, 40);
  const disliked = logs.filter((l: any) => l.rating <= 6.5).slice(0, 15);
  const { data: shownRows } = shown.length ? await db.from("movies").select("title,year").in("tmdb", shown) : { data: [] };
  const system = `You recommend ${many} to one person for tonight. Match their mood first, their taste second. ${kind === "anime" ? "Suggest only Japanese anime (series or films)." : kind === "show" ? "Suggest only TV series in English, Korean or Hindi, never anime." : "Suggest only feature films, never anime films."} Prefer titles that are easy to stream in India. Never suggest a title they have already seen or were already shown. Answer by calling the answer tool.`;
  const user = [
    `Mood: ${text}`,
    notes.length ? `Follow-up notes, newest last:\n${notes.map((n) => `- ${n}`).join("\n")}` : "",
    profile?.summary ? `Taste profile: ${profile.summary}` : "",
    `Loved (9+):\n${loved.map(line).join("\n")}`,
    disliked.length ? `Disliked:\n${disliked.map(line).join("\n")}` : "",
    `Already seen or swiped (never suggest): ${[...logs, ...swipes].map((d: any) => d.title).filter(Boolean).join("; ")}`,
    (shownRows || []).length ? `Already shown tonight (never suggest again): ${(shownRows || []).map((m: any) => `${m.title} (${m.year})`).join("; ")}` : "",
    `Their ratings above may include films, shows and anime; use them for taste, but suggest only ${many}.`,
    `Fill the answer: {"films": [12 items of {"title": ${kind === "anime" ? "the title as listed on MyAnimeList, in English when it has one" : `exact English ${kind === "show" ? "series" : "release"} title`}, "year": ${kind === "movie" ? "release year" : "first air year"}, "why": one sentence under 18 words tying it to the mood}]}`,
  ].filter(Boolean).join("\n\n");
  const films: any[] = [];
  const ids = new Set<number>();
  const ruledOut: string[] = [];
  for (let round = 1; round <= 3 && films.length < 4; round++) {
    const ask = round === 1 ? user : `${user}\n\nThese were already ruled out, so suggest different ${many}: ${ruledOut.join("; ")}`;
    const out = await haiku("mood", system, ask, 2200, MOOD_SCHEMA);
    const ideas = (Array.isArray(out.films) ? out.films : []).slice(0, 12);
    let seen = 0, missing = 0, dup = 0;
    const resolved = await Promise.all(ideas.map(async (f: any) => {
      const title = clean(f.title, 120);
      if (!title) return null;
      const label = `${title} (${Number(f.year) || "?"})`;
      if (seenTitles.has(norm(title))) { seen++; ruledOut.push(label); return null; }
      try {
        const m = await find(title, Number(f.year) || null, kind);
        if (!m) { missing++; ruledOut.push(label); return null; }
        if (seenIds.has(m.tmdb) || shownSet.has(m.tmdb)) { seen++; ruledOut.push(label); return null; }
        const { imdb_rating, imdb_votes, mal_score, original_title, ...rest } = m;
        return {
          ...rest, imdb: (imdb_votes ?? 0) >= (kind === "show" ? 500 : 1000) ? imdb_rating : null, mal: kind === "anime" ? mal_score : null,
          cast: (m.cast || []).slice(0, 3), why: clean(f.why, 200),
        };
      } catch (e) {
        missing++;
        ruledOut.push(label);
        console.warn(JSON.stringify({ event: "fabula_ai_mood_find_failed", title, year: f.year, error: String((e as Error).message || e) }));
        return null;
      }
    }));
    for (const m of resolved) {
      if (!m) continue;
      if (ids.has(m.tmdb)) { dup++; continue; }
      ids.add(m.tmdb);
      films.push(m);
      ruledOut.push(`${m.title} (${m.year})`);
    }
    console.log(JSON.stringify({ event: "fabula_ai_mood_round", round, mood: text.slice(0, 80), ideas: ideas.length, seen, missing, dup, kept: films.length }));
  }
  if (films.length < 4) console.warn(JSON.stringify({ event: "fabula_ai_mood_short", mood: text.slice(0, 80), kept: films.length }));
  return { films: films.slice(0, 4) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Body must be JSON" }, 400); }
  if (!(await keyValid(req.headers.get("apikey")))) return json({ error: "Not allowed" }, 403);
  try {
    switch (body?.action) {
      case "mood": {
        const text = clean(body.text, 600);
        if (text.length < 2) return json({ error: "Tell me the mood first" }, 400);
        const notes = (Array.isArray(body.notes) ? body.notes : []).map((n: unknown) => clean(n, 300)).filter(Boolean).slice(-8);
        const shown = (Array.isArray(body.shown) ? body.shown : []).map(Number).filter((n: number) => Number.isInteger(n) && n > 0).slice(-80);
        const kind = ["show", "anime"].includes(body.kind) ? body.kind : "movie";
        return json(await mood(text, notes, shown, kind));
      }
      case "taste": {
        const fresh = (Array.isArray(body.fresh) ? body.fresh : []).map(Number).filter((n: number) => Number.isInteger(n) && n > 0).slice(0, 400);
        return json({ taste: await taste(fresh) });
      }
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (e) {
    return json({ error: String((e as Error).message || e) }, 502);
  }
});
