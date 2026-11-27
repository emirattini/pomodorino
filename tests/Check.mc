import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

// Helpers for the unit tests. Like everything in tests/, compiled only into test builds (tests.jungle).
module Check {

    // got equals want (by value for numbers, strings and booleans); logs both when not.
    function eq(logger as Logger, what as String, got as Object?, want as Object?) as Boolean {
        var ok = (got == null) ? (want == null) : got.equals(want);
        if (!ok) {
            logger.error(what + ": got " + got + ", expected " + want);
        }
        return ok;
    }

    // Same length, and every element eq.
    function arr(logger as Logger, what as String, got as Array, want as Array) as Boolean {
        if (got.size() != want.size()) {
            logger.error(what + ": got " + got + ", expected " + want);
            return false;
        }
        for (var i = 0; i < want.size(); i++) {
            if (!eq(logger, what + "[" + i + "]", got[i], want[i])) {
                return false;
            }
        }
        return true;
    }

    // The tests run in the simulator's copy of the app: put back the Storage values they change.
    function stash(keys as Array<String>) as Dictionary {
        var saved = {};
        for (var i = 0; i < keys.size(); i++) {
            saved[keys[i]] = Application.Storage.getValue(keys[i]);
        }
        return saved;
    }

    function restore(saved as Dictionary) as Void {
        var keys = saved.keys();
        for (var i = 0; i < keys.size(); i++) {
            var v = saved[keys[i]];
            if (v == null) {
                Application.Storage.deleteValue(keys[i] as String);
            } else {
                Application.Storage.setValue(keys[i] as String, v as Application.PropertyValueType);
            }
        }
    }
}
