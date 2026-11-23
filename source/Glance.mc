import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// The app's glance (the quick view in the widget list).
// - A session running or paused: its phase and end time, and the task being worked on.
// - Otherwise: the most important task of the day (the server sorts by priority).
// Glances can't make web requests, so the task comes from the list saved the last time the app
// loaded it. A list from an earlier day isn't shown. This code runs in the glance's small memory
// (64 KB), so it only reads Storage and doesn't use the app's other modules.
(:glance)
class PomoGlanceView extends WatchUi.GlanceView {

    const FOCUS_COLOR = 0xFF5544;
    const SHORT_COLOR = 0x44DD88;
    const LONG_COLOR = 0x44AAFF;
    const GOAL_COLOR = 0xFFB000;
    const DIM_COLOR = 0x8A8A8A;

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var font = (Graphics has :FONT_GLANCE) ? Graphics.FONT_GLANCE : Graphics.FONT_XTINY;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var c = content();
        line(dc, (h * 0.18).toNumber(), font, c[0] as String, c[1] as Number, w);
        line(dc, (h * 0.50).toNumber(), font, c[2] as String, Graphics.COLOR_WHITE, w);
        line(dc, (h * 0.82).toNumber(), font, c[3] as String, DIM_COLOR, w);
    }

    // [header, header color, main line, detail line]
    private function content() as Array {
        var now = Time.now().value();
        var st = Application.Storage.getValue("state");
        var task = Application.Storage.getValue("task");
        var header = "POMODORINO";
        var color = GOAL_COLOR;

        if (st instanceof Dictionary) {
            var ph = st["ph"];
            if (st["run"] == true && st["end"] instanceof Number && now < (st["end"] as Number)) {
                header = phaseName(ph) + " · until " + clock(st["end"] as Number);
                color = ph == 2 ? SHORT_COLOR : (ph == 3 ? LONG_COLOR : FOCUS_COLOR);
            } else if (st["run"] == false && st["rdy"] == false && ph != 0) {
                header = phaseName(ph) + " · paused";
            }
        }

        if (task instanceof Dictionary && task["title"] instanceof String) {
            return [header, color, task["title"], "Working on this"];
        }
        var top = topTask();
        if (top != null) {
            var detail = "Next task";
            if (top["estimateMin"] instanceof Number) {
                detail += " · est " + minutes(top["estimateMin"] as Number);
            }
            if (top["spentMin"] instanceof Number && (top["spentMin"] as Number) > 0) {
                detail += " · " + minutes(top["spentMin"] as Number) + " done";
            }
            return [header, color, top["title"], detail];
        }
        if (Application.Storage.getValue("taskCache") != null) {
            return [header, color, "No tasks loaded today", "Open to see today's tasks"];
        }
        return [header, color, "Ready to focus", "Press to start"];
    }

    // The first task of today's saved list, or null (no list, an old list, or nothing left today).
    private function topTask() as Dictionary? {
        var cache = Application.Storage.getValue("taskCache");
        if (!(cache instanceof Dictionary) || cache["day"] != Time.today().value()) {
            return null;
        }
        var tasks = cache["tasks"];
        if (!(tasks instanceof Array) || tasks.size() == 0) {
            return null;
        }
        return tasks[0] as Dictionary;
    }

    private function phaseName(ph) as String {
        if (ph == 2) {
            return "SHORT BREAK";
        }
        return ph == 3 ? "LONG BREAK" : "FOCUS";
    }

    private function clock(epoch as Number) as String {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        var hour = info.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12 == 0 ? 12 : hour % 12;
        }
        return hour + ":" + (info.min as Number).format("%02d");
    }

    private function minutes(m as Number) as String {
        return m >= 60 ? (m / 60) + "h " + (m % 60).format("%02d") + "'" : m + "'";
    }

    // Left-aligned text, shortened with "…" to the glance width.
    private function line(dc as Dc, y as Number, font, s as String, color as Number, w as Number) as Void {
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
