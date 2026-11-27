import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Test;

// TaskSync: the offline queue, the cached task list and the small helpers. No test sends a request: test
// builds have no personal server key (./build.sh test), and the queue tests leave nothing to send.
module TaskSyncTest {

    const KEYS = ["pending", "taskCache"];

    function task(id as String, spent as Number) as Dictionary {
        return { "id" => id, "title" => "Task " + id, "spentMin" => spent };
    }

    (:test)
    function queueKeepsTheNewest50(logger as Logger) as Boolean {
        var saved = Check.stash(KEYS);
        Application.Storage.deleteValue("pending");
        for (var i = 0; i < 52; i++) {
            TaskSync.enqueue({ "k" => "s", "n" => i });
        }
        var q = TaskSync.queue();
        var ok = Check.eq(logger, "size", q.size(), 50)
            && Check.eq(logger, "oldest kept", (q[0] as Dictionary)["n"], 2)
            && Check.eq(logger, "newest", (q[49] as Dictionary)["n"], 51)
            && Check.eq(logger, "pending count", TaskSync.pendingCount(), 50);
        Check.restore(saved);
        return ok;
    }

    // Sent, or refused for good (400 bad data, 404 task deleted): dropped. Anything else waits for a retry.
    (:test)
    function sentItemsLeaveTheQueue(logger as Logger) as Boolean {
        var saved = Check.stash(KEYS);
        var item = { "k" => "c", "id" => "t1" };
        var codes = [200, 204, 400, 404, 401, 500, 503, Communications.BLE_CONNECTION_UNAVAILABLE];
        var left = [0, 0, 0, 0, 1, 1, 1, 1];
        var ok = true;
        for (var i = 0; i < codes.size() && ok; i++) {
            Application.Storage.setValue("pending", [item]);
            TaskSync.onSent(codes[i] as Number, null);
            ok = Check.eq(logger, "left after " + codes[i], TaskSync.pendingCount(), left[i]);
        }
        Check.restore(saved);
        return ok;
    }

    // A list fetched while "complete" is still queued must not bring the task back.
    (:test)
    function queuedCompletesAreHiddenFromTheList(logger as Logger) as Boolean {
        var saved = Check.stash(KEYS);
        Application.Storage.setValue("pending", [
            { "k" => "s", "b" => { "taskId" => "a" } },
            { "k" => "c", "id" => "b" }
        ]);
        var tasks = TaskSync.withoutQueuedCompletes([task("a", 0), task("b", 0), task("c", 0)]);
        var ok = Check.eq(logger, "tasks", tasks.size(), 2)
            && Check.eq(logger, "first", (tasks[0] as Dictionary)["id"], "a")
            && Check.eq(logger, "second", (tasks[1] as Dictionary)["id"], "c");
        Check.restore(saved);
        return ok;
    }

    (:test)
    function cachedListFollowsTheWatch(logger as Logger) as Boolean {
        var saved = Check.stash(KEYS);
        TaskSync.saveTasks([task("a", 10), task("b", 0)]);
        var day = (Application.Storage.getValue("taskCache") as Dictionary)["day"];
        TaskSync.updateCachedTask("a", 25, false);
        TaskSync.updateCachedTask("b", 0, true);
        TaskSync.updateCachedTask("unknown", 25, false);
        var tasks = TaskSync.cachedTasks() as Array;
        var ok = Check.eq(logger, "tasks", tasks.size(), 1)
            && Check.eq(logger, "minutes added", (tasks[0] as Dictionary)["spentMin"], 35)
            && Check.eq(logger, "day kept", (Application.Storage.getValue("taskCache") as Dictionary)["day"], day);
        Check.restore(saved);
        return ok;
    }

    // A task the server sent without minutes starts from 0.
    (:test)
    function minutesOnATaskWithoutAny(logger as Logger) as Boolean {
        var saved = Check.stash(KEYS);
        TaskSync.saveTasks([{ "id" => "a", "title" => "No minutes yet" }]);
        TaskSync.updateCachedTask("a", 25, false);
        var ok = Check.eq(logger, "minutes", ((TaskSync.cachedTasks() as Array)[0] as Dictionary)["spentMin"], 25);
        Check.restore(saved);
        return ok;
    }

    (:test)
    function isoTimesInUtc(logger as Logger) as Boolean {
        return Check.eq(logger, "epoch", TaskSync.iso(0), "1970-01-01T00:00:00Z")
            && Check.eq(logger, "noon", TaskSync.iso(1795780800), "2026-11-27T12:00:00Z")
            && Check.eq(logger, "leap day", TaskSync.iso(951868799), "2000-02-29T23:59:59Z");
    }

    (:test)
    function errorTexts(logger as Logger) as Boolean {
        return Check.eq(logger, "no phone", TaskSync.errorText(Communications.BLE_CONNECTION_UNAVAILABLE), "Phone not connected")
            && Check.eq(logger, "401", TaskSync.errorText(401), "Connect Todoist again")
            && Check.eq(logger, "timeout", TaskSync.errorText(Communications.NETWORK_REQUEST_TIMED_OUT), "Server timed out")
            && Check.eq(logger, "502", TaskSync.errorText(502), "Task service error")
            && Check.eq(logger, "other", TaskSync.errorText(418), "Error 418");
    }
}
