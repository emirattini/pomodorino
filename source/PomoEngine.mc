import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Time;

// Pure timer logic, shared by the foreground app and the background service.
// The timer is based on wall-clock end times, so it keeps "running" while the
// app is closed: whenever we look at it again we roll the state forward.
(:background)
module PomoEngine {

    const IDLE = 0;
    const FOCUS = 1;
    const SHORT_BREAK = 2;
    const LONG_BREAK = 3;

    const KEY_STATE = "state";
    const KEY_SETTINGS = "settings";

    function merge(defaults as Dictionary, key as String) as Dictionary {
        var stored = Application.Storage.getValue(key);
        if (stored instanceof Dictionary) {
            var keys = defaults.keys();
            for (var i = 0; i < keys.size(); i++) {
                var v = stored.get(keys[i]);
                if (v != null) {
                    defaults.put(keys[i], v);
                }
            }
        }
        return defaults;
    }

    function loadSettings() as Dictionary {
        return merge({
            "focus" => 25,   // minutes
            "short" => 5,    // minutes
            "long" => 15,    // minutes
            "every" => 4,    // long break after N pomodoros
            "goal" => 8,     // daily pomodoro target
            "auto" => false, // auto-start next session
            "style" => 0     // main screen style (see Styles.mc)
        }, KEY_SETTINGS);
    }

    // ph:  current phase
    // run: counting down towards "end" (epoch seconds)
    // rem: seconds left when not running
    // rdy: not running and not yet started (vs. paused)
    // cyc: pomodoros completed in the current set (resets after long break)
    function loadState() as Dictionary {
        return merge({
            "ph" => IDLE,
            "run" => false,
            "end" => 0,
            "rem" => 0,
            "rdy" => true,
            "cyc" => 0
        }, KEY_STATE);
    }

    function duration(phase as Number, settings as Dictionary) as Number {
        if (phase == SHORT_BREAK) {
            return (settings["short"] as Number) * 60;
        }
        if (phase == LONG_BREAK) {
            return (settings["long"] as Number) * 60;
        }
        return (settings["focus"] as Number) * 60;
    }

    // Moves past the current phase, which ended at `endedAt`.
    function advance(state as Dictionary, settings as Dictionary, endedAt as Number, autoStart as Boolean) as Void {
        var ended = state["ph"] as Number;
        var cyc = state["cyc"] as Number;
        var next = FOCUS;
        if (ended == FOCUS) {
            cyc += 1;
            next = (cyc >= (settings["every"] as Number)) ? LONG_BREAK : SHORT_BREAK;
        } else if (ended == LONG_BREAK) {
            cyc = 0;
        }
        state["cyc"] = cyc;
        state["ph"] = next;
        var dur = duration(next, settings);
        if (autoStart) {
            state["run"] = true;
            state["end"] = endedAt + dur;
            state["rdy"] = false;
        } else {
            state["run"] = false;
            state["rem"] = dur;
            state["rdy"] = true;
        }
    }

    // Rolls the state forward to `now`.
    // Returns [completed focus end times (Array<Number>), last ended phase or null].
    // Auto-start never chains past a long break, so an ignored timer stops
    // after one full set instead of counting pomodoros all night.
    function roll(state as Dictionary, settings as Dictionary, now as Number) as Array {
        var done = [] as Array<Number>;
        var last = null;
        var guard = 0;
        while ((state["run"] as Boolean) && now >= (state["end"] as Number) && guard < 20) {
            guard++;
            var ended = state["ph"] as Number;
            var endedAt = state["end"] as Number;
            if (ended == FOCUS) {
                done.add(endedAt);
            }
            last = ended;
            var auto = (settings["auto"] as Boolean) && ended != LONG_BREAK;
            advance(state, settings, endedAt, auto);
        }
        return [done, last];
    }

    // Schedules the background wake-up for the end of the running phase.
    function scheduleWake(state as Dictionary) as Void {
        if (state["run"] as Boolean) {
            Background.registerForTemporalEvent(new Time.Moment(state["end"] as Number));
        } else {
            Background.deleteTemporalEvent();
        }
    }

    function wakeMessage(ended as Number, state as Dictionary) as String {
        var running = state["run"] as Boolean;
        if (ended == FOCUS) {
            var brk = (state["ph"] == LONG_BREAK) ? "Long break" : "Break";
            return running ? "Pomodoro done! " + brk + " started." : "Pomodoro done! " + brk + " time.";
        }
        return running ? "Break over. Focus started." : "Break over. Ready to focus?";
    }
}
