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
    // pomodoros), pom (completed pomodoros), int (a pomodoro was cut short)
    var task as Dictionary? = null;
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

    function nowSec() as Number {
        return Time.now().value();
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
            "sid" => TaskSync.newId(), "start" => 0, "foc" => 0, "pom" => 0, "int" => false
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
        var pom = t["pom"] as Number;
        if (min > 0 || pom > 0) {
            var now = nowSec();
            var start = t["start"] as Number;
            TaskSync.enqueue({ "k" => "s", "b" => {
                "sessionId" => t["sid"],
                "taskId" => id,
                "startedAt" => TaskSync.iso(start > 0 ? start : now),
                "endedAt" => TaskSync.iso(now),
                "focusMin" => min,
                "pomodori" => pom,
                "interrupted" => (t["int"] as Boolean) || partialFocus() > 0
            } });
        }
        if (complete) {
            TaskSync.enqueue({ "k" => "c", "id" => id });
        }
        TaskSync.updateCachedTask(id, min, complete);
        task = null;
        Application.Storage.deleteValue(KEY_TASK);
        stopAll();
        TaskSync.flush();
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
