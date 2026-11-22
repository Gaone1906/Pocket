import { $, esc, readSession, writeSession } from "./util.js";
import { caller, createRoom, lobbyView, swipeView, matchedView, noticeView, nameSheet, bindSwipe, nightTitle } from "./room.js";
import { lk } from "./profile.js";

const parts = location.hash.replace(/^#/, "").split(".");
const ref = /^[a-z0-9]{8,40}$/.test(parts[0] || "") ? parts[0] : "";
const code = /^[a-z0-9]{8,20}$/.test(parts[1] || "") ? parts[1] : "";
const key = lk("match." + code);

const ui = { draft: "" };

const room = createRoom({
  call: caller(`https://${ref}.supabase.co/functions/v1/fabula-match`),
  code,
  member: code ? readSession(key) : null,
  save: (c, m) => writeSession(key, c && m ? m : null),
  onChange: render,
});

function render() {
  const app = $("#app");
  if (!ref || !code) {
    app.innerHTML = noticeView("This link doesn't work");
    return;
  }
  const s = room.state;
  if (room.error && !s) {
    app.innerHTML = noticeView(room.error.message);
    return;
  }
  if (!room.member) {
    app.innerHTML = `<main class="screen match"><div class="mhead"><h1>${esc(nightTitle(null))}</h1></div><div class="stack"><div class="plate"></div></div></main>${nameSheet(ui.draft, room.busy)}`;
    const input = $('[data-input="name"]');
    if (input && document.activeElement !== input) {
      input.focus();
      input.setSelectionRange(input.value.length, input.value.length);
    }
    return;
  }
  if (!s) {
    app.innerHTML = `<main class="screen match"><div class="spin"></div></main>`;
    return;
  }
  if (s.matched) app.innerHTML = matchedView(room, { host: false });
  else if (s.started) app.innerHTML = swipeView(room, { host: false });
  else app.innerHTML = lobbyView(room, { host: false });
  bindSwipe(app, room);
}

document.addEventListener("input", (e) => {
  if (e.target.dataset.input !== "name") return;
  ui.draft = e.target.value;
  const b = e.target.form && e.target.form.querySelector("button[type=submit]");
  if (b) b.disabled = !ui.draft.trim() || room.busy;
});

document.addEventListener("submit", (e) => {
  e.preventDefault();
  const name = ui.draft.trim().slice(0, 20);
  if (!name || room.busy) return;
  room.join(name);
});

document.addEventListener("keydown", (e) => {
  if (e.target.matches && e.target.matches("input")) return;
  const act = { ArrowRight: "match-yes", ArrowLeft: "match-no" }[e.key];
  const b = act && $(`[data-act="${act}"]`);
  if (b) {
    e.preventDefault();
    b.click();
  }
});

window.addEventListener("hashchange", () => location.reload());

render();
if (room.member) {
  room.show(true);
} else room.visible = true;
