import Toybox.Application;
import Toybox.Lang;
import Toybox.Test;

// Stats: the daily history, the streak and the 7-day chart. They live in Storage ("hist"), so each test
// starts from its own history and puts the simulator's back at the end.
module StatsTest {

    const DAY = 86400;

    // Day key n days before today.
    function daysAgo(n as Number) as Number {
        return Stats.dayKey(Stats.todayNoon() - n * DAY);
    }

    // A Stats over this history: { day key => [count, goal] }.
    function statsWith(days as Dictionary) as Stats {
        var hist = {};
        var keys = days.keys();
        for (var i = 0; i < keys.size(); i++) {
            var cg = days[keys[i]] as Array<Number>;
            hist[keys[i]] = cg[0] * 100 + cg[1];
        }
        Application.Storage.setValue("hist", hist);
        return new Stats();
    }

    (:test)
    function recordCountsAndKeepsTheGoal(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var stats = statsWith({});
        var noon = Stats.todayNoon();
        stats.record(noon, 8);
        stats.record(noon + 60, 6); // the goal was changed in between: the day keeps the latest
        var today = Stats.dayKey(noon);
        var ok = Check.eq(logger, "count", stats.countOn(today), 2)
            && Check.eq(logger, "goal", stats.goalOn(today), 6)
            && Check.eq(logger, "today", stats.todayCount(), 2)
            && Check.eq(logger, "kept after reopening", new Stats().countOn(today), 2)
            && Check.eq(logger, "other day", stats.countOn(daysAgo(1)), 0);
        Check.restore(saved);
        return ok;
    }

    // Today not reached yet doesn't break the streak; reaching it adds one.
    (:test)
    function streakCountsBackFromYesterday(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var days = {
            daysAgo(1) => [8, 8],
            daysAgo(2) => [9, 8],
            daysAgo(3) => [5, 8],  // missed: the streak stops here
            daysAgo(4) => [8, 8]
        };
        var ok = Check.eq(logger, "today not reached", statsWith(days).streak(8), 2);
        days[daysAgo(0)] = [8, 8];
        ok = ok && Check.eq(logger, "today reached", statsWith(days).streak(8), 3);
        Check.restore(saved);
        return ok;
    }

    // Each day is judged by the goal it had then, not today's.
    (:test)
    function streakUsesEachDaysOwnGoal(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var stats = statsWith({ daysAgo(1) => [4, 4], daysAgo(2) => [6, 6] });
        var ok = Check.eq(logger, "streak", stats.streak(10), 2);
        Check.restore(saved);
        return ok;
    }

    (:test)
    function aDayWithoutPomodorosBreaksTheStreak(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var stats = statsWith({ daysAgo(1) => [8, 8], daysAgo(3) => [8, 8] });
        var ok = Check.eq(logger, "streak", stats.streak(8), 1);
        Check.restore(saved);
        return ok;
    }

    // A pomodoro recorded after the streak was asked for shows up in the next answer (no stale cache).
    (:test)
    function streakFollowsNewPomodoros(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var stats = statsWith({ daysAgo(1) => [2, 2], daysAgo(0) => [1, 2] });
        var ok = Check.eq(logger, "before", stats.streak(2), 1);
        stats.record(Stats.todayNoon(), 2);
        ok = ok && Check.eq(logger, "after", stats.streak(2), 2);
        Check.restore(saved);
        return ok;
    }

    (:test)
    function setTodayGoalOnlyChangesAnExistingDay(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var stats = statsWith({});
        stats.setTodayGoal(5);
        var ok = Check.eq(logger, "no entry made", stats.goalOn(daysAgo(0)), 0);
        stats = statsWith({ daysAgo(0) => [3, 8] });
        stats.setTodayGoal(5);
        ok = ok && Check.eq(logger, "goal", stats.goalOn(daysAgo(0)), 5)
            && Check.eq(logger, "count kept", stats.countOn(daysAgo(0)), 3);
        Check.restore(saved);
        return ok;
    }

    // Oldest first, today last with today's goal (the chart's dashed line follows the setting).
    (:test)
    function lastDaysForTheChart(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var stats = statsWith({ daysAgo(6) => [3, 4], daysAgo(1) => [7, 8], daysAgo(0) => [2, 8] });
        var days = stats.lastDays(7, 10);
        var ok = Check.eq(logger, "days", days.size(), 7)
            && Check.arr(logger, "6 days ago", (days[0] as Array).slice(0, 2), [3, 4])
            && Check.arr(logger, "5 days ago", (days[1] as Array).slice(0, 2), [0, 0])
            && Check.arr(logger, "yesterday", (days[5] as Array).slice(0, 2), [7, 8])
            && Check.arr(logger, "today", (days[6] as Array).slice(0, 2), [2, 10])
            && Check.eq(logger, "day letter", ((days[6] as Array)[2] as String).length(), 1);
        Check.restore(saved);
        return ok;
    }

    // Past a year of history the oldest days go, so Storage doesn't grow forever.
    (:test)
    function oldDaysArePruned(logger as Logger) as Boolean {
        var saved = Check.stash(["hist"]);
        var hist = {};
        for (var i = 1; i <= 370; i++) {
            hist[daysAgo(i)] = 101;
        }
        hist[19991231] = 101; // long ago
        Application.Storage.setValue("hist", hist);
        var stats = new Stats();
        stats.record(Stats.todayNoon(), 1);
        var ok = Check.eq(logger, "old day gone", stats.countOn(19991231), 0)
            && Check.eq(logger, "a year ago kept", stats.countOn(daysAgo(370)), 1)
            && Check.eq(logger, "today", stats.todayCount(), 1);
        Check.restore(saved);
        return ok;
    }
}
