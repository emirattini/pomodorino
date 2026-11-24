import Toybox.Lang;
import Toybox.WatchUi;

function openMainMenu(ctrl as PomoController) as Void {
    var menu = new WatchUi.Menu2({ :title => "Pomodorino" });
    if (ctrl.hasTask()) {
        menu.addItem(new WatchUi.MenuItem("Finish task", ctrl.taskTitle(), :finish, null));
    } else if (TaskSync.enabled()) {
        menu.addItem(new WatchUi.MenuItem("Choose task", null, :choose, null));
    }
    if (ctrl.isBreak()) {
        menu.addItem(new WatchUi.MenuItem("Skip break", "Start focusing now", :skip, null));
    }
    if (ctrl.phase() != PomoEngine.IDLE) {
        menu.addItem(new WatchUi.MenuItem("Restart session", "Reset this timer", :restart, null));
        if (!ctrl.hasTask()) { // with a task, "Finish task" ends the set
            menu.addItem(new WatchUi.MenuItem("Stop", "End the set", :stop, null));
        }
    }
    menu.addItem(new WatchUi.MenuItem("Statistics", null, :stats, null));
    menu.addItem(new WatchUi.MenuItem("Settings", null, :settings, null));
    if (TaskSync.deviceKey().equals("")) {
        menu.addItem(new WatchUi.MenuItem("Connect Todoist", "Work on today's tasks", :connect, null));
    } else {
        menu.addItem(new WatchUi.MenuItem("Disconnect Todoist", null, :disconnect, null));
    }
    menu.addItem(new WatchUi.MenuItem("Credits", null, :credits, null));
    WatchUi.pushView(menu, new MainMenuDelegate(ctrl), WatchUi.SLIDE_UP);
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _ctrl as PomoController;

    function initialize(ctrl as PomoController) {
        Menu2InputDelegate.initialize();
        _ctrl = ctrl;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :finish) {
            openTaskSummary(_ctrl);
        } else if (id == :choose) {
            openTaskList(_ctrl, true);
        } else if (id == :skip) {
            _ctrl.skipBreak();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :restart) {
            _ctrl.restartSession();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :stop) {
            _ctrl.stopAll();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :stats) {
            WatchUi.pushView(new StatsView(_ctrl), new StatsDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :settings) {
            openSettings(_ctrl);
        } else if (id == :connect) {
            openPairing(_ctrl);
        } else if (id == :disconnect) {
            WatchUi.pushView(new WatchUi.Confirmation("Disconnect Todoist?"),
                new DisconnectConfirmation(_ctrl), WatchUi.SLIDE_LEFT);
        } else if (id == :credits) {
            var view = new CreditsView();
            WatchUi.pushView(view, new CreditsDelegate(view), WatchUi.SLIDE_LEFT);
        }
    }
}

// ---- Settings ----

// key -> [title, min, max, step, unit]
function settingSpec(key as String) as Array {
    if (key.equals("focus")) {
        return ["Focus", 5, 90, 5, "min"];
    }
    if (key.equals("short")) {
        return ["Short break", 1, 30, 1, "min"];
    }
    if (key.equals("long")) {
        return ["Long break", 5, 60, 5, "min"];
    }
    if (key.equals("every")) {
        return ["Long break every", 2, 8, 1, "pomodoros"];
    }
    return ["Daily goal", 1, 30, 1, "pomodoros"];
}

function settingLabel(ctrl as PomoController, key as String) as String {
    return (ctrl.settings[key] as Number).toString() + " " + (settingSpec(key)[4] as String);
}

function openSettings(ctrl as PomoController) as Void {
    var menu = new WatchUi.Menu2({ :title => "Settings" });
    menu.addItem(new WatchUi.MenuItem("Style", styleName(ctrl.styleIndex()), "style", null));
    var keys = ["focus", "short", "long", "every", "goal"];
    for (var i = 0; i < keys.size(); i++) {
        var key = keys[i];
        menu.addItem(new WatchUi.MenuItem(settingSpec(key)[0] as String, settingLabel(ctrl, key), key, null));
    }
    menu.addItem(new WatchUi.ToggleMenuItem("Auto-start", "Next session starts itself", "auto",
        ctrl.settings["auto"] as Boolean, null));
    WatchUi.pushView(menu, new SettingsMenuDelegate(ctrl), WatchUi.SLIDE_LEFT);
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _ctrl as PomoController;

    function initialize(ctrl as PomoController) {
        Menu2InputDelegate.initialize();
        _ctrl = ctrl;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var key = item.getId() as String;
        if (key.equals("style")) {
            var picker = new StylePickerView(_ctrl);
            WatchUi.pushView(picker, new StylePickerDelegate(picker, _ctrl, item), WatchUi.SLIDE_LEFT);
            return;
        }
        if (key.equals("auto")) {
            _ctrl.setSetting(key, (item as WatchUi.ToggleMenuItem).isEnabled());
            return;
        }
        var spec = settingSpec(key);
        var editor = new SettingEditor(_ctrl, item, key);
        var view = new NumberPickerView(spec[0] as String, _ctrl.settings[key] as Number, spec[4] as String);
        WatchUi.pushView(view,
            new NumberPickerDelegate(view, spec[1] as Number, spec[2] as Number, spec[3] as Number, editor.method(:onValue)),
            WatchUi.SLIDE_LEFT);
    }
}

class SettingEditor {

    private var _ctrl as PomoController;
    private var _item as WatchUi.MenuItem;
    private var _key as String;

    function initialize(ctrl as PomoController, item as WatchUi.MenuItem, key as String) {
        _ctrl = ctrl;
        _item = item;
        _key = key;
    }

    function onValue(value as Number) as Void {
        _ctrl.setSetting(_key, value);
        _item.setSubLabel(settingLabel(_ctrl, _key));
    }
}

// "Disconnect Todoist?" Yes: the server forgets this watch (and the account, if it was its last
// watch) and Todoist's access is revoked. A task in progress is dropped, not sent.
class DisconnectConfirmation extends WatchUi.ConfirmationDelegate {

    private var _ctrl as PomoController;

    function initialize(ctrl as PomoController) {
        ConfirmationDelegate.initialize();
        _ctrl = ctrl;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _ctrl.dropTask();
            TaskSync.disconnect();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE); // the menu, under the confirmation
        }
        return true;
    }
}
