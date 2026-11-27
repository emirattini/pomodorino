// Each screen of the watch, drawn on the 390 x 390 canvas. Ports of source/styles/EmberStyle.mc,
// DrainStyle.mc, TaskViews.mc and StatsView.mc.

import { state, IDLE, FOCUS, SHORT, LONG, isPaused, sessionLength, sessionMinutes } from "./engine.js";
import { ui, rowsOf, SETTINGS, minutesText } from "./views.js";
import {
  CX, CY, COLOR, FONT, context, shade, hex, text, arc, ring, dot, circleOutline, arcText,
  pointX, pointY, wrap, fit, chord
} from "./draw.js";

const phaseColor = (p) => p === SHORT ? COLOR.short : p === LONG ? COLOR.long : COLOR.focus;
const phaseName = (p) => ["POMODORINO", "FOCUS", "SHORT BREAK", "LONG BREAK"][p];
const spaced = (s) => s.split("").join(" ");
const two = (n) => String(n).padStart(2, "0");
const clockText = (sec) => two(Math.floor(sec / 60)) + ":" + two(sec % 60);

// What the timer styles need, worked out once per frame.
function timerFrame() {
  const total = sessionLength();
  const progress = state.phase === IDLE ? 0 : Math.min(1, Math.max(0, (total - state.remaining) / total));
  return { progress, seconds: Math.max(0, Math.ceil(state.remaining)), color: phaseColor(state.phase) };
}

// "UNTIL 14:25", "PAUSED" or "PRESS START"
function statusText() {
  if (state.running) {
    const end = new Date((state.clock + state.remaining) * 1000);
    return "UNTIL " + end.getHours() + ":" + two(end.getMinutes());
  }
  return isPaused() ? "PAUSED" : "PRESS START";
}

// The status line, or the task's title (on up to two lines) while working on a task.
function statusLine(y, radius, font, color) {
  if (!state.current || isPaused()) return text(CX, y, font, statusText(), color);
  const lines = wrap(state.current.task.title, chord(y, radius), chord(y + 25, radius));
  lines.forEach((line, i) => text(CX, y + i * 25, FONT.xtiny, line, COLOR.light));
}

const todayText = () => state.today + " / " + state.settings.goal + " TODAY";

// ---- Ember: gradient arc with a breathing tip, a segment per pomodoro of the daily goal ----
function ember() {
  const f = timerFrame(), { goal, every } = state.settings;

  const span = 360 / goal, gap = goal <= 12 ? 4 : 2.5;
  for (let i = 0; i < goal; i++) {
    arc(187, 90 - i * span - gap / 2, span - gap, 7, i < state.today ? COLOR.goal : shade(COLOR.goal, 0.22));
  }

  const r = 137, pen = 14, bright = state.running ? 1 : 0.55;
  ring(r, pen, shade(f.color, 0.16));
  if (f.progress > 0) {
    const sweep = 360 * f.progress;
    arc(r, 90, sweep, pen + 10, shade(f.color, 0.14 * bright)); // glow
    const steps = Math.floor(f.progress * 60) + 1;               // dark at the start, bright at the tip
    for (let i = 0; i < steps; i++) {
      arc(r, 90 - sweep * i / steps, sweep / steps + 0.8, pen, shade(f.color, (0.3 + 0.7 * (i + 1) / steps) * bright));
    }
    dot(CX, CY - r, pen / 2, shade(f.color, 0.3 * bright));
    const x = pointX(r, 90 - sweep), y = pointY(r, 90 - sweep);
    const halo = state.running && Math.floor(performance.now() / 1000) % 2 === 0 ? 7 : 4;
    dot(x, y, pen / 2 + halo, shade(f.color, 0.4 * bright));
    dot(x, y, pen / 2 + 1, shade(f.color, bright));
    dot(x, y, pen / 4, state.running ? COLOR.white : COLOR.dim);
  }

  arcText(162, spaced(phaseName(state.phase)), f.color, true);
  let bottom = todayText();
  if (state.streak > 0) bottom += "  ·  " + state.streak + " DAY STREAK";
  arcText(162, bottom, state.today >= goal ? COLOR.goal : shade(COLOR.goal, 0.8), false);

  // one pip per pomodoro in the set
  const x0 = CX - (every - 1) * 11;
  for (let i = 0; i < every; i++) {
    const x = x0 + i * 22, y = 145;
    if (i < state.cycle) {
      dot(x, y, 8, shade(COLOR.focus, 0.35));
      dot(x, y, 5, COLOR.focus);
    } else if (i === state.cycle && state.phase === FOCUS) {
      circleOutline(x, y, 6, 2, COLOR.focus);
      if (state.running) dot(x, y, 2.5, COLOR.focus);
    } else {
      circleOutline(x, y, 5, 2, shade(COLOR.dim, 0.6));
    }
  }

  text(CX, CY, FONT.emberTimer, clockText(f.seconds), state.running || state.phase === IDLE ? COLOR.white : COLOR.dim);
  statusLine(245, 124, FONT.xtiny, isPaused() ? f.color : COLOR.dim);
}

// ---- Drain: a thick ring that drains away, bold condensed type ----
function drain() {
  const f = timerFrame(), goal = state.settings.goal;
  const color = state.running || state.phase === IDLE ? f.color : shade(f.color, 0.55);

  ring(186, 3, shade(COLOR.goal, 0.2));
  const done = Math.min(1, state.today / goal);
  if (done > 0) {
    arc(186, 90, 360 * done, 3, COLOR.goal);
    dot(pointX(186, 90 - 360 * done), pointY(186, 90 - 360 * done), 5, COLOR.goal);
  }

  ring(149, 26, shade(color, 0.1));
  const left = 1 - f.progress;
  if (left > 0.002) {
    const start = 90 - 360 * f.progress;
    arc(149, start, 360 * left, 26, color);
    dot(pointX(149, start), pointY(149, start), 13, color);
    dot(CX, CY - 149, 13, color);
  }

  text(CX, 137, FONT.drainLabel, phaseName(state.phase), color);
  text(CX, 199, FONT.drainTimer, clockText(f.seconds), state.running || state.phase === IDLE ? COLOR.white : COLOR.dim);
  text(CX, 255, FONT.drainLabel, todayText(), COLOR.goal);
  statusLine(285, 130, FONT.drainLabel, isPaused() ? color : COLOR.dim);
}

// ---- a list like the watch's menus: the selected row stays in the middle ----
const ROW = 94;

function list(title) {
  const ctx = context(), rows = rowsOf(ui.view);
  text(CX, CY - (ui.scroll + 1) * ROW + 4, FONT.rowSub, title, COLOR.white);
  rows.forEach((row, i) => {
    const y = CY + (i - ui.scroll) * ROW;
    if (y < -60 || y > 450) return;
    if (i === ui.selected) {
      // the slanted accent on the left of the selected row
      const glow = ctx.createLinearGradient(14, 0, 70, 0);
      glow.addColorStop(0, "rgba(40,200,220,.45)");
      glow.addColorStop(1, "rgba(40,200,220,0)");
      ctx.fillStyle = glow;
      ctx.beginPath(); ctx.moveTo(30, y - 46); ctx.lineTo(80, y - 46); ctx.lineTo(64, y + 46); ctx.lineTo(14, y + 46); ctx.fill();
      ctx.fillStyle = "#33d0e0";
      ctx.beginPath(); ctx.moveTo(30, y - 46); ctx.lineTo(36, y - 46); ctx.lineTo(20, y + 46); ctx.lineTo(14, y + 46); ctx.fill();
    }
    text(48, row.subtitle ? y - 17 : y, FONT.row, fit(FONT.row, row.title, 322, "..."), COLOR.white, "left");
    if (row.subtitle) text(48, y + 20, FONT.rowSub, fit(FONT.rowSub, row.subtitle, 310, "..."), COLOR.white, "left");
  });
}

// ---- end of a task: estimated vs actual ----
function choice(y, label, selected) {
  if (selected) {
    const ctx = context();
    ctx.lineWidth = 2;
    ctx.strokeStyle = hex(COLOR.goal);
    ctx.beginPath(); ctx.roundRect(85, y - 21, 220, 42, 21); ctx.stroke();
  }
  text(CX, y, FONT.xtiny, label, selected ? COLOR.goal : COLOR.light);
}

function summary() {
  const { task, pomodoros } = state.current, session = sessionMinutes(), actual = task.spent + session;

  const lines = wrap(task.title, 234, 234);
  lines.forEach((line, i) => text(CX, 66 - (lines.length - 1) * 12.5 + i * 25, FONT.xtiny, line, COLOR.white));

  if (task.estimate) {
    text(120, 113, FONT.xtiny, "ESTIMATED", COLOR.dim);
    text(120, 152, FONT.medium, minutesText(task.estimate), COLOR.white);
    text(270, 113, FONT.xtiny, "ACTUAL", COLOR.dim);
    text(270, 152, FONT.medium, minutesText(actual), COLOR.white);
    const diff = actual - task.estimate;
    const line = diff === 0 ? "On estimate" : diff > 0 ? "+" + minutesText(diff) + " over" : minutesText(-diff) + " under";
    text(CX, 191, FONT.xtiny, line, diff > 0 ? COLOR.focus : COLOR.short);
  } else {
    text(CX, 113, FONT.xtiny, "ACTUAL · NO ESTIMATE", COLOR.dim);
    text(CX, 152, FONT.medium, minutesText(actual), COLOR.white);
  }
  text(CX, 224, FONT.xtiny, "This session " + minutesText(session) + " · " + pomodoros + (pomodoros === 1 ? " pomodoro" : " pomodoros"), COLOR.dim);

  choice(273, "Complete task", ui.choice === 0);
  choice(324, "Continue later", ui.choice === 1);
}

// ---- statistics: the last 7 days ----
function stats() {
  const ctx = context(), goal = state.settings.goal, week = [...state.week, state.today];
  const max = Math.max(goal, ...week), base = 245, full = 140, barWidth = 26, x0 = 62;
  const days = ["S", "M", "T", "W", "T", "F", "S"], todayIndex = new Date().getDay();

  text(CX, 45, FONT.xtiny, "LAST 7 DAYS", COLOR.dim);
  week.forEach((count, i) => {
    const x = x0 + i * 40, h = Math.round(full * count / max), isToday = i === 6;
    ctx.fillStyle = "#2a2a2a";
    ctx.fillRect(x, base - full, barWidth, full);
    ctx.fillStyle = hex(count >= goal ? COLOR.short : COLOR.focus);
    ctx.fillRect(x, base - h, barWidth, h);
    text(x + barWidth / 2, base - h - 16, FONT.xtiny, String(count), isToday ? COLOR.white : COLOR.dim);
    text(x + barWidth / 2, base + 22, FONT.xtiny, days[(todayIndex + i + 1) % 7], isToday ? COLOR.white : COLOR.dim);
  });

  const goalY = base - Math.round(full * goal / max);
  ctx.setLineDash([6, 5]);
  ctx.lineWidth = 2;
  ctx.strokeStyle = hex(COLOR.goal);
  ctx.beginPath(); ctx.moveTo(52, goalY); ctx.lineTo(338, goalY); ctx.stroke();
  ctx.setLineDash([]);

  text(CX, 304, FONT.small, "Streak " + state.streak + (state.streak === 1 ? " day" : " days"), COLOR.goal);
  text(CX, 343, FONT.xtiny, week.reduce((a, b) => a + b, 0) + " in 7 days, goal " + goal, COLOR.dim);
}

// ---- changing a number setting ----
function picker() {
  const { key, value } = ui.picker, [title, min, max, , unit] = SETTINGS[key];
  text(CX, 90, FONT.xtiny, title.toUpperCase(), COLOR.dim);
  text(CX, 120, FONT.xtiny, "▲", value < max ? COLOR.goal : shade(COLOR.dim, 0.4));
  text(CX, 190, FONT.drainTimer, String(value), COLOR.white);
  text(CX, 255, FONT.xtiny, unit, COLOR.dim);
  text(CX, 285, FONT.xtiny, "▼", value > min ? COLOR.goal : shade(COLOR.dim, 0.4));
  text(CX, 335, FONT.xtiny, "START save", COLOR.dim);
}

// Draws one screen. The caller has cleared and clipped the canvas.
export function drawScreen(view) {
  switch (view) {
    case "main": return (state.settings.style === 1 ? drain : ember)();
    case "tasks": return list(state.tasks.length ? "Today" : "No tasks today");
    case "menu": return list("Pomodorino");
    case "settings": return list("Settings");
    case "summary": return summary();
    case "stats": return stats();
    case "picker": return picker();
  }
}
