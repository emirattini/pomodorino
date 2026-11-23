import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Full-screen live preview of each style. UP/DOWN browse, START saves, BACK cancels.
class StylePickerView extends WatchUi.View {

    var index as Number;
    private var _ctrl as PomoController;
    private var _style as Style? = null;
    private var _loaded as Number = -1;

    function initialize(ctrl as PomoController) {
        View.initialize();
        _ctrl = ctrl;
        index = ctrl.styleIndex();
    }

    function onUpdate(dc as Dc) as Void {
        if (_loaded != index) {
            _style = null;
            _style = createStyle(index);
            _loaded = index;
        }
        (_style as Style).draw(dc, buildFrame(_ctrl, true));

        // Name pill at the bottom edge
        var cx = dc.getWidth() / 2;
        var s = dc.getWidth() / 390.0;
        var y = dc.getHeight() - (40 * s).toNumber();
        var w = (150 * s).toNumber();
        var h = (32 * s).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - w / 2, y - h / 2, w, h, h / 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(cx - w / 2, y - h / 2, w, h, h / 2);
        dc.drawText(cx, y, Graphics.FONT_XTINY, (index + 1) + "/" + STYLE_COUNT + "  " + styleName(index).toUpper(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class StylePickerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as StylePickerView;
    private var _ctrl as PomoController;
    private var _item as WatchUi.MenuItem;

    function initialize(view as StylePickerView, ctrl as PomoController, item as WatchUi.MenuItem) {
        BehaviorDelegate.initialize();
        _view = view;
        _ctrl = ctrl;
        _item = item;
    }

    function onPreviousPage() as Boolean {
        _view.index = (_view.index + STYLE_COUNT - 1) % STYLE_COUNT;
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() as Boolean {
        _view.index = (_view.index + 1) % STYLE_COUNT;
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        _ctrl.setSetting("style", _view.index);
        _item.setSubLabel(styleName(_view.index));
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
