import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

// A controller whose clock the test sets: nowSec() and today() are the controller's only clock reads.
class TestController extends PomoController {

    var clock as Number;
    var midnight as Number;

    function initialize(start as Number) {
        clock = start;
        midnight = Time.today().value();
        PomoController.initialize();
    }

    function nowSec() as Number {
        return clock;
    }

    function today() as Number {
        return midnight;
    }

    function wait(sec as Number) as Void {
        clock += sec;
    }
}

// PomoController: what the buttons do to the timer, and what a task session records and sends.
// Every test starts from an empty app (default settings, no history, no task, empty queue) and puts the
// simulator's data back at the end. Finishing a task calls TaskSync.flush(), so each test first makes sure
// the watch has no server key: nothing can leave the simulator.
module ControllerTest {

    const KEYS = ["state", "settings", "task", "hist", "pending", "taskCache", "deviceKey"];
    const NOON_OFFSET = 43200;

    function begin() as Dictionary {
        var key = Application.Properties.getValue("apiKey");
        var saved = { "storage" => Check.stash(KEYS), "apiKey" => (key instanceof String) ? key : "" };
        for (var i = 0; i < KEYS.size(); i++) {
            Application.Storage.deleteValue(KEYS[i]);
        }
        Application.Properties.setValue("apiKey", "");
        return saved;
    }

    function end(saved as Dictionary) as Void {
        Check.restore(saved["storage"] as Dictionary);
        Application.Properties.setValue("apiKey", saved["apiKey"] as String);
    }

    function offline(logger as Logger) as Boolean {
        return Check.eq(logger, "offline: no server key in the test", TaskSync.enabled(), false);
    }

    // Noon today: whole hours either way stay on the same day.
    function noon() as Number {
        return Time.today().value() + NOON_OFFSET;
    }

    function serverTask(id as String, spent as Number) as Dictionary {
        return { "id" => id, "title" => "Task " + id, "estimateMin" => 50, "spentMin" => spent };
    }

    function task(c as PomoController) as Dictionary {
        return c.task as Dictionary;
    }

    function queued(i as Number) as Dictionary {
        return TaskSync.queue()[i] as Dictionary;
    }

    function session(i as Number) as Dictionary {
        return queued(i)["b"] as Dictionary;
    }

    // A task left selected from yesterday, as Storage holds it.
    function yesterdaysTask(focusSec as Number, pomodoros as Number) as Dictionary {
        var y = Time.today().value() - 86400;
        return {
            "id" => "t1", "title" => "Task t1", "est" => 50, "spent" => 10, "sid" => "old-session",
            "start" => y + 9 * 3600, "foc" => focusSec, "pom" => pomodoros, "int" => false, "day" => y,
            "last" => y + 11 * 3600
        };
    }

    // ---- the timer ----

    (:test)
    function startPauseResume(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 0));
        c.toggle();
        var ok = Check.eq(logger, "phase", c.phase(), PomoEngine.FOCUS)
            && Check.eq(logger, "running", c.isRunning(), true)
            && Check.eq(logger, "ends", c.endTime(), noon() + 1500)
            && Check.eq(logger, "task started", task(c)["start"], noon());
        c.wait(600);
        c.toggle();
        ok = ok && Check.eq(logger, "paused", c.isPaused(), true)
            && Check.eq(logger, "left when paused", c.remaining(), 900);
        c.wait(3600); // paused time doesn't count
        c.toggle();
        ok = ok && Check.eq(logger, "ends after resume", c.endTime(), noon() + 4200 + 900)
            && Check.eq(logger, "task start kept", task(c)["start"], noon());
        end(saved);
        return ok;
    }

    (:test)
    function finishedFocusIsCounted(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 0));
        c.toggle();
        c.wait(1500);
        var ended = c.tick(false);
        var ok = Check.eq(logger, "ended", ended, PomoEngine.FOCUS)
            && Check.eq(logger, "today's pomodoros", c.stats.todayCount(), 1)
            && Check.eq(logger, "task pomodoros", task(c)["pom"], 1)
            && Check.eq(logger, "task focus s", task(c)["foc"], 1500)
            && Check.eq(logger, "task last", task(c)["last"], noon() + 1500)
            && Check.eq(logger, "phase", c.phase(), PomoEngine.SHORT_BREAK)
            && Check.eq(logger, "waits for START", c.isRunning(), false)
            && Check.eq(logger, "saved", (Application.Storage.getValue("state") as Dictionary)["ph"], PomoEngine.SHORT_BREAK);
        end(saved);
        return ok;
    }

    (:test)
    function skipBreakStartsTheFocus(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.toggle();
        c.skipBreak(); // in a focus: does nothing
        var ok = Check.eq(logger, "still focus", c.endTime(), noon() + 1500);
        c.wait(1500);
        c.tick(false);
        c.wait(60);
        c.skipBreak();
        ok = ok && Check.eq(logger, "phase", c.phase(), PomoEngine.FOCUS)
            && Check.eq(logger, "running", c.isRunning(), true)
            && Check.eq(logger, "ends", c.endTime(), noon() + 1560 + 1500)
            && Check.eq(logger, "pomodoros in the set", c.cycle(), 1);
        end(saved);
        return ok;
    }

    (:test)
    function stopResetsTheSet(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.toggle();
        c.wait(1500);
        c.tick(false);
        c.stopAll();
        var ok = Check.eq(logger, "phase", c.phase(), PomoEngine.IDLE)
            && Check.eq(logger, "pomodoros in the set", c.cycle(), 0)
            && Check.eq(logger, "shows a full focus", c.remaining(), 1500)
            && Check.eq(logger, "today's pomodoros kept", c.stats.todayCount(), 1);
        end(saved);
        return ok;
    }

    // A new duration applies to a session that hasn't started; a running one keeps its end.
    (:test)
    function settingsApplyToTheNextSession(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.toggle();
        c.setSetting("focus", 30);
        var ok = Check.eq(logger, "running focus keeps its end", c.remaining(), 1500);
        c.wait(1500);
        c.tick(false);
        c.setSetting("short", 10);
        ok = ok && Check.eq(logger, "waiting break", c.remaining(), 600)
            && Check.eq(logger, "saved", (Application.Storage.getValue("settings") as Dictionary)["short"], 10);
        c.setSetting("goal", 3);
        ok = ok && Check.eq(logger, "today's goal", c.stats.goalOn(Stats.dayKey(noon())), 3);
        c.stopAll();
        ok = ok && Check.eq(logger, "next focus", c.remaining(), 1800);
        end(saved);
        return ok;
    }

    // ---- focus time on a task ----

    // Rounded down to the minute, except that a pomodoro cut short after more than 30 s counts as 1.
    (:test)
    function focusMinutes(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 0));
        c.toggle();
        c.wait(20);
        var ok = Check.eq(logger, "20 s", c.taskFocusMin(), 0);
        c.wait(15);
        ok = ok && Check.eq(logger, "35 s", c.taskFocusMin(), 1);
        c.wait(565);
        ok = ok && Check.eq(logger, "10 min", c.taskFocusMin(), 10);
        c.toggle();
        c.wait(3600);
        ok = ok && Check.eq(logger, "paused an hour", c.taskFocusMin(), 10);
        end(saved);
        return ok;
    }

    (:test)
    function restartKeepsTheFocusTime(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 0));
        c.toggle();
        c.wait(600);
        c.restartSession();
        var ok = Check.eq(logger, "task focus s", task(c)["foc"], 600)
            && Check.eq(logger, "interrupted", task(c)["int"], true)
            && Check.eq(logger, "ready", c.isRunning() || c.isPaused(), false)
            && Check.eq(logger, "full focus again", c.remaining(), 1500)
            && Check.eq(logger, "minutes", c.taskFocusMin(), 10);
        end(saved);
        return ok;
    }

    // ---- finishing a task ----

    // One pomodoro, a break, then 10 minutes of the next: one session and the completion, in that order.
    (:test)
    function finishQueuesTheSessionThenTheCompletion(logger as Logger) as Boolean {
        var saved = begin();
        if (!offline(logger)) {
            end(saved);
            return false;
        }
        TaskSync.saveTasks([serverTask("t1", 10), serverTask("t2", 0)]);
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 10));
        var sid = task(c)["sid"];
        c.toggle();
        c.wait(1500);
        c.tick(false);
        c.toggle();
        c.wait(300);
        c.tick(false);
        c.toggle();
        c.wait(600);
        c.finishTask(true);
        var s = session(0);
        var ok = Check.eq(logger, "queued", TaskSync.pendingCount(), 2)
            && Check.eq(logger, "kind", queued(0)["k"], "s")
            && Check.eq(logger, "session id", s["sessionId"], sid)
            && Check.eq(logger, "task id", s["taskId"], "t1")
            && Check.eq(logger, "focus min", s["focusMin"], 35)
            && Check.eq(logger, "pomodori", s["pomodori"], 1)
            && Check.eq(logger, "interrupted", s["interrupted"], true)
            && Check.eq(logger, "started", s["startedAt"], TaskSync.iso(noon()))
            && Check.eq(logger, "ended", s["endedAt"], TaskSync.iso(noon() + 2400))
            && Check.eq(logger, "then complete", queued(1)["k"], "c")
            && Check.eq(logger, "complete id", queued(1)["id"], "t1")
            && Check.eq(logger, "left in the list", (TaskSync.cachedTasks() as Array).size(), 1)
            && Check.eq(logger, "no task", c.hasTask(), false)
            && Check.eq(logger, "task forgotten", Application.Storage.getValue("task"), null)
            && Check.eq(logger, "timer stopped", c.phase(), PomoEngine.IDLE);
        end(saved);
        return ok;
    }

    (:test)
    function continueLaterAddsTheMinutesToTheList(logger as Logger) as Boolean {
        var saved = begin();
        if (!offline(logger)) {
            end(saved);
            return false;
        }
        TaskSync.saveTasks([serverTask("t1", 10)]);
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 10));
        c.toggle();
        c.wait(1500);
        c.tick(false);
        c.finishTask(false);
        var ok = Check.eq(logger, "queued", TaskSync.pendingCount(), 1)
            && Check.eq(logger, "focus min", session(0)["focusMin"], 25)
            && Check.eq(logger, "interrupted", session(0)["interrupted"], false)
            && Check.eq(logger, "minutes in the list",
                ((TaskSync.cachedTasks() as Array)[0] as Dictionary)["spentMin"], 35);
        end(saved);
        return ok;
    }

    // No focus time: no session (it would be an empty Todoist comment), but Complete still goes.
    (:test)
    function finishWithoutFocusSendsNoSession(logger as Logger) as Boolean {
        var saved = begin();
        if (!offline(logger)) {
            end(saved);
            return false;
        }
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 0));
        c.finishTask(false);
        var ok = Check.eq(logger, "nothing queued", TaskSync.pendingCount(), 0);
        c.startTask(serverTask("t2", 0));
        c.finishTask(true);
        ok = ok && Check.eq(logger, "only complete", TaskSync.pendingCount(), 1)
            && Check.eq(logger, "kind", queued(0)["k"], "c");
        end(saved);
        return ok;
    }

    // ---- a task across days ----

    // Yesterday's time goes as its own session (one Todoist comment per day); today starts at zero.
    (:test)
    function newDaySendsYesterdaysTime(logger as Logger) as Boolean {
        var saved = begin();
        if (!offline(logger)) {
            end(saved);
            return false;
        }
        var y = yesterdaysTask(3000, 2);
        Application.Storage.setValue("task", y);
        TaskSync.saveTasks([serverTask("t1", 10)]);
        var c = new TestController(noon());
        c.newDay();
        var s = session(0);
        var t = task(c);
        var ok = Check.eq(logger, "queued", TaskSync.pendingCount(), 1)
            && Check.eq(logger, "session id", s["sessionId"], "old-session")
            && Check.eq(logger, "focus min", s["focusMin"], 50)
            && Check.eq(logger, "pomodori", s["pomodori"], 2)
            && Check.eq(logger, "started", s["startedAt"], TaskSync.iso(y["start"] as Number))
            && Check.eq(logger, "ended at the last focus", s["endedAt"], TaskSync.iso(y["last"] as Number))
            && Check.eq(logger, "spent so far", t["spent"], 60)
            && Check.eq(logger, "list minutes", ((TaskSync.cachedTasks() as Array)[0] as Dictionary)["spentMin"], 60)
            && Check.eq(logger, "new session id", (t["sid"] as String).equals("old-session"), false)
            && Check.eq(logger, "today's focus", t["foc"], 0)
            && Check.eq(logger, "today's pomodoros", t["pom"], 0)
            && Check.eq(logger, "not started today", t["start"], 0)
            && Check.eq(logger, "day", t["day"], Time.today().value())
            && Check.eq(logger, "asks Still working on", c.askContinue, true);
        end(saved);
        return ok;
    }

    (:test)
    function newDayWithNothingYesterday(logger as Logger) as Boolean {
        var saved = begin();
        if (!offline(logger)) {
            end(saved);
            return false;
        }
        Application.Storage.setValue("task", yesterdaysTask(0, 0));
        var c = new TestController(noon());
        c.newDay();
        var ok = Check.eq(logger, "nothing queued", TaskSync.pendingCount(), 0)
            && Check.eq(logger, "spent unchanged", task(c)["spent"], 10)
            && Check.eq(logger, "asks Still working on", c.askContinue, true);
        end(saved);
        return ok;
    }

    // A pomodoro running across midnight counts for today when it ends.
    (:test)
    function pomodoroRunningOvernightCountsForToday(logger as Logger) as Boolean {
        var saved = begin();
        if (!offline(logger)) {
            end(saved);
            return false;
        }
        Application.Storage.setValue("task", yesterdaysTask(1500, 1));
        Application.Storage.setValue("state",
            { "ph" => PomoEngine.FOCUS, "run" => true, "end" => noon() + 600, "rem" => 0, "rdy" => false, "cyc" => 1 });
        var c = new TestController(noon());
        c.newDay();
        var ok = Check.eq(logger, "yesterday's session", session(0)["focusMin"], 25)
            && Check.eq(logger, "today starts now", task(c)["start"], noon());
        c.wait(600);
        c.tick(false);
        ok = ok && Check.eq(logger, "today's pomodoros", task(c)["pom"], 1)
            && Check.eq(logger, "today's focus s", task(c)["foc"], 1500)
            && Check.eq(logger, "still one session queued", TaskSync.pendingCount(), 1);
        end(saved);
        return ok;
    }

    (:test)
    function sameDayChangesNothing(logger as Logger) as Boolean {
        var saved = begin();
        var c = new TestController(noon());
        c.startTask(serverTask("t1", 0));
        var sid = task(c)["sid"];
        c.newDay();
        var ok = Check.eq(logger, "no question", c.askContinue, false)
            && Check.eq(logger, "same session", task(c)["sid"], sid)
            && Check.eq(logger, "nothing queued", TaskSync.pendingCount(), 0);
        end(saved);
        return ok;
    }

    // A task selected before tasks had days: days are counted from now on, without asking.
    (:test)
    function taskFromAnOlderVersion(logger as Logger) as Boolean {
        var saved = begin();
        var old = yesterdaysTask(600, 0);
        old.remove("day");
        Application.Storage.setValue("task", old);
        var c = new TestController(noon());
        c.newDay();
        var ok = Check.eq(logger, "day", task(c)["day"], Time.today().value())
            && Check.eq(logger, "no question", c.askContinue, false)
            && Check.eq(logger, "time kept", task(c)["foc"], 600)
            && Check.eq(logger, "nothing queued", TaskSync.pendingCount(), 0);
        end(saved);
        return ok;
    }
}
