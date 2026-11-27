import Toybox.Lang;
import Toybox.Test;

// PomoEngine: phases, the pomodoro count, auto-start, and rolling the timer forward while the app was closed.
// Everything here works on plain dictionaries, so no Storage is touched.
module PomoEngineTest {

    // The app's defaults, with auto-start as given.
    function settings(auto as Boolean) as Dictionary {
        return { "focus" => 25, "short" => 5, "long" => 15, "every" => 4, "goal" => 8, "auto" => auto, "style" => 0 };
    }

    // A focus session that is running and ends at `end`, after `cyc` pomodoros in this set.
    function focusRunning(end as Number, cyc as Number) as Dictionary {
        return { "ph" => PomoEngine.FOCUS, "run" => true, "end" => end, "rem" => 0, "rdy" => false, "cyc" => cyc };
    }

    (:test)
    function durationsInSeconds(logger as Logger) as Boolean {
        var s = settings(false);
        return Check.eq(logger, "focus", PomoEngine.duration(PomoEngine.FOCUS, s), 1500)
            && Check.eq(logger, "short break", PomoEngine.duration(PomoEngine.SHORT_BREAK, s), 300)
            && Check.eq(logger, "long break", PomoEngine.duration(PomoEngine.LONG_BREAK, s), 900)
            && Check.eq(logger, "idle counts as focus", PomoEngine.duration(PomoEngine.IDLE, s), 1500);
    }

    (:test)
    function focusThenShortBreak(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        PomoEngine.advance(st, settings(false), 1000, false);
        return Check.eq(logger, "phase", st["ph"], PomoEngine.SHORT_BREAK)
            && Check.eq(logger, "pomodoros", st["cyc"], 1)
            && Check.eq(logger, "running", st["run"], false)
            && Check.eq(logger, "ready", st["rdy"], true)
            && Check.eq(logger, "seconds left", st["rem"], 300);
    }

    (:test)
    function fourthFocusThenLongBreak(logger as Logger) as Boolean {
        var st = focusRunning(1000, 3);
        PomoEngine.advance(st, settings(false), 1000, false);
        return Check.eq(logger, "phase", st["ph"], PomoEngine.LONG_BREAK)
            && Check.eq(logger, "pomodoros", st["cyc"], 4)
            && Check.eq(logger, "seconds left", st["rem"], 900);
    }

    (:test)
    function longBreakStartsANewSet(logger as Logger) as Boolean {
        var st = { "ph" => PomoEngine.LONG_BREAK, "run" => true, "end" => 1000, "rem" => 0, "rdy" => false, "cyc" => 4 };
        PomoEngine.advance(st, settings(false), 1000, false);
        return Check.eq(logger, "phase", st["ph"], PomoEngine.FOCUS)
            && Check.eq(logger, "pomodoros", st["cyc"], 0);
    }

    (:test)
    function shortBreakKeepsTheCount(logger as Logger) as Boolean {
        var st = { "ph" => PomoEngine.SHORT_BREAK, "run" => true, "end" => 1000, "rem" => 0, "rdy" => false, "cyc" => 2 };
        PomoEngine.advance(st, settings(false), 1000, false);
        return Check.eq(logger, "phase", st["ph"], PomoEngine.FOCUS)
            && Check.eq(logger, "pomodoros", st["cyc"], 2);
    }

    // Auto-start counts from when the last phase ended, not from now: no time lost while the app was closed.
    (:test)
    function autoStartCountsFromTheEnd(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        PomoEngine.advance(st, settings(true), 1000, true);
        return Check.eq(logger, "running", st["run"], true)
            && Check.eq(logger, "ready", st["rdy"], false)
            && Check.eq(logger, "ends", st["end"], 1300);
    }

    (:test)
    function rollLeavesAPausedTimerAlone(logger as Logger) as Boolean {
        var st = { "ph" => PomoEngine.FOCUS, "run" => false, "end" => 0, "rem" => 600, "rdy" => false, "cyc" => 1 };
        var r = PomoEngine.roll(st, settings(true), 999999);
        return Check.eq(logger, "focus sessions done", (r[0] as Array).size(), 0)
            && Check.eq(logger, "last phase", r[1], null)
            && Check.eq(logger, "phase", st["ph"], PomoEngine.FOCUS)
            && Check.eq(logger, "seconds left", st["rem"], 600);
    }

    (:test)
    function rollBeforeTheEndChangesNothing(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        var r = PomoEngine.roll(st, settings(false), 999);
        return Check.eq(logger, "focus sessions done", (r[0] as Array).size(), 0)
            && Check.eq(logger, "still running", st["run"], true)
            && Check.eq(logger, "phase", st["ph"], PomoEngine.FOCUS);
    }

    // The end second itself counts as ended.
    (:test)
    function rollAtTheEndFinishesTheFocus(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        var r = PomoEngine.roll(st, settings(false), 1000);
        return Check.arr(logger, "focus end times", r[0] as Array, [1000])
            && Check.eq(logger, "last phase", r[1], PomoEngine.FOCUS)
            && Check.eq(logger, "phase", st["ph"], PomoEngine.SHORT_BREAK)
            && Check.eq(logger, "running", st["run"], false);
    }

    // Without auto-start, hours later, only the one running focus is done: the break waits for START.
    (:test)
    function rollWithoutAutoStartStopsAfterOnePhase(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        var r = PomoEngine.roll(st, settings(false), 1000 + 8 * 3600);
        return Check.arr(logger, "focus end times", r[0] as Array, [1000])
            && Check.eq(logger, "phase", st["ph"], PomoEngine.SHORT_BREAK)
            && Check.eq(logger, "ready", st["rdy"], true);
    }

    // An ignored timer with auto-start runs one full set (4 pomodoros and the long break), then stops.
    (:test)
    function rollWithAutoStartStopsAfterTheLongBreak(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        var r = PomoEngine.roll(st, settings(true), 1000 + 24 * 3600);
        // Each focus ends 1500 + 300 s after the previous one.
        return Check.arr(logger, "focus end times", r[0] as Array, [1000, 2800, 4600, 6400])
            && Check.eq(logger, "last phase", r[1], PomoEngine.LONG_BREAK)
            && Check.eq(logger, "phase", st["ph"], PomoEngine.FOCUS)
            && Check.eq(logger, "running", st["run"], false)
            && Check.eq(logger, "ready", st["rdy"], true)
            && Check.eq(logger, "pomodoros", st["cyc"], 0)
            && Check.eq(logger, "seconds left", st["rem"], 1500);
    }

    // Opened in the middle of a later phase: rolled up to it, and that phase keeps running.
    (:test)
    function rollStopsInsideTheCurrentPhase(logger as Logger) as Boolean {
        var st = focusRunning(1000, 0);
        var r = PomoEngine.roll(st, settings(true), 2000); // the short break runs 1000..1300, then focus to 2800
        return Check.arr(logger, "focus end times", r[0] as Array, [1000])
            && Check.eq(logger, "last phase", r[1], PomoEngine.SHORT_BREAK)
            && Check.eq(logger, "phase", st["ph"], PomoEngine.FOCUS)
            && Check.eq(logger, "running", st["run"], true)
            && Check.eq(logger, "ends", st["end"], 2800);
    }

    (:test)
    function wakeMessages(logger as Logger) as Boolean {
        var shortWaiting = { "ph" => PomoEngine.SHORT_BREAK, "run" => false };
        var longRunning = { "ph" => PomoEngine.LONG_BREAK, "run" => true };
        var focusWaiting = { "ph" => PomoEngine.FOCUS, "run" => false };
        var focusRunningNow = { "ph" => PomoEngine.FOCUS, "run" => true };
        return Check.eq(logger, "focus done, break waits",
                PomoEngine.wakeMessage(PomoEngine.FOCUS, shortWaiting), "Pomodoro done! Break time.")
            && Check.eq(logger, "focus done, long break started",
                PomoEngine.wakeMessage(PomoEngine.FOCUS, longRunning), "Pomodoro done! Long break started.")
            && Check.eq(logger, "break over, focus waits",
                PomoEngine.wakeMessage(PomoEngine.SHORT_BREAK, focusWaiting), "Break over. Ready to focus?")
            && Check.eq(logger, "break over, focus started",
                PomoEngine.wakeMessage(PomoEngine.LONG_BREAK, focusRunningNow), "Break over. Focus started.");
    }
}
