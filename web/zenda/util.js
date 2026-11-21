export const $ = (sel, root = document) => root.querySelector(sel);
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
export const pad = (n) => String(n).padStart(2, "0");
export const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
export const parseDay = (k) => {
  const [y, m, d] = k.split("-").map(Number);
  return new Date(y, m - 1, d);
};
export const shiftDay = (k, n) => {
  const d = parseDay(k);
  return dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() + n));
};
export const weekday = (k) => parseDay(k).getDay() + 1;
export const isoWeekday = (k) => ((parseDay(k).getDay() + 6) % 7) + 1;
export const weekStart = (k) => shiftDay(k, -((parseDay(k).getDay() + 6) % 7));
export const spanDays = (a, b) => Math.round((parseDay(b) - parseDay(a)) / 86400000);
export const isoNow = () => new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
export const dayTitle = (k, opts = { weekday: "long", day: "numeric", month: "short" }) => parseDay(k).toLocaleDateString("en-GB", opts);
export const uuid = () => crypto.randomUUID().toUpperCase();

export function readLocal(key, fallback) {
  try {
    const v = localStorage.getItem(key);
    return v == null ? fallback : v;
  } catch (e) {
    return fallback;
  }
}

export function writeLocal(key, value) {
  try {
    if (value == null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch (e) {}
}

const s = (body, extra = "") => `<svg viewBox="0 0 24 24" ${extra}>${body}</svg>`;

export const ICONS = {
  today: s('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="1.8" fill="currentColor" stroke="none"/>'),
  calendar: s('<rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
  play: s('<path d="M8 5.5v13l11-6.5z" fill="currentColor"/>'),
  bars: s('<path d="M6 19v-7M12 19V5M18 19v-10"/>'),
  gear: s('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>'),
  sun: s('<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/>'),
  moon: s('<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>'),
  check: s('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  left: s('<path d="M15 5l-7 7 7 7"/>'),
  right: s('<path d="M9 5l7 7-7 7"/>'),
  arrow: s('<path d="M5 12h14M13 6l6 6-6 6"/>'),
  down: s('<path d="M6 9l6 6 6-6"/>'),
  plus: s('<path d="M12 5v14M5 12h14"/>'),
  close: s('<path d="M6 6l12 12M18 6L6 18"/>'),
  pause: s('<path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor" stroke="none"/>'),
  resume: s('<path d="M8 5.5v13l11-6.5z" fill="currentColor" stroke="none"/>'),
  next: s('<path d="M5 5.5v13l9-6.5zM17 5v14" />'),
  flame: s('<path d="M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.2 2-4.2.2 1.4.9 2.2 1.8 2.5C10.2 8.6 10.6 5.6 12 3z"/>'),
  target: s('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/>'),
  box: s('<rect x="4" y="4" width="16" height="16" rx="3.5"/><circle cx="4" cy="20" r="1.8" fill="currentColor" stroke="none"/>'),
  eye: s('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/>'),
  eyeoff: s('<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><path d="M4 4l16 16"/>'),
  voice: s('<path d="M4 5.5h16v10H9.5L5 19.5v-4H4z"/><path d="M8.5 10.5h7"/>'),
  pen: s('<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>'),
  book: s('<path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M9 9h6M9 13h6"/>'),
  wave: s('<path d="M3 12c2-4 4-4 6 0s4 4 6 0 4-4 6 0"/>'),
  dot: s('<circle cx="12" cy="12" r="3" fill="currentColor" stroke="none"/>'),
  leaf: s('<path d="M5 19c0-8 5-14 15-14 0 9-5 15-13 15M5 19l8-8"/>'),
};

export function enso(size, opacity, extra = "") {
  return `<svg class="enso" width="${size}" height="${size}" viewBox="0 0 200 200" aria-hidden="true" style="opacity:${opacity};${extra}"><path d="M110 22C52 14 18 62 24 112c6 52 58 80 102 62 36-14 54-48 50-84" fill="none" stroke="#2B2926" stroke-width="15" stroke-linecap="round"/><path d="M104 30C58 26 30 66 34 108c5 42 50 66 88 52" fill="none" stroke="#2B2926" stroke-width="6" stroke-linecap="round" opacity="0.5"/></svg>`;
}
