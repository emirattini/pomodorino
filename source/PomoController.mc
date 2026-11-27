import Toybox.Application;
import Toybox.Attention;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

var gController as PomoController? = null;

function getController() as PomoController {
    if (gController == null) {
        gController = new PomoController();
    }
    return gController as PomoController;
}

// Foreground state holder: timer actions, settings, stats, alerts.
class PomoController {

    var settings as Dictionary;
    var state as Dictionary;
    var stats as Stats;
    // Task session (docs/tasks-spec.md), null when working without a task:
    // id, title, est (estimate min or null), spent (min spent before, or null), sid (session id),
    // start (epoch s of the first start, 0 = not yet), foc (focus seconds of completed
    // pomodoros), pom (completed pomodoros), int (a pomodoro was cut short), day (midnight of the day
    // this time belongs to: each day's time is sent as its own session), last (epoch s of the last
    // focus time added)
    var task as Dictionary? = null;
    // Set on the first open of a new day with a task still selected: MainView asks "Still working on
    // ...?" (StillWorkingView).
    var askContinue as Boolean = false;
    private var _ticker as Timer.Timer?;

    const KEY_TASK = "task";

    function initialize() {
        settings = PomoEngine.loadSettings();
        state = PomoEngine.loadState();
        stats = new Stats();
        var t = Application.Storage.getValue(KEY_TASK);
        task = (t instanceof Dictionary) ? t : null;
    }

    // ---- lifecycle ----

    function onEnter() as Void {
        // While open, we alert ourselves; no background prompt needed.
        Background.deleteTemporalEvent();
        tick(false); // catch up on what happened while closed, silently
        newDay();
        var t = new Timer.Timer();
        t.start(method(:onTick), 1000, true);
        _ticker = t;
        TaskSync.flush(); // sessions finished while the phone was away
    }

    function onExit() as Void {
        var t = _ticker;
        if (t != null) {
            t.stop();
            _ticker = null;
        }
        saveState();
        PomoEngine.scheduleWake(state);
    }

    function onTick() as Void {
        tick(true);
        WatchUi.requestUpdate();
    }

    // Rolls the timer forward; returns the phase that just ended, or null.
    function tick(alert as Boolean) as Number? {
        var res = PomoEngine.roll(state, settings, nowSec());
        var done = res[0] as Array;
        var ended = res[1];
        for (var i = 0; i < done.size(); i++) {
            stats.record(done[i] as Number, goal());
        }
        var t = task;
        if (t != null && done.size() > 0) {
            t["pom"] = (t["pom"] as Number) + done.size();
            t["foc"] = (t["foc"] as Number) + done.size() * PomoEngine.duration(PomoEngine.FOCUS, settings);
            t["last"] = nowSec();
            saveTask();
        }
        if (ended != null) {
            saveState();
            if (alert) {
                alertFor(ended as Number);
            }
        }
        return ended;
    }

    // ---- queries ----

    // The clock, in one place each so the unit tests can set it (tests/ControllerTest.mc).
    function nowSec() as Number {
        return Time.now().value();
    }

    // Midnight starting today, local time (epoch s).
    function today() as Number {
        return Time.today().value();
    }

    function phase() as Number {
        return state["ph"] as Number;
    }

    function isRunning() as Boolean {
        return state["run"] as Boolean;
    }

    function isPaused() as Boolean {
        return !isRunning() && !(state["rdy"] as Boolean) && phase() != PomoEngine.IDLE;
    }

    function isBreak() as Boolean {
        var p = phase();
        return p == PomoEngine.SHORT_BREAK || p == PomoEngine.LONG_BREAK;
    }

    function styleIndex() as Number {
        var i = settings["style"] as Number;
        return (i < 0 || i >= STYLE_COUNT) ? 0 : i;
    }

    function endTime() as Number {
        return state["end"] as Number;
    }

    function goal() as Number {
        return settings["goal"] as Number;
    }

    function cycle() as Number {
        return state["cyc"] as Number;
    }

    function total() as Number {
        return PomoEngine.duration(phase(), settings);
    }

    function remaining() as Number {
        if (isRunning()) {
            var r = (state["end"] as Number) - nowSec();
            return r < 0 ? 0 : r;
        }
        if (phase() == PomoEngine.IDLE) {
            return total();
        }
        return state["rem"] as Number;
    }

    // ---- actions ----

    function toggle() as Void {
        if (isRunning()) {
            state["rem"] = remaining();
            state["run"] = false;
            state["rdy"] = false;
        } else {
            if (phase() == PomoEngine.IDLE) {
                state["ph"] = PomoEngine.FOCUS;
                state["rem"] = total();
            }
            state["end"] = nowSec() + (state["rem"] as Number);
            state["run"] = true;
            state["rdy"] = false;
            var t = task;
            if (t != null && t["start"] == 0) {
                t["start"] = nowSec();
                saveTask();
            }
        }
        buzz(60);
        saveState();
    }

    function skipBreak() as Void {
        if (isBreak()) {
            PomoEngine.advance(state, settings, nowSec(), true);
            saveState();
        }
    }

    function restartSession() as Void {
        // Focus time already spent on the task still counts.
        var t = task;
        var partial = partialFocus();
        if (t != null && partial > 0) {
            t["foc"] = (t["foc"] as Number) + partial;
            t["int"] = true;
            t["last"] = nowSec();
            saveTask();
        }
        if (phase() != PomoEngine.IDLE) {
            state["run"] = false;
            state["rdy"] = true;
            state["rem"] = total();
            saveState();
        }
    }

    function stopAll() as Void {
        state["ph"] = PomoEngine.IDLE;
        state["run"] = false;
        state["rdy"] = true;
        state["rem"] = 0;
        state["cyc"] = 0;
        saveState();
    }

    function setSetting(key as String, value) as Void {
        settings[key] = value;
        Application.Storage.setValue(PomoEngine.KEY_SETTINGS, settings);
        // A session that hasn't started yet picks up the new duration.
        if (!isRunning() && (state["rdy"] as Boolean) && phase() != PomoEngine.IDLE) {
            state["rem"] = total();
            saveState();
        }
        if (key.equals("goal")) {
            stats.setTodayGoal(value as Number);
        }
    }

    // ---- tasks ----

    function hasTask() as Boolean {
        return task != null;
    }

    function taskTitle() as String? {
        var t = task;
        return t == null ? null : t["title"] as String;
    }

    // t: one task from the server's list.
    function startTask(t as Dictionary) as Void {
        task = {
            "id" => t["id"], "title" => t["title"], "est" => t["estimateMin"], "spent" => t["spentMin"],
            "sid" => TaskSync.newId(), "start" => 0, "foc" => 0, "pom" => 0, "int" => false,
            "day" => today()
        };
        saveTask();
    }

    // Seconds of focus in the pomodoro in progress (paused time doesn't count: "rem" stops).
    function partialFocus() as Number {
        if (phase() == PomoEngine.FOCUS && !(state["rdy"] as Boolean)) {
            return total() - remaining();
        }
        return 0;
    }

    // Focus minutes in this task session, rounded down; a cut-short pomodoro over 30 s counts as 1.
    function taskFocusMin() as Number {
        var t = task;
        if (t == null) {
            return 0;
        }
        var sec = (t["foc"] as Number) + partialFocus();
        var min = sec / 60;
        return (min == 0 && sec > 30) ? 1 : min;
    }

    // Ends the task session: queues it for the server (and the completion, if asked), stops the timer.
    function finishTask(complete as Boolean) as Void {
        var t = task;
        if (t == null) {
            return;
        }
        var id = t["id"] as String;
        var min = taskFocusMin();
        queueSession(t, min, nowSec(), (t["int"] as Boolean) || partialFocus() > 0);
        if (complete) {
            TaskSync.enqueue({ "k" => "c", "id" => id });
        }
        TaskSync.updateCachedTask(id, min, complete);
        task = null;
        Application.Storage.deleteValue(KEY_TASK);
        stopAll();
        TaskSync.flush();
    }

    // First open of a new day with a task still selected: the earlier day's time goes to the server as its
    // own session (one Todoist comment per day), the task stays selected with today's time starting at
    // zero, and MainView asks whether it's still the task to work on. A pomodoro still going counts for
    // today, when it ends.
    function newDay() as Void {
        var t = task;
        if (t == null) {
            return;
        }
        var midnight = today();
        if (!(t["day"] instanceof Number)) {
            t["day"] = midnight; // a task selected before this version: start counting days now
            saveTask();
            return;
        }
        if ((t["day"] as Number) >= midnight) {
            return;
        }
        // Only time already added up: a pomodoro paused overnight counts for today when it ends.
        var sec = t["foc"] as Number;
        var min = (sec / 60 == 0 && sec > 30) ? 1 : sec / 60;
        var last = t["last"] instanceof Number ? t["last"] as Number : nowSec();
        if (queueSession(t, min, last, t["int"] as Boolean)) {
            var spent = t["spent"] instanceof Number ? t["spent"] as Number : 0;
            t["spent"] = spent + min; // so "actual" on the finish screen still counts every day
            TaskSync.updateCachedTask(t["id"] as String, min, false);
        }
        t["sid"] = TaskSync.newId();
        t["start"] = isRunning() ? nowSec() : 0;
        t["foc"] = 0;
        t["pom"] = 0;
        t["int"] = false;
        t["day"] = midnight;
        saveTask();
        askContinue = true;
        TaskSync.flush();
    }

    // Queues the task's time as one session (docs/tasks-spec.md). Returns false if there was nothing to send.
    private function queueSession(t as Dictionary, min as Number, endSec as Number, interrupted as Boolean) as Boolean {
        var pom = t["pom"] as Number;
        if (min <= 0 && pom <= 0) {
            return false;
        }
        var start = t["start"] as Number;
        TaskSync.enqueue({ "k" => "s", "b" => {
            "sessionId" => t["sid"],
            "taskId" => t["id"],
            "startedAt" => TaskSync.iso(start > 0 ? start : endSec),
            "endedAt" => TaskSync.iso(endSec),
            "focusMin" => min,
            "pomodori" => pom,
            "interrupted" => interrupted
        } });
        return true;
    }

    // Forgets the current task without sending anything (after Disconnect Todoist).
    function dropTask() as Void {
        task = null;
        Application.Storage.deleteValue(KEY_TASK);
    }

    private function saveTask() as Void {
        Application.Storage.setValue(KEY_TASK, task);
    }

    function saveState() as Void {
        Application.Storage.setValue(PomoEngine.KEY_STATE, state);
    }

    // ---- alerts ----

    private function alertFor(ended as Number) as Void {
        if (Attention has :vibrate) {
            var pulses = (ended == PomoEngine.FOCUS) ? 3 : 2;
            var vibe = [] as Array<Attention.VibeProfile>;
            for (var i = 0; i < pulses; i++) {
                vibe.add(new Attention.VibeProfile(100, 450));
                vibe.add(new Attention.VibeProfile(0, 250));
            }
            Attention.vibrate(vibe);
        }
        if (Attention has :playTone) {
            Attention.playTone(ended == PomoEngine.FOCUS ? Attention.TONE_SUCCESS : Attention.TONE_INTERVAL_ALERT);
        }
        if (Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e) {
                // AMOLED may refuse; not important
            }
        }
    }

    private function buzz(ms as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, ms)]);
        }
    }
}
