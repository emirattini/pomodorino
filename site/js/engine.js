// The demo's state and rules: the pomodoro timer (as in source/PomoEngine.mc and PomoController.mc)
// and the task being worked on. No drawing and no DOM here.

export const IDLE = 0, FOCUS = 1, SHORT = 2, LONG = 3;

// What the page around the watch does when something happens. watch.js fills these in.
export const hooks = {
  say: (message) => {},   // show a short message under the watch
  buzz: (message) => {}   // a session ended: shake the watch
};

export const state = {
  settings: { focus: 25, short: 5, long: 15, every: 4, goal: 8, auto: false, style: 0 },

  // the timer
  phase: IDLE,
  running: false,
  ready: true,        // waiting for START at the beginning of a session (false = paused)
  remaining: 25 * 60, // seconds
  cycle: 2,           // pomodoros done in the current set

  // statistics: today, and the 6 days before
  today: 2,
  streak: 4,
  week: [6, 8, 4, 9, 8, 7],

  // made-up Todoist tasks
  tasks: [
    { title: "Write the Q4 report", project: "Work", estimate: 50, spent: 20 },
    { title: "Review pull requests", project: "Work", estimate: 25, spent: 0 },
    { title: "Study Rust: ownership chapter", project: "Learning", estimate: 75, spent: 45 },
    { title: "Plan tomorrow", project: "Personal", estimate: 0, spent: 0 }
  ],
  // the task being worked on: { task, focus: seconds of focus in this session, pomodoros }
  current: null,

  clock: Date.now() / 1000, // the demo's own clock, running as fast as the timer
  speed: 60                 // 60 = one minute per second
};

export const isPaused = () => !state.running && !state.ready;
export const isBreak = () => state.phase === SHORT || state.phase === LONG;

// Length of the current session, in seconds.
export function sessionLength() {
  const s = state.settings;
  const minutes = state.phase === SHORT ? s.short : state.phase === LONG ? s.long : s.focus;
  return minutes * 60;
}

// From one session to the next: focus → short break (or a long one every few), break → focus.
export function advance(autoStart) {
  const ended = state.phase;
  let next = FOCUS;
  if (ended === FOCUS) {
    state.cycle++;
    next = state.cycle >= state.settings.every ? LONG : SHORT;
  } else if (ended === LONG) {
    state.cycle = 0;
  }
  state.phase = next;
  state.remaining = sessionLength();
  state.running = autoStart;
  state.ready = !autoStart;
}

// Moves time forward by `dt` real seconds.
export function tick(dt) {
  const seconds = dt * state.speed;
  state.clock += seconds;
  if (!state.running) return;

  state.remaining -= seconds;
  if (state.phase === FOCUS && state.current) state.current.focus += seconds;
  if (state.remaining > 0) return;

  const ended = state.phase;
  if (ended === FOCUS) {
    state.today++;
    if (state.current) state.current.pomodoros++;
  }
  advance(state.settings.auto && ended !== LONG);
  hooks.buzz(ended === FOCUS ? (state.phase === LONG ? "Long break!" : "Break time") : "Back to focus");
}

// START on the timer: start, pause, resume.
export function toggle() {
  if (state.running) {
    state.running = false;
    state.ready = false;
    return;
  }
  if (state.phase === IDLE) {
    state.phase = FOCUS;
    state.remaining = sessionLength();
  }
  state.running = true;
  state.ready = false;
}

export function restart() {
  state.running = false;
  state.ready = true;
  state.remaining = sessionLength();
}

export function stopAll() {
  state.phase = IDLE;
  state.running = false;
  state.ready = true;
  state.remaining = state.settings.focus * 60;
  state.cycle = 0;
}

// ---- tasks ----

export function startTask(task) {
  state.current = task ? { task, focus: 0, pomodoros: 0 } : null;
}

// Minutes of focus in this session, as the summary shows them.
export const sessionMinutes = () => state.current ? Math.round(state.current.focus / 60) : 0;

// "Complete task" or "Continue later" on the summary.
export function finishTask(complete) {
  const task = state.current.task;
  task.spent += sessionMinutes();
  if (complete) state.tasks = state.tasks.filter((t) => t !== task);
  state.current = null;
  stopAll();
  hooks.say(complete
    ? "Completed in Todoist, with a comment of the time spent"
    : "Time added to the task as a comment");
}

// A setting changed: a session that hasn't started yet takes the new length.
export function setSetting(key, value) {
  state.settings[key] = value;
  const affects = { focus: [IDLE, FOCUS], short: [SHORT], long: [LONG] }[key];
  if (state.ready && affects && affects.includes(state.phase)) state.remaining = sessionLength();
}
