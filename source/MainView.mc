import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Draws the main screen with the style chosen in Settings.
class MainView extends WatchUi.View {

    private var _ctrl as PomoController;
    private var _style as Style? = null;
    private var _styleIdx as Number = -1;
    private var _offered as Boolean = false;
    private var _later as Timer.Timer?;

    function initialize(ctrl as PomoController) {
        View.initialize();
        _ctrl = ctrl;
    }

    // In task mode, the app opens on today's task list (once per launch, and only with no timer going).
    function onShow() as Void {
        if (_offered) {
            return;
        }
        _offered = true;
        if (TaskSync.enabled() && !_ctrl.hasTask() && _ctrl.phase() == PomoEngine.IDLE) {
            // Pushing a view from inside onShow isn't allowed: do it right after.
            var t = new Timer.Timer();
            t.start(method(:offerTasks), 50, false);
            _later = t;
        }
    }

    function offerTasks() as Void {
        var t = _later; // kept in a field so the timer isn't freed before it fires
        if (t != null) {
            t.stop();
            _later = null;
        }
        openTaskList(_ctrl, false);
    }

    function onUpdate(dc as Dc) as Void {
        var idx = _ctrl.styleIndex();
        if (idx != _styleIdx) {
            _style = null; // free the old style's fonts first
            _style = createStyle(idx);
            _styleIdx = idx;
        }
        (_style as Style).draw(dc, buildFrame(_ctrl, false));
    }
}

// START button: start/pause. Screen taps are ignored on purpose, so a stray
// touch can't stop the timer.
// UP / swipe down: menu   DOWN / swipe up: stats   BACK: exit
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _ctrl as PomoController;

    function initialize(ctrl as PomoController) {
        BehaviorDelegate.initialize();
        _ctrl = ctrl;
    }

    // Taps arrive as onSelect, which we leave unhandled; START is handled as a raw key.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _ctrl.toggle();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function onMenu() as Boolean {
        openMainMenu(_ctrl);
        return true;
    }

    function onPreviousPage() as Boolean {
        openMainMenu(_ctrl);
        return true;
    }

    function onNextPage() as Boolean {
        WatchUi.pushView(new StatsView(_ctrl), new StatsDelegate(), WatchUi.SLIDE_UP);
        return true;
    }
}
