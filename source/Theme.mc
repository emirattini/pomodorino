import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Shared colors and text helpers.
module Theme {
    const FOCUS = 0xFF5544;
    const SHORT = 0x44DD88;
    const LONG = 0x44AAFF;
    const GOAL = 0xFFB000;
    const TRACK = 0x2A2A2A;
    const DIM = 0x8A8A8A;

    function phaseColor(ph as Number) as Number {
        if (ph == PomoEngine.SHORT_BREAK) {
            return SHORT;
        }
        if (ph == PomoEngine.LONG_BREAK) {
            return LONG;
        }
        return FOCUS;
    }

    function phaseName(ph as Number) as String {
        if (ph == PomoEngine.FOCUS) {
            return "FOCUS";
        }
        if (ph == PomoEngine.SHORT_BREAK) {
            return "SHORT BREAK";
        }
        if (ph == PomoEngine.LONG_BREAK) {
            return "LONG BREAK";
        }
        return "POMODORINO";
    }

    function phaseTitle(ph as Number) as String {
        if (ph == PomoEngine.FOCUS) {
            return "Focus";
        }
        if (ph == PomoEngine.SHORT_BREAK) {
            return "Short break";
        }
        if (ph == PomoEngine.LONG_BREAK) {
            return "Long break";
        }
        return "Pomodorino";
    }

    // Color with each channel scaled by f (0..1): cheap "darker shade".
    function shade(c as Number, f as Float) as Number {
        var r = (((c >> 16) & 0xFF) * f).toNumber();
        var g = (((c >> 8) & 0xFF) * f).toNumber();
        var b = ((c & 0xFF) * f).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    // "FOCUS" -> "F O C U S" (letter-spaced caps)
    function spaced(s as String) as String {
        var chars = s.toCharArray();
        var out = "";
        for (var i = 0; i < chars.size(); i++) {
            if (i > 0) {
                out += " ";
            }
            out += chars[i].toString();
        }
        return out;
    }

    function formatTime(sec as Number) as String {
        return (sec / 60).format("%02d") + ":" + (sec % 60).format("%02d");
    }

    function clockText(epoch as Number) as String {
        var info = Gregorian.info(new Time.Moment(epoch), Time.FORMAT_SHORT);
        var h = info.hour as Number;
        if (!System.getDeviceSettings().is24Hour) {
            h = h % 12;
            if (h == 0) {
                h = 12;
            }
        }
        return h.toString() + ":" + (info.min as Number).format("%02d");
    }

    // "UNTIL 14:25" / "PAUSED" / "PRESS START"
    function status(f as Frame) as String {
        if (f.running) {
            return "UNTIL " + clockText(f.end);
        }
        return f.paused ? "PAUSED" : "PRESS START";
    }
}
