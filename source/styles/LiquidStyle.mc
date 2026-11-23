import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// 4 Liquid: the dial fills up like a glass, with two waves that shift every second.
class LiquidStyle extends Style {

    private var _timer;
    private var _small;
    private var _arc as Graphics.VectorFont?;

    function initialize() {
        Style.initialize();
        _timer = WatchUi.loadResource(Rez.Fonts.TimerLiquid);
        _small = WatchUi.loadResource(Rez.Fonts.SmallLiquid);
        _arc = Draw.arcFont();
    }

    function draw(dc as Dc, f as Frame) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var s = dc.getWidth() / 390.0;
        Draw.clear(dc);
        var col = (f.running || f.phase == PomoEngine.IDLE) ? f.color : Theme.shade(f.color, 0.6);

        Draw.goalSegments(dc, cx, cy, cx - (8 * s).toNumber(), (6 * s).toNumber(), f.today, f.goal);

        var rS = cx - (54 * s).toNumber();
        if (f.frac > 0.0) {
            var t = (f.tick % 4) / 4.0;
            drawWave(dc, cx, cy, rS - (4 * s).toNumber(), f.frac, 7 * s, t + 0.5, Theme.shade(col, 0.22));
            drawWave(dc, cx, cy, rS - (4 * s).toNumber(), f.frac, 6 * s, t, Theme.shade(col, 0.5));
        }
        dc.setPenWidth((3 * s).toNumber());
        dc.setColor(Theme.shade(col, 0.7), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, rS);

        var rText = cx - (33 * s).toNumber();
        Draw.arcLabel(dc, _arc, cx, cy, rText, Theme.spaced(Theme.phaseName(f.phase)), col, true);
        Draw.arcLabel(dc, _arc, cx, cy, rText, Draw.todayText(f), f.today >= f.goal ? Theme.GOAL : Theme.shade(Theme.GOAL, 0.8), false);

        Draw.text(dc, cx, cy, _timer, Theme.formatTime(f.rem), f.running || f.phase == PomoEngine.IDLE ? Graphics.COLOR_WHITE : 0xBBBBBB);
        Draw.statusLine(dc, cx, cy + (52 * s).toNumber(), cx - (61 * s).toNumber(), _small, Theme.status(f), 0xDDDDDD, f);
    }

    // Liquid surface at height `frac` inside a circle of radius r, as one polygon.
    private function drawWave(dc as Dc, cx as Number, cy as Number, r as Number, frac as Float, amp as Float, phase as Float, color as Number) as Void {
        var n = 18;
        var level = cy + r - 2 * r * frac;
        var top = [] as Array<[Numeric, Numeric]>;
        var bottom = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i <= n; i++) {
            var dx = -r + 2.0 * r * i / n;
            var half = Math.sqrt(r * r - dx * dx);
            var y = level + amp * Math.sin(2 * Math.PI * (dx / (r * 1.2) + phase));
            if (y < cy - half) {
                y = cy - half;
            } else if (y > cy + half) {
                y = cy + half;
            }
            top.add([cx + dx, y]);
            bottom.add([cx + dx, cy + half]);
        }
        for (var i = n; i >= 0; i--) {
            top.add(bottom[i]);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(top);
    }
}
