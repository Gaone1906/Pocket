import { reduceMotion } from "./util.js";

export const COMMIT = 110;
const HOLD_MS = 600;
const SLOP = 8;

function clamp(v) {
  return Math.max(0, Math.min(1, v));
}

export function pose(el, dx, dy, up) {
  const vertical = up && dy < 0 && Math.abs(dy) > Math.abs(dx);
  const y = up ? Math.min(dy, 0) : dy * 0.15;
  el.style.transform = `translate(${dx}px, ${y}px) rotate(${dx / 18}deg)`;
  const set = (name, v) => {
    const s = el.querySelector(`[data-stamp="${name}"]`);
    if (s) s.style.opacity = String(v);
  };
  set("yes", vertical ? 0 : clamp(dx / 90));
  set("no", vertical ? 0 : clamp(-dx / 90));
  set("seen", vertical ? clamp(-dy / 90) : 0);
}

export function springBack(el) {
  el.style.transition = "transform .25s ease";
  pose(el, 0, 0, true);
}

export function fly(el, dir) {
  const w = window.innerWidth || 400;
  const h = window.innerHeight || 800;
  const quick = reduceMotion();
  el.style.transition = quick ? "none" : "transform .3s ease-in, opacity .3s ease-in";
  const stamp = { right: "yes", left: "no", up: "seen" }[dir];
  el.querySelectorAll("[data-stamp]").forEach((s) => (s.style.opacity = s.dataset.stamp === stamp ? "1" : "0"));
  if (dir === "right") el.style.transform = `translate(${w * 1.2}px, 40px) rotate(24deg)`;
  if (dir === "left") el.style.transform = `translate(${-w * 1.2}px, 40px) rotate(-24deg)`;
  if (dir === "up") el.style.transform = `translate(0, ${-h * 1.1}px)`;
  el.style.opacity = "0";
  return new Promise((resolve) => setTimeout(resolve, quick ? 0 : 280));
}

export function attach(el, { up = false, onHold = null, onStart = null, onRelease }) {
  let sx = null;
  let sy = 0;
  let dx = 0;
  let dy = 0;
  let moved = false;
  let timer = null;

  el.addEventListener("pointerdown", (e) => {
    if (e.button !== 0 || e.target.closest("button, a, input, .hook")) return;
    sx = e.clientX;
    sy = e.clientY;
    dx = dy = 0;
    moved = false;
    try {
      el.setPointerCapture(e.pointerId);
    } catch (err) {}
    el.style.transition = "none";
    if (onStart) onStart();
    clearTimeout(timer);
    if (onHold)
      timer = setTimeout(() => {
        if (moved || sx == null) return;
        sx = null;
        pose(el, 0, 0, up);
        onHold();
      }, HOLD_MS);
  });

  el.addEventListener("pointermove", (e) => {
    if (sx == null) return;
    dx = e.clientX - sx;
    dy = e.clientY - sy;
    if (Math.abs(dx) > SLOP || Math.abs(dy) > SLOP) {
      moved = true;
      clearTimeout(timer);
    }
    if (moved) pose(el, dx, dy, up);
  });

  const end = (cancelled) => {
    clearTimeout(timer);
    if (sx == null) return;
    sx = null;
    let dir = null;
    if (!cancelled) {
      if (up && dy < -COMMIT && Math.abs(dy) > Math.abs(dx)) dir = "up";
      else if (Math.abs(dx) > COMMIT) dir = dx > 0 ? "right" : "left";
    }
    if (!dir) springBack(el);
    onRelease(dir);
  };
  el.addEventListener("pointerup", () => end(false));
  el.addEventListener("pointercancel", () => end(true));
  el.addEventListener("lostpointercapture", () => end(true));
}
