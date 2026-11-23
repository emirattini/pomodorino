import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The app's glance (the quick view in the widget list), laid out like Garmin's own:
//   Pomodorino              title, in italics while a focus session runs
//   ━━━━━━━━━──────────     progress of the current session: red focus, green break, blue long break
//   Consegna Pcd            the task being worked on, or the most urgent task of the day
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
        if (st instanceof Dictionary && st["ph"] instanceof Number && st["ph"] != IDLE) {
            var dur = duration(st["ph"] as Number);
            if (st["run"] == true && st["end"] instanceof Number && now < (st["end"] as Number)) {
                ph = st["ph"] as Number;
                running = true;
                frac = 1.0 - ((st["end"] as Number) - now) / dur.toFloat();
            } else if (st["run"] == false && st["rdy"] == false && st["rem"] instanceof Number) {
                ph = st["ph"] as Number; // paused
                frac = 1.0 - (st["rem"] as Number) / dur.toFloat();
            }
        }
        frac = frac < 0.0 ? 0.0 : (frac > 1.0 ? 1.0 : frac);

        title(dc, (h * 0.20).toNumber(), ph == FOCUS && running);
        bar(dc, (h * 0.50).toNumber(), w, h, ph, frac, running);

        var task = taskLine();
        line(dc, (h * 0.80).toNumber(), task[0] as String, (task[1] as Boolean) ? Graphics.COLOR_WHITE : 0x8A8A8A, w);
    }

    // "Pomodorino" in the glance font, or Roboto Italic while focusing (a vector font: the built-in
    // fonts have no italics). Both are drawn as vector Roboto when possible, so the size doesn't jump.
    private function title(dc as Dc, y as Number, italic as Boolean) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if ((Graphics has :getVectorFont) && (dc has :drawAngledText)) {
            var size = (dc.getFontHeight(Graphics.FONT_GLANCE) * 0.78).toNumber();
            var font = Graphics.getVectorFont({ :face => italic ? "RobotoItalic" : "RobotoRegular", :size => size });
            if (font != null) {
                dc.drawAngledText(0, y, font, "Pomodorino", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, 0);
                return;
            }
        }
        dc.drawText(0, y, Graphics.FONT_GLANCE, "Pomodorino", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A rounded track with the elapsed part filled in the phase's color (dimmed while paused).
    private function bar(dc as Dc, y as Number, w as Number, h as Number, ph as Number, frac as Float, running as Boolean) as Void {
        var bh = (h * 0.11).toNumber();
        bh = bh < 6 ? 6 : bh;
        var top = y - bh / 2;
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(0, top, w, bh, bh / 2);
        if (ph == IDLE || frac <= 0.0) {
            return;
        }
        var color = ph == SHORT_BREAK ? 0x44DD88 : (ph == LONG_BREAK ? 0x44AAFF : 0xFF5544);
        if (!running) {
            color = ((color >> 1) & 0x7F7F7F); // paused: half brightness
        }
        var fw = (w * frac).toNumber();
        fw = fw < bh ? bh : fw;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(0, top, fw, bh, bh / 2);
    }

    // [text, is a task (white) rather than a hint (grey)]
    private function taskLine() as Array {
        var task = Application.Storage.getValue("task");
        if (task instanceof Dictionary && task["title"] instanceof String) {
            return [task["title"], true];
        }
        var cache = Application.Storage.getValue("taskCache");
        if (cache instanceof Dictionary) {
            var tasks = cache["tasks"];
            if (cache["day"] != Time.today().value()) {
                return ["Open to load today's tasks", false];
            }
            if (tasks instanceof Array && tasks.size() > 0 && (tasks[0] as Dictionary)["title"] instanceof String) {
                return [(tasks[0] as Dictionary)["title"], true];
            }
            return ["No tasks left today", false];
        }
        return ["Ready to focus", false];
    }

    // Session length in seconds, from the app's settings (defaults 25 / 5 / 15 minutes).
    private function duration(ph as Number) as Number {
        var s = Application.Storage.getValue("settings");
        var key = ph == SHORT_BREAK ? "short" : (ph == LONG_BREAK ? "long" : "focus");
        var min = (s instanceof Dictionary && s[key] instanceof Number) ? s[key] as Number : (ph == SHORT_BREAK ? 5 : (ph == LONG_BREAK ? 15 : 25));
        return min * 60;
    }

    // Left-aligned text in the glance font, shortened with "…" to the glance width.
    private function line(dc as Dc, y as Number, s as String, color as Number, w as Number) as Void {
        var font = Graphics.FONT_GLANCE;
        if (dc.getTextWidthInPixels(s, font) > w) {
            var n = s.length() - 1;
            while (n > 1 && dc.getTextWidthInPixels(s.substring(0, n) + "…", font) > w) {
                n--;
            }
            s = s.substring(0, n) + "…";
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, y, font, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
