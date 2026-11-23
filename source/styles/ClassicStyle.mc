import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// 5 Classic: serif numerals, one dot per minute, little tomatoes for the daily goal.
class ClassicStyle extends Style {

    const TOMATO = 0xE4573D;
    const CREAM = 0xF4E9D8;
    const SAGE = 0x8FB996;
    const SKY = 0x7FA7C9;

    private var _timer;
    private var _label;
    private var _small;

    function initialize() {
        Style.initialize();
        _timer = WatchUi.loadResource(Rez.Fonts.TimerClassic);
        _label = WatchUi.loadResource(Rez.Fonts.LabelClassic);
        _small = WatchUi.loadResource(Rez.Fonts.SmallClassic);
    }

    function draw(dc as Dc, f as Frame) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var s = dc.getWidth() / 390.0;
        Draw.clear(dc);
        var pcol = f.phase == PomoEngine.SHORT_BREAK ? SAGE : (f.phase == PomoEngine.LONG_BREAK ? SKY : TOMATO);

        // One dot per minute of the session (at most 60).
        var rS = cx - (46 * s).toNumber();
        var n = f.minutes < 5 ? 5 : (f.minutes > 60 ? 60 : f.minutes);
        var lit = (f.frac * n).toNumber();
        for (var i = 0; i < n; i++) {
            var a = 90 - i * 360.0 / n;
            var x = Draw.px(cx, rS, a);
            var y = Draw.py(cy, rS, a);
            if (i < lit) {
                dc.setColor(pcol, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, (5 * s).toNumber());
            } else if (i == lit && f.running) {
                dc.setColor(Theme.shade(pcol, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, ((f.tick % 2 == 0 ? 9 : 7) * s).toNumber());
                dc.setColor(CREAM, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, (5 * s).toNumber());
            } else {
                dc.setColor(0x4A4038, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, (3 * s).toNumber());
            }
        }

        drawTomatoes(dc, cx, cy, s, f);

        Draw.text(dc, cx, cy - (62 * s).toNumber(), _label, f.paused ? "Paused" : Theme.phaseTitle(f.phase), pcol);
        Draw.text(dc, cx, cy + (2 * s).toNumber(), _timer, Theme.formatTime(f.rem),
            f.running || f.phase == PomoEngine.IDLE ? CREAM : Theme.shade(CREAM, 0.55));
        var stats = f.today.toString() + " of " + f.goal + " today";
        if (f.streak > 0) {
            stats += "  ·  " + f.streak + " day streak";
        }
        Draw.text(dc, cx, cy + (62 * s).toNumber(), _small, stats, Theme.shade(CREAM, 0.7));
        var status = f.running ? "until " + Theme.clockText(f.end) : (f.paused ? "" : "press start");
        Draw.statusLine(dc, cx, cy + (88 * s).toNumber(), _small, status, Theme.shade(CREAM, 0.45), f);
    }

    // The daily goal as tomatoes along the bottom edge.
    private function drawTomatoes(dc as Dc, cx as Number, cy as Number, s as Float, f as Frame) as Void {
        var small = f.goal > 12;
        var step = small ? 132.0 / (f.goal - 1) : 11.0;
        var r = ((small ? 5 : 7) * s).toNumber();
        var l = r * 5 / 7;
        var rr = cx - (16 * s).toNumber();
        for (var i = 0; i < f.goal; i++) {
            var a = 270 + (i - (f.goal - 1) / 2.0) * step;
            var x = Draw.px(cx, rr, a);
            var y = Draw.py(cy, rr, a);
            var done = i < f.today;
            dc.setColor(done ? TOMATO : 0x3A2E28, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, r);
            dc.setColor(done ? SAGE : 0x2E3A30, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x - l, y - r + 1], [x, y - r + 3 * l / 5], [x + l, y - r + 1], [x, y - r - 2 * l / 5]]);
        }
    }
}
