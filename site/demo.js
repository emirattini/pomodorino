// The watch demo: a port of the app's screens (source/styles/EmberStyle.mc, DrainStyle.mc,
// TaskViews.mc, StatsView.mc, Menus.mc) to a canvas, with made-up tasks and time running 60x faster.
// Nothing here talks to a server.
{
const IDLE = 0, FOCUS = 1, SHORT = 2, LONG = 3;
const C = { focus: 0xFF5544, short: 0x44DD88, long: 0x44AAFF, goal: 0xFFB000, dim: 0x8A8A8A, white: 0xFFFFFF, lt: 0xCCCCCC };
const hex = c => "#" + c.toString(16).padStart(6, "0");
const shade = (c, f) => (Math.floor(((c >> 16) & 255) * f) << 16) | (Math.floor(((c >> 8) & 255) * f) << 8) | Math.floor((c & 255) * f);
const phaseColor = p => p === SHORT ? C.short : p === LONG ? C.long : C.focus;
const phaseName = p => ["POMODORINO", "FOCUS", "SHORT BREAK", "LONG BREAK"][p];
const spaced = s => s.split("").join(" ");
const two = n => String(n).padStart(2, "0");
const fmt = sec => two(Math.floor(sec / 60)) + ":" + two(sec % 60);
const minText = m => m >= 60 ? Math.floor(m / 60) + "h " + two(m % 60) + "'" : m + "'";

const F = {
  xt: "25px NotoW", small: "31px NotoW", medium: "40px NotoW", row: "34px NotoW", sub: "26px NotoW",
  ember: "84px EmberT", arc: "19px ArcW", drainT: "104px Bebas", drainL: "30px Bebas"
};

// ---- state ----
const st = {
  settings: { focus: 25, short: 5, long: 15, every: 4, goal: 8, auto: false, style: 0 },
  ph: IDLE, run: false, rdy: true, rem: 25 * 60, cyc: 2,
  today: 2, streak: 4, week: [6, 8, 4, 9, 8, 7],
  tasks: [
    { id: 1, title: "Write the Q4 report", project: "Work", est: 50, spent: 20 },
    { id: 2, title: "Review pull requests", project: "Work", est: 25, spent: 0 },
    { id: 3, title: "Study Rust: ownership chapter", project: "Learning", est: 75, spent: 45 },
    { id: 4, title: "Plan tomorrow", project: "Personal", est: 0, spent: 0 }
  ],
  task: null,          // { t: task, foc: seconds of focus this session, pom }
  view: "tasks", sel: 0, choice: 0, back: null, picker: null,
  clock: Date.now() / 1000, speed: 60
};
const total = () => (st.ph === SHORT ? st.settings.short : st.ph === LONG ? st.settings.long : st.settings.focus) * 60;
const paused = () => !st.run && !st.rdy;

// ---- the timer (PomoEngine.mc) ----
function advance(auto) {
  const ended = st.ph;
  let next = FOCUS;
  if (ended === FOCUS) {
    st.cyc++;
    next = st.cyc >= st.settings.every ? LONG : SHORT;
  } else if (ended === LONG) {
    st.cyc = 0;
  }
  st.ph = next;
  st.rem = total();
  st.run = auto;
  st.rdy = !auto;
}

function tick(dt) {
  const d = dt * st.speed;
  st.clock += d;
  if (!st.run) return;
  st.rem -= d;
  if (st.ph === FOCUS && st.task) st.task.foc += d;
  if (st.rem > 0) return;
  const ended = st.ph;
  if (ended === FOCUS) {
    st.today++;
    if (st.task) st.task.pom++;
  }
  advance(st.settings.auto && ended !== LONG);
  buzz(ended === FOCUS ? (st.ph === LONG ? "Long break!" : "Break time") : "Back to focus");
}

function toggle() {
  if (st.run) {
    st.run = false; st.rdy = false;
  } else {
    if (st.ph === IDLE) { st.ph = FOCUS; st.rem = total(); }
    st.run = true; st.rdy = false;
  }
}

function stopAll() { st.ph = IDLE; st.run = false; st.rdy = true; st.rem = st.settings.focus * 60; st.cyc = 0; }

const focusMin = () => st.task ? Math.round(st.task.foc / 60) : 0;

function finishTask(complete) {
  const t = st.task.t;
  t.spent += focusMin();
  if (complete) st.tasks = st.tasks.filter(x => x !== t);
  st.task = null;
  stopAll();
  say(complete ? "Completed in Todoist, with a comment of the time spent" : "Time added to the task as a comment");
}

// ---- screens ----
let ctx, capH = {};
function text(x, y, font, s, color, align) {
  ctx.font = font;
  ctx.fillStyle = hex(color);
  ctx.textAlign = align || "center";
  if (capH[font] === undefined) capH[font] = ctx.measureText("H").actualBoundingBoxAscent;
  ctx.fillText(s, x, y + capH[font] / 2);
}
const width = (font, s) => { ctx.font = font; return ctx.measureText(s).width; };
const rad = d => d * Math.PI / 180;
// Clockwise arc of `sweep` degrees from `start` (degrees counter-clockwise from 3 o'clock, as on the watch).
function arcCw(r, start, sweep, pen, color) {
  if (sweep <= 0.3) return;
  ctx.beginPath();
  ctx.lineWidth = pen; ctx.strokeStyle = hex(color);
  if (sweep >= 359.9) ctx.arc(195, 195, r, 0, Math.PI * 2);
  else ctx.arc(195, 195, r, rad(-start), rad(-start + sweep));
  ctx.stroke();
}
const circle = (r, pen, color) => arcCw(r, 90, 360, pen, color);
function dot(x, y, r, color) { ctx.beginPath(); ctx.fillStyle = hex(color); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); }
const px = (r, deg) => 195 + r * Math.cos(rad(deg));
const py = (r, deg) => 195 - r * Math.sin(rad(deg));

// Text along the top (clockwise) or bottom of the circle, like drawRadialText.
function arcLabel(r, s, color, top) {
  ctx.font = F.arc; ctx.fillStyle = hex(color); ctx.textAlign = "center";
  const ws = [...s].map(ch => ctx.measureText(ch).width);
  const totalW = ws.reduce((a, b) => a + b, 0);
  let acc = 0;
  [...s].forEach((ch, i) => {
    const off = (acc + ws[i] / 2 - totalW / 2) / r;
    const th = top ? -Math.PI / 2 + off : Math.PI / 2 - off;
    ctx.save();
    ctx.translate(195 + r * Math.cos(th), 195 + r * Math.sin(th));
    ctx.rotate(top ? th + Math.PI / 2 : th - Math.PI / 2);
    ctx.fillText(ch, 0, 7);
    ctx.restore();
    acc += ws[i];
  });
}

// Up to two lines, balanced when it fits, "…" on the second when it doesn't (Draw.wrap).
function wrap(s, w1, w2) {
  if (width(F.xt, s) <= w1) return [s];
  let greedy = 0, balanced = 0, best = 0;
  for (let i = 1; i < s.length - 1; i++) {
    if (s[i] !== " ") continue;
    const a = width(F.xt, s.slice(0, i)) / w1;
    if (a > 1) break;
    greedy = i;
    const b = width(F.xt, s.slice(i + 1)) / w2, worst = Math.max(a, b);
    if (b <= 1 && (!balanced || worst < best)) { balanced = i; best = worst; }
  }
  const cut = balanced || greedy;
  return cut ? [s.slice(0, cut), fit(F.xt, s.slice(cut + 1), w2, "…")] : [fit(F.xt, s, w1, "…")];
}
function fit(font, s, w, dots) {
  if (width(font, s) <= w) return s;
  let n = s.length - 1;
  while (n > 1 && width(font, s.slice(0, n) + dots) > w) n--;
  return s.slice(0, n) + dots;
}
const chord = (y, r) => { const dy = Math.abs(y - 195); return dy < r ? 2 * Math.sqrt(r * r - dy * dy) - 12 : 0; };

function statusText() {
  if (st.run) {
    const d = new Date((st.clock + st.rem) * 1000);
    return "UNTIL " + d.getHours() + ":" + two(d.getMinutes());
  }
  return paused() ? "PAUSED" : "PRESS START";
}
function statusLine(y, r, font, color) {
  if (!st.task || paused()) return text(195, y, font, statusText(), color);
  const lines = wrap(st.task.t.title, chord(y, r), chord(y + 25, r));
  lines.forEach((l, i) => text(195, y + i * 25, F.xt, l, C.lt));
}

function frame() {
  const t = total(), rem = Math.max(0, Math.ceil(st.rem));
  return { frac: st.ph === IDLE ? 0 : Math.min(1, Math.max(0, (t - st.rem) / t)), rem, color: phaseColor(st.ph) };
}

function ember() {
  const f = frame(), { goal, every } = st.settings;
  // daily goal: one segment per pomodoro
  const span = 360 / goal, gap = goal <= 12 ? 4 : 2.5;
  for (let i = 0; i < goal; i++) arcCw(187, 90 - i * span - gap / 2, span - gap, 7, i < st.today ? C.goal : shade(C.goal, 0.22));
  // session arc: gradient, glow, breathing tip
  const r = 137, pen = 14, bright = st.run ? 1 : 0.55;
  circle(r, pen, shade(f.color, 0.16));
  if (f.frac > 0) {
    const sweep = 360 * f.frac;
    arcCw(r, 90, sweep, pen + 10, shade(f.color, 0.14 * bright));
    const steps = Math.floor(f.frac * 60) + 1;
    for (let i = 0; i < steps; i++) {
      const a0 = 90 - sweep * i / steps;
      arcCw(r, a0, sweep / steps + 0.8, pen, shade(f.color, (0.3 + 0.7 * (i + 1) / steps) * bright));
    }
    dot(195, 195 - r, pen / 2, shade(f.color, 0.3 * bright));
    const tx = px(r, 90 - sweep), ty = py(r, 90 - sweep);
    const halo = st.run && Math.floor(performance.now() / 1000) % 2 === 0 ? 7 : 4;
    dot(tx, ty, pen / 2 + halo, shade(f.color, 0.4 * bright));
    dot(tx, ty, pen / 2 + 1, shade(f.color, bright));
    dot(tx, ty, pen / 4, st.run ? C.white : C.dim);
  }
  arcLabel(162, spaced(phaseName(st.ph)), f.color, true);
  let today = st.today + " / " + goal + " TODAY";
  if (st.streak > 0) today += "  ·  " + st.streak + " DAY STREAK";
  arcLabel(162, today, st.today >= goal ? C.goal : shade(C.goal, 0.8), false);
  // pips: one per pomodoro in the set
  const x0 = 195 - (every - 1) * 11;
  for (let i = 0; i < every; i++) {
    const x = x0 + i * 22, y = 145;
    ctx.lineWidth = 2;
    if (i < st.cyc) { dot(x, y, 8, shade(C.focus, 0.35)); dot(x, y, 5, C.focus); }
    else {
      const cur = i === st.cyc && st.ph === FOCUS;
      ctx.beginPath(); ctx.strokeStyle = hex(cur ? C.focus : shade(C.dim, 0.6)); ctx.arc(x, y, cur ? 6 : 5, 0, Math.PI * 2); ctx.stroke();
      if (cur && st.run) dot(x, y, 2.5, C.focus);
    }
  }
  text(195, 195, F.ember, fmt(f.rem), st.run || st.ph === IDLE ? C.white : C.dim);
  statusLine(245, 124, F.xt, paused() ? f.color : C.dim);
}

function drain() {
  const f = frame(), goal = st.settings.goal;
  const col = st.run || st.ph === IDLE ? f.color : shade(f.color, 0.55);
  circle(186, 3, shade(C.goal, 0.2));
  const gf = Math.min(1, st.today / goal);
  if (gf > 0) { arcCw(186, 90, 360 * gf, 3, C.goal); dot(px(186, 90 - 360 * gf), py(186, 90 - 360 * gf), 5, C.goal); }
  circle(149, 26, shade(col, 0.1));
  const left = 1 - f.frac;
  if (left > 0.002) {
    const start = 90 - 360 * f.frac;
    arcCw(149, start, 360 * left, 26, col);
    dot(px(149, start), py(149, start), 13, col);
    dot(195, 195 - 149, 13, col);
  }
  text(195, 137, F.drainL, phaseName(st.ph), col);
  text(195, 199, F.drainT, fmt(f.rem), st.run || st.ph === IDLE ? C.white : C.dim);
  text(195, 255, F.drainL, st.today + " / " + goal + " TODAY", C.goal);
  statusLine(285, 130, F.drainL, paused() ? col : C.dim);
}

// A Menu2-like list: the selected row in the middle, the title above the first row.
function list(title, rows) {
  const y0 = 195;
  text(195, y0 - (st.sel + 1) * 94 + 4, F.sub, title, C.white);
  rows.forEach((row, i) => {
    const cy = y0 + (i - st.sel) * 94;
    if (cy < -60 || cy > 450) return;
    if (i === st.sel) {
      const g = ctx.createLinearGradient(14, 0, 70, 0);
      g.addColorStop(0, "rgba(40,200,220,.45)"); g.addColorStop(1, "rgba(40,200,220,0)");
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.moveTo(30, cy - 46); ctx.lineTo(80, cy - 46); ctx.lineTo(64, cy + 46); ctx.lineTo(14, cy + 46); ctx.fill();
      ctx.fillStyle = "#33d0e0";
      ctx.beginPath(); ctx.moveTo(30, cy - 46); ctx.lineTo(36, cy - 46); ctx.lineTo(20, cy + 46); ctx.lineTo(14, cy + 46); ctx.fill();
    }
    const sub = row.sub;
    text(48, sub ? cy - 17 : cy, F.row, fit(F.row, row.t, 322, "..."), C.white, "left");
    if (sub) text(48, cy + 20, F.sub, fit(F.sub, sub, 310, "..."), C.white, "left");
  });
}

function taskSub(t) {
  const parts = [t.project];
  if (t.est && t.spent) parts.push(minText(t.spent) + " / " + minText(t.est));
  else if (t.est) parts.push("est " + minText(t.est));
  else if (t.spent) parts.push(minText(t.spent) + " done");
  return parts.join(" · ");
}
const taskRows = () => [...st.tasks.map(t => ({ t: t.title, sub: taskSub(t), task: t })),
  { t: "No task", sub: "Plain pomodoro", id: "none" }, { t: "Refresh", id: "refresh" }];

const STYLES = ["Ember", "Drain"];
const SPECS = { focus: ["Focus", 5, 90, 5, "min"], short: ["Short break", 1, 30, 1, "min"], long: ["Long break", 5, 60, 5, "min"],
  every: ["Long break every", 2, 8, 1, "pomodoros"], goal: ["Daily goal", 1, 30, 1, "pomodoros"] };
function menuRows() {
  const r = [];
  if (st.task) r.push({ t: "Finish task", sub: st.task.t.title, id: "finish" }); else r.push({ t: "Choose task", id: "choose" });
  if (st.ph === SHORT || st.ph === LONG) r.push({ t: "Skip break", sub: "Start focusing now", id: "skip" });
  if (st.ph !== IDLE) {
    r.push({ t: "Restart session", sub: "Reset this timer", id: "restart" });
    if (!st.task) r.push({ t: "Stop", sub: "End the set", id: "stop" });
  }
  r.push({ t: "Statistics", id: "stats" }, { t: "Settings", id: "settings" });
  return r;
}
const settingRows = () => [{ t: "Style", sub: STYLES[st.settings.style], id: "style" },
  ...Object.keys(SPECS).map(k => ({ t: SPECS[k][0], sub: st.settings[k] + " " + SPECS[k][4], id: k })),
  { t: "Auto-start", sub: st.settings.auto ? "On · next session starts itself" : "Off", id: "auto" }];

function summary() {
  const t = st.task.t, session = focusMin(), actual = t.spent + session;
  const lines = wrap(t.title, 234, 234);
  lines.forEach((l, i) => text(195, 66 - (lines.length - 1) * 12.5 + i * 25, F.xt, l, C.white));
  if (t.est) {
    text(120, 113, F.xt, "ESTIMATED", C.dim); text(120, 152, F.medium, minText(t.est), C.white);
    text(270, 113, F.xt, "ACTUAL", C.dim); text(270, 152, F.medium, minText(actual), C.white);
    const d = actual - t.est;
    text(195, 191, F.xt, d === 0 ? "On estimate" : d > 0 ? "+" + minText(d) + " over" : minText(-d) + " under", d > 0 ? C.focus : C.short);
  } else {
    text(195, 113, F.xt, "ACTUAL · NO ESTIMATE", C.dim); text(195, 152, F.medium, minText(actual), C.white);
  }
  const pom = st.task.pom;
  text(195, 224, F.xt, "This session " + minText(session) + " · " + pom + (pom === 1 ? " pomodoro" : " pomodoros"), C.dim);
  choice(273, "Complete task", st.choice === 0);
  choice(324, "Continue later", st.choice === 1);
}
function choice(y, label, sel) {
  if (sel) {
    ctx.lineWidth = 2; ctx.strokeStyle = hex(C.goal);
    ctx.beginPath(); ctx.roundRect(85, y - 21, 220, 42, 21); ctx.stroke();
  }
  text(195, y, F.xt, label, sel ? C.goal : C.lt);
}

function stats() {
  const goal = st.settings.goal, week = [...st.week, st.today];
  const max = Math.max(goal, ...week), base = 245, full = 140, bw = 26, x0 = 62;
  const names = ["S", "M", "T", "W", "T", "F", "S"], dow = new Date().getDay();
  text(195, 45, F.xt, "LAST 7 DAYS", C.dim);
  week.forEach((n, i) => {
    const x = x0 + i * 40, h = Math.round(full * n / max);
    ctx.fillStyle = "#2a2a2a"; ctx.fillRect(x, base - full, bw, full);
    ctx.fillStyle = hex(n >= goal ? C.short : C.focus); ctx.fillRect(x, base - h, bw, h);
    text(x + bw / 2, base - h - 16, F.xt, String(n), i === 6 ? C.white : C.dim);
    text(x + bw / 2, base + 22, F.xt, names[(dow + i + 1) % 7], i === 6 ? C.white : C.dim);
  });
  const gy = base - Math.round(full * goal / max);
  ctx.setLineDash([6, 5]); ctx.lineWidth = 2; ctx.strokeStyle = hex(C.goal);
  ctx.beginPath(); ctx.moveTo(52, gy); ctx.lineTo(338, gy); ctx.stroke(); ctx.setLineDash([]);
  text(195, 304, F.small, "Streak " + st.streak + (st.streak === 1 ? " day" : " days"), C.goal);
  text(195, 343, F.xt, week.reduce((a, b) => a + b, 0) + " in 7 days, goal " + goal, C.dim);
}

function picker() {
  const p = st.picker, s = SPECS[p.key];
  text(195, 90, F.xt, s[0].toUpperCase(), C.dim);
  text(195, 120, F.xt, "▲", p.v < s[2] ? C.goal : shade(C.dim, 0.4));
  text(195, 190, F.drainT, String(p.v), C.white);
  text(195, 255, F.xt, s[4], C.dim);
  text(195, 285, F.xt, "▼", p.v > s[1] ? C.goal : shade(C.dim, 0.4));
  text(195, 335, F.xt, "START save", C.dim);
}

function draw() {
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, cv.width, cv.height);
  const k = cv.width / 390;
  ctx.setTransform(k, 0, 0, k, 0, 0);
  ctx.save();
  ctx.beginPath(); ctx.arc(195, 195, 195, 0, Math.PI * 2); ctx.clip();
  ctx.fillStyle = "#000"; ctx.fillRect(0, 0, 390, 390);
  ctx.lineCap = "butt";
  const v = st.view;
  if (v === "main") (st.settings.style ? drain : ember)();
  else if (v === "tasks") list(st.tasks.length ? "Today" : "No tasks today", taskRows());
  else if (v === "menu") list("Pomodorino", menuRows());
  else if (v === "settings") list("Settings", settingRows());
  else if (v === "summary") summary();
  else if (v === "stats") stats();
  else if (v === "picker") picker();
  ctx.restore();
}

// ---- buttons ----
function open(view, sel) { st.view = view; st.sel = sel || 0; st.choice = 0; hint(); }
function move(d, n) { st.sel = Math.max(0, Math.min(n - 1, st.sel + d)); }

function press(key) {
  if (key === "light") return say("LIGHT turns on the backlight. It does nothing else in Pomodorino.");
  const v = st.view;
  if (v === "main") {
    if (key === "start") toggle();
    else if (key === "up") open("menu");
    else if (key === "down") open("stats");
    else if (key === "back") say("On the watch, BACK leaves the app. The timer keeps going, and the watch buzzes when it ends.");
  } else if (v === "tasks" || v === "menu" || v === "settings") {
    const rows = v === "tasks" ? taskRows() : v === "menu" ? menuRows() : settingRows();
    if (key === "up") move(-1, rows.length);
    else if (key === "down") move(1, rows.length);
    else if (key === "back") open(v === "settings" ? "menu" : "main", v === "settings" ? menuRows().findIndex(r => r.id === "settings") : 0);
    else if (key === "start") select(v, rows[st.sel]);
  } else if (v === "summary") {
    if (key === "up") st.choice = 0;
    else if (key === "down") st.choice = 1;
    else if (key === "back") open("main");
    else if (key === "start") { finishTask(st.choice === 0); open("tasks"); }
  } else if (v === "stats") {
    if (key === "back" || key === "start") open(st.back || "main", st.backSel), st.back = null;
  } else if (v === "picker") {
    const p = st.picker, s = SPECS[p.key];
    if (key === "up") p.v = Math.min(s[2], p.v + s[3]);
    else if (key === "down") p.v = Math.max(s[1], p.v - s[3]);
    else if (key === "start" || key === "back") {
      if (key === "start") {
        st.settings[p.key] = p.v;
        if (st.rdy && (p.key === "focus" && st.ph <= FOCUS || p.key === "short" && st.ph === SHORT || p.key === "long" && st.ph === LONG)) st.rem = total();
      }
      open("settings", settingRows().findIndex(r => r.id === p.key));
    }
  }
  draw();
}

function select(v, row) {
  if (v === "tasks") {
    if (row.id === "refresh") return say("Today's tasks, fresh from Todoist");
    st.task = row.task ? { t: row.task, foc: 0, pom: 0 } : null;
    open("main");
    if (row.task) say("The timer now runs on “" + row.task.title + "”. Press START.");
  } else if (v === "menu") {
    const id = row.id;
    if (id === "finish") open("summary");
    else if (id === "choose") open("tasks");
    else if (id === "skip") { advance(true); open("main"); }
    else if (id === "restart") { st.run = false; st.rdy = true; st.rem = total(); open("main"); }
    else if (id === "stop") { stopAll(); open("main"); }
    else if (id === "stats") { st.back = "menu"; st.backSel = st.sel; open("stats"); }
    else if (id === "settings") open("settings");
  } else if (v === "settings") {
    if (row.id === "style") { st.settings.style = 1 - st.settings.style; syncChips(); }
    else if (row.id === "auto") st.settings.auto = !st.settings.auto;
    else { st.picker = { key: row.id, v: st.settings[row.id] }; open("picker"); }
  }
}

// ---- around the watch ----
const cv = document.getElementById("screen");
const watch = document.getElementById("watch");
const hintEl = document.getElementById("hint"), toastEl = document.getElementById("toast");
ctx = cv.getContext("2d");
const HINTS = {
  tasks: "Today's tasks from Todoist. UP and DOWN move, START picks one.",
  main: "START starts and pauses. UP opens the menu, DOWN the statistics.",
  menu: "UP and DOWN move, START opens, BACK closes.",
  settings: "START changes a setting, BACK goes back.",
  summary: "Estimate vs actual. UP and DOWN choose, START confirms.",
  stats: "The last 7 days against your goal. BACK goes back.",
  picker: "UP and DOWN change the number, START saves."
};
function hint() { hintEl.textContent = HINTS[st.view]; }
let toastTimer;
function say(s) {
  toastEl.textContent = s;
  toastEl.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.remove("on"), 4200);
}
function buzz(s) {
  watch.classList.remove("buzz"); void watch.offsetWidth; watch.classList.add("buzz");
  try { navigator.vibrate && navigator.vibrate([200, 100, 200]); } catch (e) {}
  say("Bzzz: " + s + ". On the watch it buzzes even when you've left the app.");
}

document.querySelectorAll("[data-key]").forEach(b => b.addEventListener("click", () => { press(b.dataset.key); }));
cv.addEventListener("click", () => say("Taps on the screen are ignored, on the watch too: use the buttons."));
watch.addEventListener("keydown", e => {
  const k = { ArrowUp: "up", ArrowDown: "down", Enter: "start", " ": "start", Escape: "back", Backspace: "back" }[e.key];
  if (k) { e.preventDefault(); press(k); }
});

function syncChips() {
  document.querySelectorAll("[data-style]").forEach(b => b.setAttribute("aria-pressed", String(+b.dataset.style === st.settings.style)));
  document.querySelectorAll("[data-speed]").forEach(b => b.setAttribute("aria-pressed", String(+b.dataset.speed === st.speed)));
}
document.querySelectorAll("[data-style]").forEach(b => b.addEventListener("click", () => { st.settings.style = +b.dataset.style; syncChips(); draw(); }));
document.querySelectorAll("[data-speed]").forEach(b => b.addEventListener("click", () => { st.speed = +b.dataset.speed; syncChips(); }));

function resize() {
  const d = Math.round(cv.clientWidth * (window.devicePixelRatio || 1));
  if (d && cv.width !== d) { cv.width = cv.height = d; capH = {}; }
}
const ro = new ResizeObserver(() => { resize(); draw(); });
ro.observe(cv);
Promise.all(Object.values(F).map(f => document.fonts.load(f, "0123456789:ABC"))).then(() => { capH = {}; draw(); }, () => {});

let last = performance.now();
function loop(now) {
  tick(Math.min(0.25, (now - last) / 1000));
  last = now;
  draw();
  requestAnimationFrame(loop);
}
syncChips(); hint(); resize();
requestAnimationFrame(loop);
}
