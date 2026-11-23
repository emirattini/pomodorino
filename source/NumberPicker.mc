import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// UP/DOWN (or swipe) change the value, START saves, BACK cancels.
class NumberPickerView extends WatchUi.View {

    var value as Number;
    private var _title as String;
    private var _unit as String;

    function initialize(title as String, value as Number, unit as String) {
        View.initialize();
        _title = title;
        self.value = value;
        _unit = unit;
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

        dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (125 * s).toNumber(), Graphics.FONT_SMALL, _title, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Arrows
        var a = (14 * s).toNumber();
        var up = cy - (78 * s).toNumber();
        var down = cy + (78 * s).toNumber();
        dc.setColor(Theme.FOCUS, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - a, up + a / 2], [cx + a, up + a / 2], [cx, up - a / 2]]);
        dc.fillPolygon([[cx - a, down - a / 2], [cx + a, down - a / 2], [cx, down + a / 2]]);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (8 * s).toNumber(), Graphics.FONT_NUMBER_HOT, value.toString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Theme.DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (118 * s).toNumber(), Graphics.FONT_XTINY, _unit, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + (150 * s).toNumber(), Graphics.FONT_XTINY, "START to save", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class NumberPickerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as NumberPickerView;
    private var _min as Number;
    private var _max as Number;
    private var _step as Number;
    private var _onValue as Method;

    function initialize(view as NumberPickerView, min as Number, max as Number, step as Number, onValue as Method) {
        BehaviorDelegate.initialize();
        _view = view;
        _min = min;
        _max = max;
        _step = step;
        _onValue = onValue;
    }

    private function change(delta as Number) as Void {
        var v = _view.value + delta;
        if (v > _max) {
            v = _min;
        } else if (v < _min) {
            v = _max;
        }
        _view.value = v;
        WatchUi.requestUpdate();
    }

    function onPreviousPage() as Boolean {
        change(_step);
        return true;
    }

    function onNextPage() as Boolean {
        change(-_step);
        return true;
    }

    function onSelect() as Boolean {
        _onValue.invoke(_view.value);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
