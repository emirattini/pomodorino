import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Daily history: day key (YYYYMMDD) -> count * 100 + goal of that day.
class Stats {

    const KEY = "hist";
    const KEEP_DAYS = 370;
    const DAY = 86400;

    private var _hist as Dictionary;
    private var _streak as Number = -1;     // cached
    private var _streakDay as Number = 0;

    function initialize() {
        var h = Application.Storage.getValue(KEY);
        _hist = (h instanceof Dictionary) ? h : {};
    }

    static function dayKey(t as Number) as Number {
        var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_SHORT);
        return (info.year as Number) * 10000 + (info.month as Number) * 100 + (info.day as Number);
    }

    // Noon today: stepping back whole days from here is safe across DST changes.
    static function todayNoon() as Number {
        return Time.today().value() + 43200;
    }

    function countOn(key as Number) as Number {
        var v = _hist[key];
        return v == null ? 0 : (v as Number) / 100;
    }

    function goalOn(key as Number) as Number {
        var v = _hist[key];
        return v == null ? 0 : (v as Number) % 100;
    }

    function todayCount() as Number {
        return countOn(dayKey(todayNoon()));
    }

    function record(t as Number, goal as Number) as Void {
        var k = dayKey(t);
        _hist[k] = (countOn(k) + 1) * 100 + goal;
        prune();
        save();
    }

    function setTodayGoal(goal as Number) as Void {
        var k = dayKey(todayNoon());
        if (_hist.hasKey(k)) {
            _hist[k] = countOn(k) * 100 + goal;
            save();
        }
        _streak = -1;
    }

    // Consecutive days the goal was met. Today counts once reached, but not
    // reaching it (yet) doesn't break the streak.
    function streak(goal as Number) as Number {
        var noon = todayNoon();
        var today = dayKey(noon);
        if (_streak >= 0 && _streakDay == today) {
            return _streak;
        }
        var n = (countOn(today) >= goal) ? 1 : 0;
        var t = noon - DAY;
        for (var i = 0; i < KEEP_DAYS; i++) {
            var k = dayKey(t);
            var g = goalOn(k);
            if (g > 0 && countOn(k) >= g) {
                n++;
                t -= DAY;
            } else {
                break;
            }
        }
        _streak = n;
        _streakDay = today;
        return n;
    }

    // Oldest first, today last: [count, goal, day letter] per day.
    function lastDays(n as Number, todayGoal as Number) as Array {
        var out = [];
        var noon = todayNoon();
        for (var i = n - 1; i >= 0; i--) {
            var t = noon - i * DAY;
            var k = dayKey(t);
            var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_MEDIUM);
            var letter = (info.day_of_week as String).substring(0, 1);
            out.add([countOn(k), i == 0 ? todayGoal : goalOn(k), letter]);
        }
        return out;
    }

    private function prune() as Void {
        if (_hist.size() <= KEEP_DAYS) {
            return;
        }
        var cutoff = dayKey(todayNoon() - KEEP_DAYS * DAY);
        var keys = _hist.keys();
        for (var i = 0; i < keys.size(); i++) {
            if ((keys[i] as Number) < cutoff) {
                _hist.remove(keys[i]);
            }
        }
    }

    function save() as Void {
        _streak = -1;
        Application.Storage.setValue(KEY, _hist);
    }
}
