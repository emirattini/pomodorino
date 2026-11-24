import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The app's glance (the quick view in the widget list), laid out like Garmin's own:
//   Pomodorino              title
//   /▰▰▰▰▰▰▰▰/ /──────────/  progress of the current session: red focus, green break, blue long break
//   Consegna Pcd   20/50'   the task being worked on, or the most urgent task of the day, with the
//                           minutes done on it out of its estimate
// Glances can't make web requests, so the next task comes from the list saved the last time the app
// loaded it; a list from an earlier day isn't shown. This runs in the glance's small memory (64 KB),
// so it only reads Storage and doesn't use the app's other modules.
(:glance)
class PomoGlanceView extends WatchUi.GlanceView {

    const IDLE = 0;
    const FOCUS = 1;
    const SHORT_BREAK = 2;
    const LONG_BREAK = 3;

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var now = Time.now().value();
        var st = Application.Storage.getValue("state");

        // Where the session is: phase, progress 0..1, and whether it's counting down.
        var ph = IDLE;
        var frac = 0.0;
        var running = false;
        var focusSec = 0; // seconds of the focus session in progress, not yet in the task's "foc"
        var session = IDLE; // the phase the app is in, even if its timer ran out while it was closed
        if (st instanceof Dictionary && st["ph"] instanceof Number && st["ph"] != IDLE) {
            session = st["ph"] as Number;
            var dur = duration(session);
            var elapsed = 0; // seconds into the current session
            if (st["run"] == true && st["end"] instanceof Number) {
                var left = (st["end"] as Number) - now;
                // A session that ended while the app was closed counts in full, but the bar shows idle.
                elapsed = dur - (left > 0 ? left : 0);
                if (left > 0) {
                    ph = st["ph"] as Number;
                    running = true;
                    frac = elapsed / dur.toFloat();
                }
            } else if (st["run"] == false && st["rdy"] == false && st["rem"] instanceof Number) {
                ph = st["ph"] as Number; // paused
                elapsed = dur - (st["rem"] as Number);
                frac = elapsed / dur.toFloat();
            }
            if (st["ph"] == FOCUS) {
                focusSec = elapsed;
            }
        }
        frac = frac < 0.0 ? 0.0 : (frac > 1.0 ? 1.0 : frac);

        title(dc, (h * 0.20).toNumber());
        bar(dc, (h * 0.50).toNumber(), w, h, ph, frac, running);

        var task = taskLine(focusSec, session);
        taskRow(dc, (h * 0.80).toNumber(), w, task);
    }

    // "Pomodorino", larger than the glance font: drawn as vector Roboto when the watch has it.
    private function title(dc as Dc, y as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if ((Graphics has :getVectorFont) && (dc has :drawAngledText)) {
            var size = dc.getFontHeight(Graphics.FONT_GLANCE);
            var font = Graphics.getVectorFont({ :face => "RobotoRegular", :size => size });
            if (font != null) {
                dc.drawAngledText(0, y, font, "Pomodorino", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, 0);
                return;
            }
        }
        dc.drawText(0, y, Graphics.FONT_GLANCE, "Pomodorino", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Like Garmin's glance bars: the elapsed part is a slanted bar fading from greyish to the phase's
    // color (red focus, green break, blue long break; dimmed while paused), then a small gap, then the
    // rest as a thin grey line. Both start and end with a slash, like "/████/ /────/".
    private function bar(dc as Dc, y as Number, w as Number, h as Number, ph as Number, frac as Float, running as Boolean) as Void {
        var bh = (h * 0.09).toNumber(); // the thick part
        bh = bh < 6 ? 6 : bh;
        var th = bh / 3;                 // the thin line
        th = th < 2 ? 2 : th;
        var x = 0;
        if (ph != IDLE && frac > 0.0) {
            var fw = (w * frac).toNumber();
            fw = fw < bh + 2 ? bh + 2 : fw;
            var color = ph == SHORT_BREAK ? 0x44DD88 : (ph == LONG_BREAK ? 0x44AAFF : 0xFF3322);
            if (!running) {
                color = mix(color, 0x000000, 50); // paused: half brightness
            }
            gradient(dc, y - bh / 2, fw, bh, mix(color, 0x606060, 70), color);
            x = fw + 4; // with the slants, about a 5-pixel gap at the line's height
        }
        if (x < w - th) {
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            slanted(dc, x, w, y - th / 2, th, th / 2);
        }
    }

    // A parallelogram from x0 to x1 whose ends lean like "/" by `slant` pixels.
    private function slanted(dc as Dc, x0 as Number, x1 as Number, top as Number, height as Number, slant as Number) as Void {
        dc.fillPolygon([[x0 + slant, top], [x1, top], [x1 - slant, top + height], [x0, top + height]]);
    }

    // A slanted bar 0..width, drawn in thin slices whose color goes from `from` (left) to `to` (right).
    private function gradient(dc as Dc, top as Number, width as Number, height as Number, from as Number, to as Number) as Void {
        var step = 3;
        var slant = height / 4;   // a slight lean, like Garmin's bars
        var run = width - slant;  // where each slice's bottom-left corner can be
        for (var i = 0; i < run; i += step) {
            var j = i + step > run ? run : i + step;
            dc.setColor(mix(from, to, (i * 100) / run), Graphics.COLOR_TRANSPARENT);
            // +1 overlap so no hairline gaps show between slices
            dc.fillPolygon([[i + slant, top], [j + slant + 1, top], [j + 1, top + height], [i, top + height]]);
        }
    }

    // `a` with `pct` percent of `b` mixed in, channel by channel.
    private function mix(a as Number, b as Number, pct as Number) as Number {
        var out = 0;
        for (var shift = 0; shift <= 16; shift += 8) {
            var ca = (a >> shift) & 0xFF;
            var cb = (b >> shift) & 0xFF;
            out |= ((ca * (100 - pct) + cb * pct) / 100) << shift;
        }
        return out;
    }

    // [text, is a task (white) rather than a hint (grey), minutes done or null, estimate or null]
    private function taskLine(focusSec as Number, session as Number) as Array {
        var task = Application.Storage.getValue("task");
        if (task instanceof Dictionary && task["title"] instanceof String) {
            // Logged before this session + this session's finished pomodoros + the one in progress,
            // counted like the app does (a cut-short pomodoro over 30 s counts as one minute).
            var sec = (task["foc"] instanceof Number ? task["foc"] as Number : 0) + focusSec;
            var min = sec / 60;
            min = (min == 0 && sec > 30) ? 1 : min;
            var before = task["spent"] instanceof Number ? task["spent"] as Number : 0;
            return [task["title"], true, before + min, task["est"]];
        }
        // A session without a task: name the phase rather than suggest a task that isn't being done.
        if (session != IDLE) {
            return [session == SHORT_BREAK ? "Short break" : (session == LONG_BREAK ? "Long break" : "Focus"), false, null, null];
        }
        var cache = Application.Storage.getValue("taskCache");
        if (cache instanceof Dictionary) {
            var tasks = cache["tasks"];
            if (cache["day"] != Time.today().value()) {
                return ["Open to load today's tasks", false, null, null];
            }
            if (tasks instanceof Array && tasks.size() > 0 && (tasks[0] as Dictionary)["title"] instanceof String) {
                var top = tasks[0] as Dictionary;
                return [top["title"], true, top["spentMin"], top["estimateMin"]];
            }
            return ["No tasks left today", false, null, null];
        }
        return ["Ready to focus", false, null, null];
    }

    // Session length in seconds, from the app's settings (defaults 25 / 5 / 15 minutes).
    private function duration(ph as Number) as Number {
        var s = Application.Storage.getValue("settings");
        var key = ph == SHORT_BREAK ? "short" : (ph == LONG_BREAK ? "long" : "focus");
        var min = (s instanceof Dictionary && s[key] instanceof Number) ? s[key] as Number : (ph == SHORT_BREAK ? 5 : (ph == LONG_BREAK ? 15 : 25));
        return min * 60;
    }

    // The task title on the left and "done/estimate'" on the right (red once over the estimate).
    // Without an estimate just the minutes done, if any; hints have no counter.
    private function taskRow(dc as Dc, y as Number, w as Number, task as Array) as Void {
        var font = Graphics.FONT_GLANCE;
        var done = task[2] instanceof Number ? task[2] as Number : 0;
        var est = task[3] instanceof Number ? task[3] as Number : 0;
        var counter = est > 0 ? done + "/" + est + "'" : (done > 0 ? done + "'" : "");
        var room = w;
        if (!counter.equals("")) {
            dc.setColor(est > 0 && done > est ? 0xFF5544 : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w, y, font, counter, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            room = w - dc.getTextWidthInPixels(counter, font) - 12;
        }
        var s = task[0] as String;
        if (dc.getTextWidthInPixels(s, font) > room) {
            var n = s.length() - 1;
            while (n > 1 && dc.getTextWidthInPixels(s.substring(0, n) + "…", font) > room) {
                n--;
            }
            s = s.substring(0, n) + "…";
        }
        dc.setColor((task[1] as Boolean) ? Graphics.COLOR_WHITE : 0x8A8A8A, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, y, font, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
