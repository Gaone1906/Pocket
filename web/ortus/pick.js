export const MODES = ["quotes", "reels", "videos", "stories"];

export const QUOTE_THEMES = ["Courage", "Resilience", "Purpose", "Mindset", "Perseverance", "Excellence", "Discipline", "Failure", "Patience", "Action"];

export const REEL_CATEGORIES = ["Speeches", "Never give up", "Discipline", "Legends", "Stories", "Sports", "Kindness & humanity", "Life advice"];

export function dayKey(now = new Date()) {
  const d = new Date(now.getTime() - 4 * 3600 * 1000);
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function hash(text) {
  let h = 0x811c9dc5;
  const bytes = new TextEncoder().encode(text);
  for (const b of bytes) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export function daily(items, kind, day = dayKey()) {
  if (!items.length) return null;
  const sorted = [...items].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return sorted[hash(`${kind}|${day}`) % sorted.length];
}

export function shuffled(items, seed) {
  return [...items].sort((a, b) => hash(seed + "|" + a.id) - hash(seed + "|" + b.id));
}

export function youtubeId(url) {
  const text = String(url || "");
  const m = text.match(/(?:shorts\/|embed\/|youtu\.be\/|[?&]v=)([A-Za-z0-9_-]{11})/);
  return m ? m[1] : null;
}

export function embedUrl(item, autoplay) {
  const id = youtubeId(item.url);
  if (!id) return null;
  const q = new URLSearchParams({ playsinline: "1", rel: "0", modestbranding: "1" });
  if (autoplay) q.set("autoplay", "1");
  if (Number(item.start) > 0) q.set("start", String(Math.floor(item.start)));
  if (Number(item.end) > 0) q.set("end", String(Math.floor(item.end)));
  return `https://www.youtube-nocookie.com/embed/${id}?${q}`;
}

export function watchUrl(item) {
  const id = youtubeId(item.url);
  if (!id) return item.url || "";
  return /shorts\//.test(item.url || "") ? `https://www.youtube.com/shorts/${id}` : `https://www.youtube.com/watch?v=${id}${Number(item.start) > 0 ? "&t=" + Math.floor(item.start) : ""}`;
}

export function views(n) {
  const v = Number(n) || 0;
  if (v >= 1e9) return (v / 1e9).toFixed(1).replace(/\.0$/, "") + "B";
  if (v >= 1e6) return Math.round(v / 1e6) + "M";
  if (v >= 1e3) return Math.round(v / 1e3) + "K";
  return String(v);
}

export function byViews(items) {
  return [...items].sort((a, b) => (Number(b.views) || 0) - (Number(a.views) || 0) || (a.id < b.id ? -1 : 1));
}

export function storyMinutes(story) {
  const words = (story.paras || []).join(" ").split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 200));
}

export function cleanTitle(text) {
  return String(text || "")
    .replace(/#[\p{L}\p{N}_]+/gu, "")
    .replace(/[\p{Extended_Pictographic}\u200d\ufe0f]/gu, "")
    .replace(/\s*[|]+\s*$/g, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}
