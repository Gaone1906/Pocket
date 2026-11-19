const OFFSETS = [0, -32, 34, -64, 66, -98, 100, 180];

function hsl(h, s, l, a = 1) {
  const hue = ((h % 360) + 360) % 360;
  return a === 1 ? `hsl(${hue} ${s}% ${l}%)` : `hsl(${hue} ${s}% ${l}% / ${a})`;
}

function pastel(id, name, hue, factor) {
  const tone = (s, l, a = 1) => hsl(hue, Math.min(100, s * factor), l, a);
  return {
    id,
    name,
    dark: false,
    backdrop: tone(45, 92.5),
    sidebar: tone(42, 89),
    card: tone(55, 96),
    line: tone(30, 81.5),
    ink: tone(34, 16),
    muted: tone(18, 35),
    faint: tone(16, 62),
    accent: tone(48, 54),
    accentInk: tone(52, 32),
    shadow: tone(34, 26, 0.1),
    pill: "rgba(255,255,255,0.85)",
    swatch: tone(46, 84),
    swatchRing: tone(46, 46),
    tints: OFFSETS.map((o) => hsl(hue + o, Math.max(18, Math.min(100, 34 * factor)), o === 0 ? 50 : 56)),
  };
}

const bronze = {
  id: "bronze",
  name: "Bronze",
  dark: true,
  backdrop: "#2B2C30",
  sidebar: "#252629",
  card: "#34353A",
  line: "#46474D",
  ink: "#EDE7DF",
  muted: "#A39D95",
  faint: "#6E6B67",
  accent: "#C8925A",
  accentInk: "#D9A86C",
  shadow: "rgba(0,0,0,0.45)",
  pill: "#404146",
  swatch: "#36373B",
  swatchRing: "#D9A86C",
  tints: ["#C08A52", "#B8704A", "#C9A55A", "#D8C3A0", "#9EA3A8", "#C98F84", "#8A949E", "#D4AF37"],
};

export const THEMES = [
  pastel("sage", "Sage", 145, 1),
  pastel("rose", "Rose", 356, 1),
  pastel("butter", "Butter", 46, 1.15),
  pastel("apricot", "Apricot", 24, 1.05),
  pastel("sky", "Sky", 205, 1),
  pastel("lavender", "Lavender", 262, 0.95),
  pastel("blush", "Blush", 328, 0.9),
  pastel("stone", "Stone", 32, 0.28),
  bronze,
];

export function theme(id) {
  return THEMES.find((t) => t.id === id) || (id && id !== "sage" ? bronze : THEMES[0]);
}

export function apply(id) {
  const t = theme(id);
  const root = document.documentElement.style;
  const map = {
    "--backdrop": t.backdrop,
    "--sidebar": t.sidebar,
    "--card": t.card,
    "--line": t.line,
    "--ink": t.ink,
    "--muted": t.muted,
    "--faint": t.faint,
    "--accent": t.accent,
    "--accent-ink": t.accentInk,
    "--shadow": t.shadow,
    "--pill": t.pill,
  };
  for (const k in map) root.setProperty(k, map[k]);
  t.tints.forEach((c, i) => root.setProperty(`--tint-${i}`, c));
  document.documentElement.dataset.dark = t.dark ? "1" : "0";
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", t.backdrop);
  return t;
}
