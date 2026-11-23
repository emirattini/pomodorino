import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Last 7 days as bars against the goal, plus streak and week total.
class StatsView extends WatchUi.View {

    private var _ctrl as PomoController;

    function initialize(ctrl as PomoController) {
        View.initialize();
        _ctrl = ctrl;
    }

    function onUpdate(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var s = dc.getWidth() / 416.0;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var goal = _ctrl.goal();
        var days = _ctrl.stats.lastDays(7, goal);

        dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (150 * s).toNumber(), Graphics.FONT_XTINY, "LAST 7 DAYS", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var maxV = goal;
        var week = 0;
        for (var i = 0; i < days.size(); i++) {
            var c = (days[i] as Array)[0] as Number;
            week += c;
            if (c > maxV) {
                maxV = c;
            }
        }
        if (maxV < 1) {
            maxV = 1;
        }

        var chartW = (290 * s).toNumber();
        var maxH = (150 * s).toNumber();
        var base = cy + (55 * s).toNumber();
        var barW = (28 * s).toNumber();
        var step = (chartW - barW) / 6;
        var left = cx - chartW / 2;
        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);

        for (var i = 0; i < days.size(); i++) {
            var d = days[i] as Array;
            var count = d[0] as Number;
            var dayGoal = d[1] as Number;
            var x = left + i * step;
            var h = (count * maxH) / maxV;
            var isToday = (i == days.size() - 1);

            dc.setColor(Theme.TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, base - maxH, barW, maxH);
            if (h > 0) {
                dc.setColor((dayGoal > 0 && count >= dayGoal) ? Theme.SHORT : Theme.FOCUS, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, base - h, barW, h);
            }
            dc.setColor(isToday ? Graphics.COLOR_WHITE : Theme.DIM, Graphics.COLOR_TRANSPARENT);
            if (count > 0) {
                dc.drawText(x + barW / 2, base - h - xtinyH / 2 - 2, Graphics.FONT_XTINY, count.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            dc.drawText(x + barW / 2, base + xtinyH / 2 + 4, Graphics.FONT_XTINY, d[2] as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Dashed goal line
        var gy = base - (goal * maxH) / maxV;
        dc.setColor(Theme.GOAL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var gx = left - 6; gx < left + chartW + 6; gx += 12) {
            dc.drawLine(gx, gy, gx + 6, gy);
        }

        var streak = _ctrl.stats.streak(goal);
        dc.setColor(Theme.GOAL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (115 * s).toNumber(), Graphics.FONT_SMALL, "Streak " + streak + (streak == 1 ? " day" : " days"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (152 * s).toNumber(), Graphics.FONT_XTINY, week.toString() + " in 7 days, goal " + goal,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class StatsDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    function onSelect() as Boolean {
        return onBack();
    }

    function onPreviousPage() as Boolean {
        return onBack();
    }
}
