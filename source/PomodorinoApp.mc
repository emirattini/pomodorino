import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:background, :glance)
class PomodorinoApp extends Application.AppBase {

    // onStart/onStop also run for the background process; only the
    // foreground app calls getInitialView().
    private var _foreground as Boolean = false;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
        if (_foreground) {
            getController().onExit();
        }
    }

    function getInitialView() {
        _foreground = true;
        var ctrl = getController();
        ctrl.onEnter();
        return [new MainView(ctrl), new MainDelegate(ctrl)];
    }

    // The quick view in the widget list (Glance.mc).
    (:glance)
    function getGlanceView() {
        return [new PomoGlanceView()];
    }

    function getServiceDelegate() {
        return [new PomoServiceDelegate()];
    }
}
