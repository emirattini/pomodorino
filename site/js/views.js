// The watch's screens and what each button does on them (MainView.mc, Menus.mc, TaskViews.mc).

import {
  state, hooks, IDLE, isBreak, advance, toggle, restart, stopAll,
  startTask, finishTask, setSetting
} from "./engine.js";

export const STYLES = ["Ember", "Drain"];

// Number settings: [title, min, max, step, unit]
export const SETTINGS = {
  focus: ["Focus", 5, 90, 5, "min"],
  short: ["Short break", 1, 30, 1, "min"],
  long: ["Long break", 5, 60, 5, "min"],
  every: ["Long break every", 2, 8, 1, "pomodoros"],
  goal: ["Daily goal", 1, 30, 1, "pomodoros"]
};

export const ui = {
  view: "tasks",  // the app opens on today's tasks
  selected: 0,    // row in a list
  scroll: 0,      // where the list is drawn: follows `selected` smoothly
  choice: 0,      // 0 or 1 on the summary
  picker: null,   // { key, value } while changing a number
  statsBack: null // where BACK goes from the statistics
};

// Set by watch.js: called when the screen changes, with the direction it slides in from.
export const viewHooks = { opened: (direction) => {} };

function open(view, direction, selected = 0) {
  ui.view = view;
  ui.selected = ui.scroll = selected;
  ui.choice = 0;
  viewHooks.opened(direction);
}

// ---- list rows ----

const minutes = (m) => m >= 60 ? Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "'" : m + "'";
export { minutes as minutesText };

// "Work · 20' / 50'" (spent / estimate), "Work · est 25'" or "Work · 15' done"
function taskSubtitle(t) {
  const parts = [t.project];
  if (t.estimate && t.spent) parts.push(minutes(t.spent) + " / " + minutes(t.estimate));
  else if (t.estimate) parts.push("est " + minutes(t.estimate));
  else if (t.spent) parts.push(minutes(t.spent) + " done");
  return parts.join(" · ");
}

export function taskRows() {
  return [
    ...state.tasks.map((t) => ({ title: t.title, subtitle: taskSubtitle(t), task: t })),
    { title: "No task", subtitle: "Plain pomodoro", id: "none" },
    { title: "Refresh", id: "refresh" }
  ];
}

export function menuRows() {
  const rows = [];
  if (state.current) rows.push({ title: "Finish task", subtitle: state.current.task.title, id: "finish" });
  else rows.push({ title: "Choose task", id: "choose" });
  if (isBreak()) rows.push({ title: "Skip break", subtitle: "Start focusing now", id: "skip" });
  if (state.phase !== IDLE) {
    rows.push({ title: "Restart session", subtitle: "Reset this timer", id: "restart" });
    if (!state.current) rows.push({ title: "Stop", subtitle: "End the set", id: "stop" });
  }
  rows.push({ title: "Statistics", id: "stats" }, { title: "Settings", id: "settings" });
  return rows;
}

export function settingRows() {
  const s = state.settings;
  return [
    { title: "Style", subtitle: STYLES[s.style], id: "style" },
    ...Object.entries(SETTINGS).map(([key, spec]) => ({ title: spec[0], subtitle: s[key] + " " + spec[4], id: key })),
    { title: "Auto-start", subtitle: s.auto ? "On · next session starts itself" : "Off", id: "auto" }
  ];
}

const LISTS = { tasks: taskRows, menu: menuRows, settings: settingRows };
export const rowsOf = (view) => LISTS[view]();
const indexOf = (rows, id) => Math.max(0, rows.findIndex((r) => r.id === id));

// ---- buttons ----

const HANDLERS = {
  main(key) {
    if (key === "start") toggle();
    else if (key === "up") open("menu", "up");
    else if (key === "down") { ui.statsBack = "main"; open("stats", "up"); }
    else if (key === "back") hooks.say("On the watch, BACK leaves the app. The timer keeps going, and the watch buzzes when it ends.");
  },

  tasks: (key) => listKey(key, () => open("main", "down")),
  menu: (key) => listKey(key, () => open("main", "down")),
  settings: (key) => listKey(key, () => open("menu", "right", indexOf(menuRows(), "settings"))),

  summary(key) {
    if (key === "up") ui.choice = 0;
    else if (key === "down") ui.choice = 1;
    else if (key === "back") open("main", "right");
    else if (key === "start") { finishTask(ui.choice === 0); open("tasks", "left"); }
  },

  stats(key) {
    if (key !== "back" && key !== "start") return;
    if (ui.statsBack === "menu") open("menu", "right", indexOf(menuRows(), "stats"));
    else open("main", "down");
  },

  picker(key) {
    const p = ui.picker, [, min, max, step] = SETTINGS[p.key];
    if (key === "up") p.value = Math.min(max, p.value + step);
    else if (key === "down") p.value = Math.max(min, p.value - step);
    else if (key === "start" || key === "back") {
      if (key === "start") setSetting(p.key, p.value);
      open("settings", "right", indexOf(settingRows(), p.key));
    }
  }
};

// UP and DOWN move, START selects, BACK leaves (any list).
function listKey(key, back) {
  const rows = rowsOf(ui.view);
  if (key === "up") ui.selected = Math.max(0, ui.selected - 1);
  else if (key === "down") ui.selected = Math.min(rows.length - 1, ui.selected + 1);
  else if (key === "back") back();
  else if (key === "start") select(rows[ui.selected]);
}

function select(row) {
  if (ui.view === "tasks") {
    if (row.id === "refresh") return hooks.say("Today's tasks, fresh from Todoist");
    startTask(row.task || null);
    open("main", "down");
    if (row.task) hooks.say("The timer now runs on “" + row.task.title + "”. Press START.");
  } else if (ui.view === "menu") {
    const go = {
      finish: () => open("summary", "left"),
      choose: () => open("tasks", "left"),
      skip: () => { advance(true); open("main", "down"); },
      restart: () => { restart(); open("main", "down"); },
      stop: () => { stopAll(); open("main", "down"); },
      stats: () => { ui.statsBack = "menu"; open("stats", "left"); },
      settings: () => open("settings", "left")
    };
    go[row.id]();
  } else if (ui.view === "settings") {
    if (row.id === "style") setSetting("style", 1 - state.settings.style);
    else if (row.id === "auto") setSetting("auto", !state.settings.auto);
    else { ui.picker = { key: row.id, value: state.settings[row.id] }; open("picker", "left"); }
  }
}

export function press(key) {
  if (key === "light") return hooks.say("LIGHT turns on the backlight. It does nothing else in Pomodorino.");
  HANDLERS[ui.view](key);
}

export const HINTS = {
  tasks: "Today's tasks from Todoist. UP and DOWN move, START picks one.",
  main: "START starts and pauses. UP opens the menu, DOWN the statistics.",
  menu: "UP and DOWN move, START opens, BACK closes.",
  settings: "START changes a setting, BACK goes back.",
  summary: "Estimate vs actual. UP and DOWN choose, START confirms.",
  stats: "The last 7 days against your goal. BACK goes back.",
  picker: "UP and DOWN change the number, START saves."
};
