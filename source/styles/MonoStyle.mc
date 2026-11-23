import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// 3 Mono: hairline ring, sliding donut knob, JetBrains Mono, blinking cursor.
class MonoStyle extends Style {

    private var _timer;
    private var _label;

    function initialize() {
        Style.initialize();
        _timer = WatchUi.loadResource(Rez.Fonts.TimerMono);
        _label = WatchUi.loadResource(Rez.Fonts.LabelMono);
    }

    function draw(dc as Dc, f as Frame) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var s = dc.getWidth() / 390.0;
        Draw.clear(dc);
        var col = f.paused ? Theme.shade(f.color, 0.55) : f.color;

        var rS = cx - (40 * s).toNumber();
        dc.setPenWidth(2);
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, rS);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        var t = (8 * s).toNumber();
        for (var a = 0; a < 360; a += 90) {
            dc.drawLine(Draw.px(cx, rS - t, a), Draw.py(cy, rS - t, a), Draw.px(cx, rS + t, a), Draw.py(cy, rS + t, a));
        }

        dc.setPenWidth((4 * s).toNumber());
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        Draw.arcCw(dc, cx, cy, rS, 90, 360 * f.frac);
        var kx = Draw.px(cx, rS, 90 - 360 * f.frac);
        var ky = Draw.py(cy, rS, 90 - 360 * f.frac);
        dc.fillCircle(kx, ky, (12 * s).toNumber());
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(kx, ky, (5 * s).toNumber());

        // "// focus_" with a cursor that blinks every second (a space keeps the width).
        var cursor = (f.running && f.tick % 2 == 0) ? "_" : " ";
        Draw.text(dc, cx, cy - (60 * s).toNumber(), _label, "// " + Theme.phaseName(f.phase).toLower() + cursor, col);
        Draw.text(dc, cx, cy, _timer, Theme.formatTime(f.rem), f.running || f.phase == PomoEngine.IDLE ? Graphics.COLOR_WHITE : Theme.DIM);
        var status = f.running ? "ends " + Theme.clockText(f.end) : (f.paused ? "paused" : "press start");
        var below = Draw.statusLine(dc, cx, cy + (44 * s).toNumber(), cx - (50 * s).toNumber(), _label, status, Theme.DIM, f);

        // Daily goal as squares (two rows of 15 for big goals).
        var big = f.goal > 10;
        var sq = ((big ? 7 : 10) * s).toNumber();
        var pitch = ((big ? 10 : 16) * s).toNumber();
        var perRow = big ? 15 : f.goal;
        var y0 = cy + (70 * s).toNumber() + below; // a two-line task title pushes the squares down
        for (var i = 0; i < f.goal; i++) {
            var row = i / perRow;
            var inRow = (row == (f.goal - 1) / perRow) ? f.goal - row * perRow : perRow;
            var x = cx - (inRow * pitch - (pitch - sq)) / 2 + (i % perRow) * pitch;
            var y = y0 + row * pitch;
            if (i < f.today) {
                dc.setColor(Theme.GOAL, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, y, sq, sq);
            } else {
                dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                dc.drawRectangle(x, y, sq, sq);
            }
        }
        var rows = (f.goal + perRow - 1) / perRow;
        Draw.text(dc, cx, y0 + rows * pitch + (14 * s).toNumber(), _label,
            "set=" + f.cycle + "/" + f.every + "  streak=" + f.streak, Theme.DIM);
    }
}
