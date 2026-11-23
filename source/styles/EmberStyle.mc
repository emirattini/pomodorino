import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// 1 Ember: gradient arc with a breathing glow tip, segmented goal ring, curved labels.
class EmberStyle extends Style {

    private var _timer;
    private var _arc as Graphics.VectorFont?;

    function initialize() {
        Style.initialize();
        _timer = WatchUi.loadResource(Rez.Fonts.TimerEmber);
        _arc = Draw.arcFont();
    }

    function draw(dc as Dc, f as Frame) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var s = dc.getWidth() / 390.0;
        Draw.clear(dc);

        Draw.goalSegments(dc, cx, cy, cx - (8 * s).toNumber(), (7 * s).toNumber(), f.today, f.goal);
        drawSession(dc, cx, cy, cx - (58 * s).toNumber(), (14 * s).toNumber(), f);

        var rText = cx - (33 * s).toNumber();
        Draw.arcLabel(dc, _arc, cx, cy, rText, Theme.spaced(Theme.phaseName(f.phase)), f.color, true);
        Draw.arcLabel(dc, _arc, cx, cy, rText, Draw.todayText(f), f.today >= f.goal ? Theme.GOAL : Theme.shade(Theme.GOAL, 0.8), false);

        drawPips(dc, cx, cy - (50 * s).toNumber(), s, f);
        Draw.text(dc, cx, cy, _timer, Theme.formatTime(f.rem),
            f.running || f.phase == PomoEngine.IDLE ? Graphics.COLOR_WHITE : Theme.DIM);
        Draw.statusLine(dc, cx, cy + (50 * s).toNumber(), Graphics.FONT_XTINY, Theme.status(f), f.paused ? f.color : Theme.DIM, f);
    }

    private function drawSession(dc as Dc, cx as Number, cy as Number, r as Number, pen as Number, f as Frame) as Void {
        var color = f.color;
        var bright = f.running ? 1.0 : 0.55;
        dc.setPenWidth(pen);
        dc.setColor(Theme.shade(color, 0.16), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        if (f.frac <= 0.0) {
            return;
        }
        var sweep = 360.0 * f.frac;

        // Soft glow under the arc
        dc.setPenWidth(pen + (10 * cx / 195));
        dc.setColor(Theme.shade(color, 0.14 * bright), Graphics.COLOR_TRANSPARENT);
        Draw.arcCw(dc, cx, cy, r, 90, sweep);

        // Gradient: dark at the start, full color at the tip
        dc.setPenWidth(pen);
        var steps = (f.frac * 60).toNumber() + 1;
        for (var i = 0; i < steps; i++) {
            var a0 = 90 - sweep * i / steps;
            var a1 = 90 - sweep * (i + 1) / steps - 0.8; // overlap hides seams
            dc.setColor(Theme.shade(color, (0.3 + 0.7 * (i + 1) / steps) * bright), Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a0, a1);
        }

        dc.setColor(Theme.shade(color, 0.3 * bright), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy - r, pen / 2);

        // Tip: breathing halo, colored knob, white core
        var tx = Draw.px(cx, r, 90 - sweep);
        var ty = Draw.py(cy, r, 90 - sweep);
        var halo = (f.running && f.tick % 2 == 0) ? 7 : 4;
        dc.setColor(Theme.shade(color, 0.4 * bright), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tx, ty, pen / 2 + halo);
        dc.setColor(Theme.shade(color, bright), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tx, ty, pen / 2 + 1);
        dc.setColor(f.running ? Graphics.COLOR_WHITE : Theme.DIM, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tx, ty, pen / 4);
    }

    // One pip per pomodoro in the set: done = filled, current = ring with core.
    private function drawPips(dc as Dc, cx as Number, y as Number, s as Float, f as Frame) as Void {
        var gap = (22 * s).toNumber();
        var r = (5 * s).toNumber();
        var x0 = cx - (f.every - 1) * gap / 2;
        for (var i = 0; i < f.every; i++) {
            var x = x0 + i * gap;
            if (i < f.cycle) {
                dc.setColor(Theme.shade(Theme.FOCUS, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, r + 3);
                dc.setColor(Theme.FOCUS, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, r);
            } else if (i == f.cycle && f.phase == PomoEngine.FOCUS) {
                dc.setColor(Theme.FOCUS, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawCircle(x, y, r + 1);
                if (f.running) {
                    dc.fillCircle(x, y, r / 2);
                }
            } else {
                dc.setColor(Theme.shade(Theme.DIM, 0.6), Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawCircle(x, y, r);
            }
        }
    }
}
