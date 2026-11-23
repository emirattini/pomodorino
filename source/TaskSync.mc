import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Talks to the Pomodorino server (docs/tasks-spec.md §5) through the phone.
// The timer never waits for it: finished sessions go into a queue in Storage
// and are sent whenever the phone is reachable.
module TaskSync {

    const KEY_CACHE = "taskCache";   // last task list: { "tasks" => [...] }
    const KEY_QUEUE = "pending";     // [{ "k" => "s", "b" => session } | { "k" => "c", "id" => taskId }]
    const MAX_QUEUE = 50;

    var _busy as Boolean = false;

    // ---- configuration (Garmin Connect app settings) ----

    // A phone setting, or the personal value compiled in by build.sh (gen/Personal.mc) when it's empty.
    function prop(key as String) as String {
        var v = Application.Properties.getValue(key);
        if (v instanceof String && !v.equals("")) {
            return v;
        }
        if (key.equals("serverUrl")) {
            return Personal.SERVER_URL;
        }
        return key.equals("apiKey") ? Personal.API_KEY : "";
    }

    // On when switched on in the phone settings, or when a personal build has a server compiled in.
    function enabled() as Boolean {
        var on = Application.Properties.getValue("tasksEnabled") == true || !Personal.SERVER_URL.equals("");
        return on && !prop("serverUrl").equals("") && !prop("apiKey").equals("");
    }

    function baseUrl() as String {
        var url = prop("serverUrl");
        while (url.length() > 0 && url.substring(url.length() - 1, url.length()).equals("/")) {
            url = url.substring(0, url.length() - 1) as String;
        }
        return url;
    }

    function options(method as Communications.HttpRequestMethod) as Dictionary {
        var headers = { "X-Api-Key" => prop("apiKey") } as Dictionary;
        if (method == Communications.HTTP_REQUEST_METHOD_POST) {
            headers["Content-Type"] = Communications.REQUEST_CONTENT_TYPE_JSON;
        }
        return {
            :method => method,
            :headers => headers,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    // ---- task list ----

    function fetchTasks(callback as Method) as Void {
        Communications.makeWebRequest(baseUrl() + "/v1/tasks", { "scope" => "today" },
            options(Communications.HTTP_REQUEST_METHOD_GET), callback);
    }

    function cachedTasks() as Array? {
        var c = Application.Storage.getValue(KEY_CACHE);
        if (c instanceof Dictionary && c["tasks"] instanceof Array) {
            return c["tasks"] as Array;
        }
        return null;
    }

    // "day" (today's midnight) lets the glance tell today's list from an old one.
    function saveTasks(tasks as Array) as Void {
        Application.Storage.setValue(KEY_CACHE, { "tasks" => tasks, "day" => Time.today().value() });
    }

    // Drops the tasks this watch has completed but whose "complete" hasn't reached the server yet.
    // Without this, a list fetched right after Complete task (while the request is still on its way)
    // would bring the task back.
    function withoutQueuedCompletes(tasks as Array) as Array {
        var q = queue();
        for (var i = 0; i < q.size(); i++) {
            var item = q[i] as Dictionary;
            if (!"c".equals(item["k"])) {
                continue;
            }
            for (var j = tasks.size() - 1; j >= 0; j--) {
                if ((item["id"] as String).equals((tasks[j] as Dictionary)["id"])) {
                    tasks.remove(tasks[j]);
                }
            }
        }
        return tasks;
    }

    // Keeps the cached list in step with what we just did, so it's right even offline.
    function updateCachedTask(id as String, addMin as Number, remove as Boolean) as Void {
        var cache = Application.Storage.getValue(KEY_CACHE);
        if (!(cache instanceof Dictionary) || !(cache["tasks"] instanceof Array)) {
            return;
        }
        var tasks = cache["tasks"] as Array;
        for (var i = 0; i < tasks.size(); i++) {
            var t = tasks[i] as Dictionary;
            if (id.equals(t["id"])) {
                if (remove) {
                    tasks.remove(t);
                } else {
                    var spent = t["spentMin"];
                    t["spentMin"] = (spent instanceof Number ? spent : 0) + addMin;
                }
                Application.Storage.setValue(KEY_CACHE, cache); // keeps the list's own "day"
                return;
            }
        }
    }

    // A short reason for a failed request, for the screen.
    function errorText(code as Number) as String {
        if (code == Communications.BLE_CONNECTION_UNAVAILABLE || code == Communications.BLE_HOST_TIMEOUT) {
            return "Phone not connected";
        }
        if (code == 401) {
            return "Wrong API key";
        }
        if (code == Communications.NETWORK_REQUEST_TIMED_OUT) {
            return "Server timed out";
        }
        if (code == 502 || code == 503) {
            return "Task service error";
        }
        return "Error " + code;
    }

    // ---- outgoing queue ----

    function queue() as Array {
        var q = Application.Storage.getValue(KEY_QUEUE);
        return (q instanceof Array) ? q : [];
    }

    function pendingCount() as Number {
        return queue().size();
    }

    function enqueue(item as Dictionary) as Void {
        var q = queue();
        q.add(item);
        while (q.size() > MAX_QUEUE) {
            q = q.slice(1, null); // drop the oldest
        }
        Application.Storage.setValue(KEY_QUEUE, q);
    }

    // Sends the oldest queued item; on success the callback sends the next one.
    function flush() as Void {
        if (_busy || !enabled()) {
            return;
        }
        var q = queue();
        if (q.size() == 0) {
            return;
        }
        var item = q[0] as Dictionary;
        var post = options(Communications.HTTP_REQUEST_METHOD_POST);
        _busy = true;
        if ("c".equals(item["k"])) {
            Communications.makeWebRequest(baseUrl() + "/v1/tasks/" + item["id"] + "/complete", {}, post,
                new Lang.Method(TaskSync, :onSent));
        } else {
            Communications.makeWebRequest(baseUrl() + "/v1/sessions", item["b"] as Dictionary, post,
                new Lang.Method(TaskSync, :onSent));
        }
    }

    function onSent(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        var q = queue();
        if (q.size() == 0) {
            return;
        }
        // 2xx: done. 400/404: will never succeed (bad data, task deleted), so don't let it block the queue.
        // Anything else (no phone, 401, 5xx): keep it and try again later.
        var done = (code >= 200 && code < 300) || code == 400 || code == 404;
        if (!done) {
            return;
        }
        Application.Storage.setValue(KEY_QUEUE, q.slice(1, null));
        flush();
    }

    // ---- helpers ----

    function newId() as String {
        return Time.now().value().format("%x") + "-" + (Math.rand() & 0xFFFFFF).format("%06x");
    }

    function iso(t as Number) as String {
        var u = Gregorian.utcInfo(new Time.Moment(t), Time.FORMAT_SHORT);
        return Lang.format("$1$-$2$-$3$T$4$:$5$:$6$Z", [
            u.year, (u.month as Number).format("%02d"), u.day.format("%02d"),
            u.hour.format("%02d"), u.min.format("%02d"), u.sec.format("%02d")]);
    }
}
