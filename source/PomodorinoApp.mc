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

    // The color of the system's selection marker next to our glance (API 4.0+, on devices that
    // support glance themes, like the Forerunner 165). Others ignore it.
    (:glance)
    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_RED;
    }

    function getServiceDelegate() {
        return [new PomoServiceDelegate()];
    }
}
