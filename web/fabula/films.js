import { esc, ICONS } from "./util.js";

export const LANGUAGES = ["English", "Hindi", "Telugu", "Tamil", "Malayalam", "Kannada", "Korean", "Japanese", "Spanish", "French"];
export const GENRES = ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Family", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Thriller", "War"];
export const KINDS = ["movie", "show", "anime"];
export const KIND_NAMES = { movie: "Movies", show: "Shows", anime: "Anime" };
export const KIND_LANGS = { movie: LANGUAGES, show: ["English", "Korean", "Hindi"], anime: [] };
export const KIND_GENRES = {
  movie: GENRES,
  show: ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Family", "Fantasy", "Mystery", "Romance", "Sci-fi", "War"],
  anime: ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-fi", "Slice of Life", "Sports", "Supernatural", "Thriller"],
};
export const NOUN = { movie: ["film", "films"], show: ["show", "shows"], anime: ["anime", "anime"] };

export function kindOf(film) {
  if (film && KINDS.includes(film.kind)) return film.kind;
  const id = Number(film && film.tmdb);
  return id >= 200000000 ? "anime" : id >= 100000000 ? "show" : "movie";
}

export function noun(kind, n = 1) {
  const w = NOUN[kind] || NOUN.movie;
  return n === 1 ? w[0] : w[1];
}

const GRADIENTS = [
  ["#1d2a44", "#5b4426", "#c99a52"],
  ["#191932", "#4b3a7a", "#c9a2e0"],
  ["#4a1020", "#b8402a", "#f3b16b"],
  ["#2a0f0f", "#7a2a2a", "#e0a080"],
  ["#0f3b3a", "#1a6b5b", "#c7e3c1"],
  ["#0f2a3b", "#1a5b7b", "#a1d3e3"],
  ["#13234a", "#3d5bb0", "#9fc0ff"],
  ["#3a1050", "#a03fb0", "#f0b0e0"],
  ["#2a1a08", "#7a4a1a", "#e0b070"],
];

export function gradient(id) {
  const g = GRADIENTS[Math.abs(Number(id) || 0) % GRADIENTS.length];
  return `linear-gradient(165deg,${g[0]} 0%,${g[1]} 60%,${g[2]} 100%)`;
}

export function posterUrl(path, size = "w500") {
  if (!path || typeof path !== "string") return "";
  if (/^https?:/.test(path)) return path;
  return "https://image.tmdb.org/t/p/" + size + (path.startsWith("/") ? path : "/" + path);
}

export function posterStyle(film, size = "w500") {
  const url = posterUrl(film && film.poster, size);
  const bg = gradient(film && film.tmdb);
  return url ? `background-image:url('${esc(url)}'),${bg}` : `background-image:${bg}`;
}

export function runtime(min) {
  const m = Number(min);
  if (!m) return "";
  const h = Math.floor(m / 60);
  return h ? `${h}h ${m % 60}m` : `${m}m`;
}

export function genreList(film) {
  return Array.isArray(film && film.genres) ? film.genres : [];
}

function plural(n, one, many) {
  return n ? `${n} ${n === 1 ? one : many}` : "";
}

export function meta(film, { genres = 2, director = false } = {}) {
  if (!film) return "";
  const kind = kindOf(film);
  if (kind === "anime") {
    return [film.year, film.format, film.format === "Movie" ? runtime(film.runtime) : plural(Number(film.episodes), "ep", "eps"), director ? film.director : genreList(film).slice(0, genres).join(", ") || film.director]
      .filter(Boolean)
      .join(" · ");
  }
  if (kind === "show") {
    const g = director ? film.director : genreList(film).slice(0, genres).join(", ");
    return [film.year, plural(Number(film.seasons), "season", "seasons"), film.runtime ? `${film.runtime}m` : "", g, film.language && film.language !== "English" ? film.language : ""]
      .filter(Boolean)
      .join(" · ");
  }
  const parts = [film.year, runtime(film.runtime)];
  if (director) parts.push(film.director);
  else {
    const g = genreList(film).slice(0, genres).join(", ");
    if (g) parts.push(g);
    if (film.language && film.language !== "English") parts.push(film.language);
  }
  return parts.filter(Boolean).join(" · ");
}

export function imdbTag(film) {
  const m = film && film.mal != null && film.mal !== "" ? Number(film.mal) : NaN;
  if (Number.isFinite(m)) return `<span class="imdb mal">MAL: <b>${m.toFixed(2)}</b>/10</span>`;
  const n = film && film.imdb != null && film.imdb !== "" ? Number(film.imdb) : NaN;
  if (!Number.isFinite(n)) return "";
  return `<span class="imdb">IMDb: <b>${n.toFixed(1)}</b>/10</span>`;
}

export function metaRow(film, opts, cls = "meta") {
  return `<div class="metarow"><span class="${cls}">${esc(meta(film, opts))}</span>${imdbTag(film)}</div>`;
}

export function initial(name) {
  return (String(name || "?").trim()[0] || "?").toUpperCase();
}

const AVATARS = [
  ["#E8673C", "#1A0D07"],
  ["#2F8F5B", "#FFFFFF"],
  ["#6A4FA8", "#FFFFFF"],
  ["#3D6FB0", "#FFFFFF"],
  ["#B0476A", "#FFFFFF"],
  ["#8A6A2A", "#FFFFFF"],
  ["#2A8A8A", "#FFFFFF"],
  ["#7A4AA0", "#FFFFFF"],
];

export function avatar(name, i, cls = "") {
  const [bg, fg] = AVATARS[i % AVATARS.length];
  return `<span class="avatar ${cls}" style="background:${bg};color:${fg}">${esc(initial(name))}</span>`;
}

export function stamps() {
  return `<span class="stamp yes" data-stamp="yes">YES</span><span class="stamp no" data-stamp="no">NOPE</span><span class="stamp seen" data-stamp="seen">SEEN IT</span>`;
}

export function card(film, { top = false, undo = false, canUndo = false, superlike = false, why = true, open = false } = {}) {
  if (!film) return "";
  const overview = film.overview || "";
  return `<div class="card ${top ? "top" : "under"} ${superlike ? "gold" : ""} ${open ? "open" : ""}" ${top ? `data-card="${esc(film.tmdb)}"` : ""}>
    <div class="face">
      <div class="poster" style="${posterStyle(film, "w780")}">
        <div class="shade"></div>
      </div>
      <div class="dim"></div>
      ${undo ? `<button class="undo" data-act="undo" aria-label="Undo last swipe" ${canUndo ? "" : "disabled"}>${ICONS.undo}</button>` : ""}
      <span class="badge">Superlike</span>
      ${top ? stamps() : ""}
      <div class="lower">
        <span class="ctitle">${esc(film.title)}</span>
        <div class="info">
          ${metaRow(film)}
          ${overview ? `<span class="hook" ${top ? `data-act="hook" role="button" tabindex="0" aria-expanded="${open}"` : ""}>${esc(overview)}</span>` : ""}
          ${why && film.why ? `<span class="why">${esc(film.why)}</span>` : ""}
        </div>
      </div>
    </div>
  </div>`;
}

export function thumb(film, cls = "thumb") {
  return `<div class="${cls}" style="${posterStyle(film, "w185")}"></div>`;
}

export function ratingText(r) {
  const n = Number(r);
  if (!Number.isFinite(n)) return "";
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

export function ratingClass(r) {
  const n = Number(r);
  if (n >= 9) return "hi";
  if (n >= 7) return "mid";
  return "lo";
}
