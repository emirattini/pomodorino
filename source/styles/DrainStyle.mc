import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// 2 Drain: a thick ring that drains away as time runs out; bold Bebas Neue type.
class DrainStyle extends Style {

    private var _timer;
    private var _label;

    function initialize() {
        Style.initialize();
        _timer = WatchUi.loadResource(Rez.Fonts.TimerDrain);
        _label = WatchUi.loadResource(Rez.Fonts.LabelDrain);
    }

    function draw(dc as Dc, f as Frame) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var s = dc.getWidth() / 390.0;
        Draw.clear(dc);
        var col = (f.running || f.phase == PomoEngine.IDLE) ? f.color : Theme.shade(f.color, 0.55);

        // Daily goal: thin continuous arc with a knob.
        var rG = cx - (9 * s).toNumber();
        dc.setPenWidth((3 * s).toNumber());
        dc.setColor(Theme.shade(Theme.GOAL, 0.2), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, rG);
        var gf = f.goal > 0 ? f.today.toFloat() / f.goal : 0.0;
        if (gf > 1.0) {
            gf = 1.0;
        }
        if (gf > 0.0) {
            dc.setColor(Theme.GOAL, Graphics.COLOR_TRANSPARENT);
            Draw.arcCw(dc, cx, cy, rG, 90, 360 * gf);
            dc.fillCircle(Draw.px(cx, rG, 90 - 360 * gf), Draw.py(cy, rG, 90 - 360 * gf), (5 * s).toNumber());
        }

        // Session: the remaining time, from the tip clockwise back to 12 o'clock.
        var rS = cx - (46 * s).toNumber();
        var pen = (26 * s).toNumber();
        dc.setPenWidth(pen);
        dc.setColor(Theme.shade(col, 0.1), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, rS);
        var left = 1.0 - f.frac;
        if (left > 0.002) {
            var start = 90 - 360 * f.frac;
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            Draw.arcCw(dc, cx, cy, rS, start, 360 * left);
            dc.fillCircle(Draw.px(cx, rS, start), Draw.py(cy, rS, start), pen / 2);
            dc.fillCircle(cx, cy - rS, pen / 2);
        }

        Draw.text(dc, cx, cy - (58 * s).toNumber(), _label, Theme.phaseName(f.phase), col);
        Draw.text(dc, cx, cy + (4 * s).toNumber(), _timer, Theme.formatTime(f.rem),
            f.running || f.phase == PomoEngine.IDLE ? Graphics.COLOR_WHITE : Theme.DIM);
        Draw.text(dc, cx, cy + (60 * s).toNumber(), _label, f.today.toString() + " / " + f.goal + " TODAY", Theme.GOAL);
        Draw.statusLine(dc, cx, cy + (90 * s).toNumber(), cx - (65 * s).toNumber(), _label, Theme.status(f), f.paused ? col : Theme.DIM, f);
    }
}
