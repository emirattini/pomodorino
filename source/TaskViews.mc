import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Task list and end-of-session summary (docs/tasks-spec.md §4.3).

// Opens the task list: a loading screen that turns into the list (or the cached one when offline).
// replace: take the place of the current view (a menu or the summary) instead of going on top.
function openTaskList(ctrl as PomoController, replace as Boolean) as Void {
    var view = new TaskLoadView(ctrl);
    if (replace) {
        WatchUi.switchToView(view, new TaskLoadDelegate(view), WatchUi.SLIDE_LEFT);
    } else {
        WatchUi.pushView(view, new TaskLoadDelegate(view), WatchUi.SLIDE_UP);
    }
}

function minutesText(m as Number) as String {
    return m >= 60 ? (m / 60).toString() + "h " + (m % 60).format("%02d") + "'" : m.toString() + "'";
}

class TaskLoadView extends WatchUi.View {

    private var _ctrl as PomoController;
    private var _visible as Boolean = false;
    private var _loading as Boolean = false;
    private var _error as String? = null;

    function initialize(ctrl as PomoController) {
        View.initialize();
        _ctrl = ctrl;
    }

    function onShow() as Void {
        _visible = true;
        if (!_loading && _error == null) {
            load();
        }
    }

    function onHide() as Void {
        _visible = false;
    }

    function load() as Void {
        _loading = true;
        _error = null;
        TaskSync.fetchTasks(method(:onTasks));
        WatchUi.requestUpdate();
    }

    function onTasks(code as Number, data as Dictionary or String or Null) as Void {
        _loading = false;
        var tasks = null;
        var title = "Today";
        if (code == 200 && data instanceof Dictionary && data["tasks"] instanceof Array) {
            tasks = data["tasks"] as Array;
            TaskSync.saveTasks(tasks);
            TaskSync.flush(); // the phone is reachable: send what's waiting
        } else {
            _error = TaskSync.errorText(code);
            tasks = TaskSync.cachedTasks();
            title = "Offline";
        }
        if (!_visible) {
            return;
        }
        if (tasks != null) {
            WatchUi.switchToView(buildTaskMenu(tasks, title), new TaskMenuDelegate(_ctrl, tasks), WatchUi.SLIDE_IMMEDIATE);
        } else {
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Dc) as Void {
        Draw.clear(dc);
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var err = _error;
        if (_loading || err == null) {
            Draw.text(dc, cx, cy, Graphics.FONT_SMALL, "Loading tasks…", Graphics.COLOR_WHITE);
            return;
        }
        Draw.text(dc, cx, cy - 40, Graphics.FONT_SMALL, "No tasks", Graphics.COLOR_WHITE);
        Draw.text(dc, cx, cy, Graphics.FONT_XTINY, err, Theme.FOCUS);
        Draw.text(dc, cx, cy + 50, Graphics.FONT_XTINY, "START retry", Theme.DIM);
        Draw.text(dc, cx, cy + 80, Graphics.FONT_XTINY, "BACK no task", Theme.DIM);
    }

    function retry() as Void {
        if (!_loading) {
            load();
        }
    }
}

class TaskLoadDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TaskLoadView;

    function initialize(view as TaskLoadView) {
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

function buildTaskMenu(tasks as Array, title as String) as WatchUi.Menu2 {
    var pending = TaskSync.pendingCount();
    if (tasks.size() == 0) {
        title = "No tasks today";
    } else if (pending > 0) {
        title += " · " + pending + " unsent";
    }
    var menu = new WatchUi.Menu2({ :title => title });
    for (var i = 0; i < tasks.size(); i++) {
        var t = tasks[i] as Dictionary;
        menu.addItem(new WatchUi.MenuItem(t["title"] as String, taskSubLabel(t), i, null));
    }
    menu.addItem(new WatchUi.MenuItem("No task", "Plain pomodoro", :none, null));
    menu.addItem(new WatchUi.MenuItem("Refresh", null, :refresh, null));
    return menu;
}

// "Work · est 30' · 15' done"
function taskSubLabel(t as Dictionary) as String? {
    var parts = [] as Array<String>;
    if (t["project"] instanceof String) {
        parts.add(t["project"] as String);
    }
    if (t["estimateMin"] instanceof Number) {
        parts.add("est " + minutesText(t["estimateMin"] as Number));
    }
    if (t["spentMin"] instanceof Number && (t["spentMin"] as Number) > 0) {
        parts.add(minutesText(t["spentMin"] as Number) + " done");
    }
    if (parts.size() == 0) {
        return null;
    }
    var s = parts[0];
    for (var i = 1; i < parts.size(); i++) {
        s += " · " + parts[i];
    }
    return s;
}

class TaskMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _ctrl as PomoController;
    private var _tasks as Array;

    function initialize(ctrl as PomoController, tasks as Array) {
        Menu2InputDelegate.initialize();
        _ctrl = ctrl;
        _tasks = tasks;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :refresh) {
            openTaskList(_ctrl, true);
        } else if (id instanceof Number) {
            _ctrl.startTask(_tasks[id] as Dictionary);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN); // "No task"
        }
    }
}

// ---- end of a task session ----

function openTaskSummary(ctrl as PomoController) as Void {
    var view = new TaskSummaryView(ctrl);
    WatchUi.switchToView(view, new TaskSummaryDelegate(view, ctrl), WatchUi.SLIDE_LEFT);
}

// Estimated vs actual time, then Complete task / Continue later. BACK goes back to the timer.
class TaskSummaryView extends WatchUi.View {

    var choice as Number = 0; // 0 complete, 1 later
    private var _ctrl as PomoController;

    function initialize(ctrl as PomoController) {
        View.initialize();
        _ctrl = ctrl;
    }

    function onUpdate(dc as Dc) as Void {
        Draw.clear(dc);
        var t = _ctrl.task;
        if (t == null) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var s = w / 390.0;
        var session = _ctrl.taskFocusMin();
        var before = t["spent"] instanceof Number ? t["spent"] as Number : 0;
        var actual = before + session;

        Draw.text(dc, cx, (h * 0.17).toNumber(), Graphics.FONT_XTINY,
            Draw.fit(dc, Graphics.FONT_XTINY, t["title"] as String, (w * 0.62).toNumber()), Graphics.COLOR_WHITE);

        var labelY = (h * 0.29).toNumber();
        var valueY = (h * 0.39).toNumber();
        if (t["est"] instanceof Number) {
            var est = t["est"] as Number;
            var dx = (75 * s).toNumber();
            Draw.text(dc, cx - dx, labelY, Graphics.FONT_XTINY, "ESTIMATED", Theme.DIM);
            Draw.text(dc, cx - dx, valueY, Graphics.FONT_MEDIUM, minutesText(est), Graphics.COLOR_WHITE);
            Draw.text(dc, cx + dx, labelY, Graphics.FONT_XTINY, "ACTUAL", Theme.DIM);
            Draw.text(dc, cx + dx, valueY, Graphics.FONT_MEDIUM, minutesText(actual), Graphics.COLOR_WHITE);
            var diff = actual - est;
            var line = diff == 0 ? "On estimate" : (diff > 0 ? "+" + minutesText(diff) + " over" : minutesText(-diff) + " under");
            Draw.text(dc, cx, (h * 0.49).toNumber(), Graphics.FONT_XTINY, line, diff > 0 ? Theme.FOCUS : Theme.SHORT);
        } else {
            Draw.text(dc, cx, labelY, Graphics.FONT_XTINY, "ACTUAL · NO ESTIMATE", Theme.DIM);
            Draw.text(dc, cx, valueY, Graphics.FONT_MEDIUM, minutesText(actual), Graphics.COLOR_WHITE);
        }
        var pom = t["pom"] as Number;
        Draw.text(dc, cx, (h * 0.575).toNumber(), Graphics.FONT_XTINY,
            "This session " + minutesText(session) + " · " + pom + (pom == 1 ? " pomodoro" : " pomodoros"), Theme.DIM);

        drawOption(dc, cx, (h * 0.70).toNumber(), s, "Complete task", choice == 0);
        drawOption(dc, cx, (h * 0.83).toNumber(), s, "Continue later", choice == 1);
    }

    private function drawOption(dc as Dc, cx as Number, y as Number, s as Float, label as String, selected as Boolean) as Void {
        if (selected) {
            var hw = (110 * s).toNumber();
            var hh = (21 * s).toNumber();
            dc.setPenWidth(2);
            dc.setColor(Theme.GOAL, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(cx - hw, y - hh, 2 * hw, 2 * hh, hh);
        }
        Draw.text(dc, cx, y, Graphics.FONT_XTINY, label, selected ? Theme.GOAL : Graphics.COLOR_LT_GRAY);
    }
}

class TaskSummaryDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TaskSummaryView;
    private var _ctrl as PomoController;

    function initialize(view as TaskSummaryView, ctrl as PomoController) {
        BehaviorDelegate.initialize();
        _view = view;
        _ctrl = ctrl;
    }

    function onPreviousPage() as Boolean {
        return move();
    }

    function onNextPage() as Boolean {
        return move();
    }

    private function move() as Boolean {
        _view.choice = 1 - _view.choice;
        WatchUi.requestUpdate();
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() != WatchUi.KEY_ENTER) {
            return false;
        }
        _ctrl.finishTask(_view.choice == 0);
        if (TaskSync.enabled()) {
            openTaskList(_ctrl, true); // pick the next task
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }
}
