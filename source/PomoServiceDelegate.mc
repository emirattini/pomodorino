import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// Runs while the app is closed, at the moment a session ends.
// It only reads storage: the foreground app recomputes the same state from
// the stored end times the next time it opens.
(:background)
class PomoServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var settings = PomoEngine.loadSettings();
        var state = PomoEngine.loadState();
        var res = PomoEngine.roll(state, settings, Time.now().value() + 2);
        var ended = res[1];

        // With auto-start the next session is already running: wake again at its end.
        PomoEngine.scheduleWake(state);

        if (ended != null && (Background has :requestApplicationWake)) {
            Background.requestApplicationWake(PomoEngine.wakeMessage(ended as Number, state));
        }
        Background.exit(null);
    }
}
