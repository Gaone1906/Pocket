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

function dusk(id, name, ground, glow, depth = 1) {
  const base = (sat, l, a = 1) => hsl(ground, Math.min(100, sat * depth), l, a);
  const lit = (sat, l, a = 1) => hsl(glow, sat, l, a);
  return {
    id,
    name,
    dark: true,
    backdrop: base(46, 11),
    sidebar: base(48, 8.5),
    card: base(36, 15.5),
    line: base(28, 23),
    ink: lit(40, 93),
    muted: base(18, 70),
    faint: base(14, 48),
    accent: lit(62, 76),
    accentInk: lit(70, 81),
    shadow: "rgba(0,0,0,0.45)",
    pill: base(32, 20),
    swatch: base(46, 14),
    swatchRing: lit(70, 81),
    tints: OFFSETS.map((o) => hsl(glow + o, 55, 74)),
  };
}

export const THEMES = [
  pastel("sage", "Sage", 145, 1),
  pastel("rose", "Rose", 356, 1),
  pastel("butter", "Butter", 46, 1.15),
  pastel("apricot", "Apricot", 24, 1.05),
  pastel("sky", "Sky", 205, 1),
  pastel("lavender", "Lavender", 262, 0.95),
  pastel("blush", "Blush", 328, 0.9),
  pastel("stone", "Stone", 32, 0.28),
  pastel("ember", "Ember", 354, 1.55),
  pastel("flint", "Flint", 212, 0.15),
  pastel("bark", "Bark", 28, 0.9),
  dusk("moonlit-sage", "Moonlit Sage", 160, 140),
  dusk("harbour", "Harbour", 218, 24),
  dusk("aurora", "Aurora", 268, 158),
  dusk("nocturne", "Nocturne", 256, 272),
  dusk("candlelight", "Candlelight", 336, 44),
  dusk("mint-cocoa", "Mint Cocoa", 28, 156, 0.7),
  dusk("coral-reef", "Coral Reef", 178, 12),
  dusk("plum-blossom", "Plum Blossom", 302, 334),
];

export function theme(id) {
  return THEMES.find((t) => t.id === id) || THEMES[0];
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
    "--on-accent": t.dark ? t.backdrop : "#fff",
  };
  for (const k in map) root.setProperty(k, map[k]);
  t.tints.forEach((c, i) => root.setProperty(`--tint-${i}`, c));
  document.documentElement.dataset.dark = t.dark ? "1" : "0";
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", t.backdrop);
  return t;
}
