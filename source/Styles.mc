import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.WatchUi;

// Everything a style needs to draw one frame of the main screen.
class Frame {
    var phase as Number = 0;
    var color as Number = 0;
    var running as Boolean = false;
    var paused as Boolean = false;
    var frac as Float = 0.0;      // session progress 0..1
    var rem as Number = 0;        // seconds left
    var end as Number = 0;        // epoch seconds
    var minutes as Number = 25;   // session length
    var today as Number = 0;
    var goal as Number = 1;
    var streak as Number = 0;
    var cycle as Number = 0;
    var every as Number = 4;
    var tick as Number = 0;       // epoch seconds, drives small animations
    var task as String? = null;   // title of the task being worked on

    function initialize() {
    }
}

// demo: when idle, show a session in progress (used by the style picker preview).
function buildFrame(ctrl as PomoController, demo as Boolean) as Frame {
    var f = new Frame();
    var total = ctrl.total();
    f.phase = ctrl.phase();
    f.running = ctrl.isRunning();
    f.paused = ctrl.isPaused();
    f.rem = ctrl.remaining();
    f.frac = (total > 0 && f.phase != PomoEngine.IDLE) ? (total - f.rem).toFloat() / total : 0.0;
    f.frac = f.frac < 0.0 ? 0.0 : (f.frac > 1.0 ? 1.0 : f.frac);
    f.end = ctrl.endTime();
    f.minutes = total / 60;
    f.goal = ctrl.goal();
    f.today = ctrl.stats.todayCount();
    f.streak = ctrl.stats.streak(f.goal);
    f.cycle = ctrl.cycle();
    f.every = ctrl.settings["every"] as Number;
    f.tick = Time.now().value();
    f.task = demo ? null : ctrl.taskTitle();
    if (demo && f.phase == PomoEngine.IDLE) {
        f.phase = PomoEngine.FOCUS;
        f.frac = 0.4;
        f.rem = (total * 0.6).toNumber();
        f.running = true;
        f.end = f.tick + f.rem;
    }
    f.color = Theme.phaseColor(f.phase);
    return f;
}

// ---- Style registry ----

const STYLE_COUNT = 5;

function styleName(i as Number) as String {
    return ["Ember", "Drain", "Mono", "Liquid", "Classic"][i] as String;
}

function createStyle(i as Number) as Style {
    if (i == 1) {
        return new DrainStyle();
    }
    if (i == 2) {
        return new MonoStyle();
    }
    if (i == 3) {
        return new LiquidStyle();
    }
    if (i == 4) {
        return new ClassicStyle();
    }
    return new EmberStyle();
}

// Base class: each style loads its own fonts and draws the whole screen.
class Style {
    function initialize() {
    }

    function draw(dc as Dc, f as Frame) as Void {
    }
}

// ---- Drawing helpers shared by styles ----

module Draw {

    function clear(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
    }

    function px(cx as Number, r as Numeric, deg as Numeric) as Float {
        return cx + r * Math.cos(Math.toRadians(deg));
    }

    function py(cy as Number, r as Numeric, deg as Numeric) as Float {
        return cy - r * Math.sin(Math.toRadians(deg));
    }

    // Clockwise arc of `sweep` degrees starting at `start` (CIQ angles: CCW from 3 o'clock).
    function arcCw(dc as Dc, cx as Number, cy as Number, r as Number, start as Numeric, sweep as Numeric) as Void {
        if (sweep >= 359.9) {
            dc.drawCircle(cx, cy, r);
        } else if (sweep > 0.3) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, start - sweep);
        }
    }

    // Daily goal as one segment per pomodoro, starting at 12 o'clock.
    function goalSegments(dc as Dc, cx as Number, cy as Number, r as Number, pen as Number, count as Number, goal as Number) as Void {
        var n = goal < 1 ? 1 : goal;
        var dark = Theme.shade(Theme.GOAL, 0.22);
        dc.setPenWidth(pen);
        if (n == 1) {
            dc.setColor(count >= 1 ? Theme.GOAL : dark, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
            return;
        }
        var span = 360.0 / n;
        var gap = n <= 12 ? 4.0 : 2.5;
        for (var i = 0; i < n; i++) {
            var start = 90 - i * span - gap / 2;
            dc.setColor(i < count ? Theme.GOAL : dark, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, start, start - (span - gap));
        }
    }

    // Text curved along the top (reading clockwise) or bottom of a circle.
    function arcLabel(dc as Dc, font as Graphics.VectorFont?, cx as Number, cy as Number, r as Number, text as String, color as Number, top as Boolean) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (font != null && (dc has :drawRadialText)) {
            dc.drawRadialText(cx, cy, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER,
                top ? 90 : 270, r,
                top ? Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE : Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
        } else {
            dc.drawText(cx, top ? cy - r : cy + r, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    function arcFont() as Graphics.VectorFont? {
        if (Graphics has :getVectorFont) {
            return Graphics.getVectorFont({ :face => ["RobotoCondensedBold", "RobotoRegular"], :size => 19 });
        }
        return null;
    }

    function text(dc as Dc, x as Numeric, y as Numeric, font, s as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The status line, replaced by the task's title while a task session runs (unless paused).
    // The title uses the system font: the styles' own fonts only have the letters their labels need.
    function statusLine(dc as Dc, cx as Number, y as Number, font, status as String, color as Number, f as Frame) as Void {
        var title = f.task;
        if (title == null || f.paused) {
            text(dc, cx, y, font, status, color);
            return;
        }
        // Width of the screen's inner circle (radius ~68% of the half-width) at this height.
        var r = cx * 0.68;
        var dy = (y - dc.getHeight() / 2).abs();
        var w = dy < r ? (2 * Math.sqrt(r * r - dy * dy)).toNumber() - 10 : cx;
        text(dc, cx, y, Graphics.FONT_XTINY, fit(dc, Graphics.FONT_XTINY, title, w), 0xCCCCCC);
    }

    var _fitIn as String? = null;
    var _fitW as Number = 0;
    var _fitOut as String = "";

    // Shortens `s` with "…" to fit `maxW` pixels. Remembers the last answer, since onUpdate runs every second.
    function fit(dc as Dc, font, s as String, maxW as Number) as String {
        if (s.equals(_fitIn) && maxW == _fitW) {
            return _fitOut;
        }
        var out = s;
        if (dc.getTextWidthInPixels(s, font) > maxW) {
            var n = s.length() - 1;
            while (n > 1 && dc.getTextWidthInPixels(s.substring(0, n) + "…", font) > maxW) {
                n--;
            }
            out = s.substring(0, n) + "…";
        }
        _fitIn = s;
        _fitW = maxW;
        _fitOut = out;
        return out;
    }

    function todayText(f as Frame) as String {
        var s = f.today.toString() + " / " + f.goal + " TODAY";
        if (f.streak > 0) {
            s += "  ·  " + f.streak + " DAY STREAK";
        }
        return s;
    }
}
