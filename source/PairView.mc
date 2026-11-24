import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// "Connect Todoist": asks the server for a pairing code, has the phone open the connect page
// (Garmin Connect shows a notification), then checks every few seconds until the login is done.
// See server/src/pair.rs for the other side.

function openPairing(ctrl as PomoController) as Void {
    var view = new PairView(ctrl);
    WatchUi.switchToView(view, new PairDelegate(view), WatchUi.SLIDE_LEFT);
}

class PairView extends WatchUi.View {

    enum { STARTING, WAITING, CONNECTED, FAILED }

    const POLL_MS = 3000;
    const TIMEOUT_SEC = 15 * 60;

    private var _ctrl as PomoController;
    private var _state as Number = STARTING;
    private var _message as String = "";
    private var _code as String = "";
    private var _key as String = "";
    private var _url as String = "";
    private var _startedAt as Number = 0;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _active as Boolean = false;

    function initialize(ctrl as PomoController) {
        View.initialize();
        _ctrl = ctrl;
    }

    function onShow() as Void {
        _active = true;
        if (_state == STARTING) {
            start();
        } else if (_state == WAITING) {
            poll();
        }
    }

    function onHide() as Void {
        _active = false;
        _timer.stop();
    }

    // START: try again after a failure, or send the phone notification again while waiting.
    function retry() as Void {
        if (_state == FAILED) {
            start();
        } else if (_state == WAITING) {
            openOnPhone();
        }
    }

    private function start() as Void {
        _state = STARTING;
        Communications.makeWebRequest(TaskSync.baseUrl() + "/v1/pair", {}, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onStarted));
        WatchUi.requestUpdate();
    }

    function onStarted(code as Number, data as Dictionary or String or Null) as Void {
        if (!_active) {
            return;
        }
        if (code != 200 || !(data instanceof Dictionary) || !(data["deviceKey"] instanceof String)) {
            fail(TaskSync.errorText(code));
            return;
        }
        _code = data["code"] as String;
        _key = data["deviceKey"] as String;
        _url = data["connectUrl"] as String;
        _startedAt = Time.now().value();
        _state = WAITING;
        openOnPhone();
        _timer.start(method(:poll), POLL_MS, false);
        WatchUi.requestUpdate();
    }

    private function openOnPhone() as Void {
        Communications.openWebPage(_url, { "code" => _code }, null);
    }

    function poll() as Void {
        if (!_active || _state != WAITING) {
            return;
        }
        if (Time.now().value() - _startedAt > TIMEOUT_SEC) {
            fail("The code expired");
            return;
        }
        Communications.makeWebRequest(TaskSync.baseUrl() + "/v1/pair/status", null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => { "X-Api-Key" => _key },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:onStatus));
    }

    function onStatus(code as Number, data as Dictionary or String or Null) as Void {
        if (!_active || _state != WAITING) {
            return;
        }
        if (code == 200 && data instanceof Dictionary && data["linked"] == true) {
            TaskSync.setDeviceKey(_key);
            _state = CONNECTED;
            WatchUi.requestUpdate();
            _timer.start(method(:showTasks), 1500, false);
            return;
        }
        if (code == 404) {
            fail("The code expired");
            return;
        }
        // Not yet, or the phone is briefly out of reach: ask again in a moment.
        _timer.start(method(:poll), POLL_MS, false);
    }

    function showTasks() as Void {
        if (_active) {
            openTaskList(_ctrl, true);
        }
    }

    private function fail(message as String) as Void {
        _timer.stop();
        _state = FAILED;
        _message = message;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        Draw.clear(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        if (_state == STARTING) {
            Draw.text(dc, cx, h / 2, Graphics.FONT_SMALL, "Connecting…", Graphics.COLOR_WHITE);
        } else if (_state == WAITING) {
            Draw.text(dc, cx, (h * 0.24).toNumber(), Graphics.FONT_SMALL, "Check your phone", Graphics.COLOR_WHITE);
            Draw.text(dc, cx, (h * 0.36).toNumber(), Graphics.FONT_XTINY, "Open the notification and", Theme.DIM);
            Draw.text(dc, cx, (h * 0.44).toNumber(), Graphics.FONT_XTINY, "log in to Todoist", Theme.DIM);
            Draw.text(dc, cx, (h * 0.58).toNumber(), Graphics.FONT_MEDIUM, _code, Theme.GOAL);
            Draw.text(dc, cx, (h * 0.72).toNumber(), Graphics.FONT_XTINY, "START send again", Theme.DIM);
            Draw.text(dc, cx, (h * 0.80).toNumber(), Graphics.FONT_XTINY, "BACK cancel", Theme.DIM);
        } else if (_state == CONNECTED) {
            Draw.text(dc, cx, (h * 0.45).toNumber(), Graphics.FONT_SMALL, "Connected", Theme.SHORT);
            Draw.text(dc, cx, (h * 0.56).toNumber(), Graphics.FONT_XTINY, "Loading today's tasks", Theme.DIM);
        } else {
            Draw.text(dc, cx, (h * 0.40).toNumber(), Graphics.FONT_SMALL, "Not connected", Graphics.COLOR_WHITE);
            Draw.text(dc, cx, (h * 0.52).toNumber(), Graphics.FONT_XTINY, _message, Theme.FOCUS);
            Draw.text(dc, cx, (h * 0.68).toNumber(), Graphics.FONT_XTINY, "START try again", Theme.DIM);
            Draw.text(dc, cx, (h * 0.76).toNumber(), Graphics.FONT_XTINY, "BACK cancel", Theme.DIM);
        }
    }
}

class PairDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PairView;

    function initialize(view as PairView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_ENTER) {
            _view.retry();
            return true;
        }
        return false;
    }
}
