// The demo watch on the page: the canvas, the render loop, the buttons and keys, and the messages
// around it. Screens slide in and out like on the real watch.

import { state, hooks, tick } from "./engine.js";
import { ui, viewHooks, press, HINTS } from "./views.js";
import { drawScreen } from "./screens.js";
import { SIZE, CX, CY, FONT, setContext, fontsChanged } from "./draw.js";

const canvas = document.getElementById("screen");
const watch = document.getElementById("watch");
const hintLine = document.getElementById("hint");
const toast = document.getElementById("toast");
const ctx = canvas.getContext("2d");
setContext(ctx);

const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---- messages ----

let toastTimer;
hooks.say = (message) => {
  toast.textContent = message;
  toast.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("on"), 4200);
};

hooks.buzz = (message) => {
  watch.classList.remove("buzz");
  void watch.offsetWidth; // restart the animation
  watch.classList.add("buzz");
  try { navigator.vibrate?.([200, 100, 200]); } catch (e) { /* not allowed here */ }
  hooks.say("Bzzz: " + message + ". On the watch it buzzes even when you've left the app.");
};

const showHint = () => { hintLine.textContent = HINTS[ui.view]; };

// ---- slide transitions ----

// Where a new screen comes from: "up" = it slides up from the bottom (Garmin's SLIDE_UP).
const FROM = { up: [0, 1], down: [0, -1], left: [1, 0], right: [-1, 0] };
const SLIDE_MS = 340;
let slide = null; // { picture of the old screen, direction, start time }

viewHooks.opened = (direction) => {
  showHint();
  if (reducedMotion || !FROM[direction]) return;
  const old = document.createElement("canvas");
  old.width = canvas.width;
  old.height = canvas.height;
  old.getContext("2d").drawImage(canvas, 0, 0);
  slide = { old, direction: FROM[direction], start: performance.now() };
};

const easeOut = (t) => 1 - Math.pow(1 - t, 4);

function render(now) {
  const scale = canvas.width / SIZE;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.setTransform(scale, 0, 0, scale, 0, 0);
  ctx.save();
  ctx.beginPath();
  ctx.arc(CX, CY, SIZE / 2, 0, Math.PI * 2);
  ctx.clip();
  ctx.fillStyle = "#000";
  ctx.fillRect(0, 0, SIZE, SIZE);
  ctx.lineCap = "butt";

  if (slide) {
    const t = Math.min(1, (now - slide.start) / SLIDE_MS), p = easeOut(t);
    const [dx, dy] = slide.direction;
    // the old screen leaves...
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1 - 0.5 * p;
    ctx.drawImage(slide.old, -dx * p * canvas.width, -dy * p * canvas.height);
    ctx.restore();
    // ...as the new one comes in
    ctx.translate(dx * (1 - p) * SIZE, dy * (1 - p) * SIZE);
    if (t >= 1) slide = null;
  }
  drawScreen(ui.view);
  ctx.restore();
}

// ---- the loop: time, list scrolling, drawing ----

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.25, (now - last) / 1000);
  last = now;
  tick(dt);
  // lists glide to the selected row
  const gap = ui.selected - ui.scroll;
  ui.scroll = Math.abs(gap) < 0.002 || reducedMotion ? ui.selected : ui.scroll + gap * (1 - Math.exp(-dt * 16));
  render(now);
  requestAnimationFrame(frame);
}

// ---- buttons and keys ----

// The style can also change in the watch's settings: keep the chips beside it in step.
function pressButton(key) {
  press(key);
  syncChips();
}

const buttons = {};
document.querySelectorAll("[data-key]").forEach((button) => {
  buttons[button.dataset.key] = button;
  button.addEventListener("click", () => pressButton(button.dataset.key));
});

canvas.addEventListener("click", () => hooks.say("Taps on the screen are ignored, on the watch too: use the buttons."));

const KEYS = { ArrowUp: "up", ArrowDown: "down", Enter: "start", " ": "start", Escape: "back", Backspace: "back" };
watch.addEventListener("keydown", (e) => {
  const key = KEYS[e.key];
  if (!key) return;
  e.preventDefault();
  // show the button going in, as if it had been pressed
  buttons[key].classList.add("pressed");
  setTimeout(() => buttons[key].classList.remove("pressed"), 140);
  pressButton(key);
});

// ---- style and speed, beside the watch ----

function syncChips() {
  document.querySelectorAll("[data-style]").forEach((b) => b.setAttribute("aria-pressed", String(+b.dataset.style === state.settings.style)));
  document.querySelectorAll("[data-speed]").forEach((b) => b.setAttribute("aria-pressed", String(+b.dataset.speed === state.speed)));
}
document.querySelectorAll("[data-style]").forEach((b) => b.addEventListener("click", () => {
  state.settings.style = +b.dataset.style;
  syncChips();
}));
document.querySelectorAll("[data-speed]").forEach((b) => b.addEventListener("click", () => {
  state.speed = +b.dataset.speed;
  syncChips();
}));
// ---- size: sharp on any screen ----

function resize() {
  const pixels = Math.round(canvas.clientWidth * (window.devicePixelRatio || 1));
  if (pixels && canvas.width !== pixels) {
    canvas.width = canvas.height = pixels;
    fontsChanged();
  }
}
const sizeWatcher = new ResizeObserver(resize);
sizeWatcher.observe(canvas);

// The canvas only uses a font once it's loaded.
Promise.all(Object.values(FONT).map((f) => document.fonts.load(f, "0123456789:ABCabc")))
  .then(fontsChanged, () => {});

syncChips();
showHint();
resize();
requestAnimationFrame(frame);
