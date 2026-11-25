import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Author, then credits for the icon photo (CC BY-SA 3.0 asks for attribution) and the bundled fonts (SIL OFL 1.1
// asks for the copyright notices). Pages flip with UP/DOWN or a swipe; BACK closes.
class CreditsView extends WatchUi.View {

    // First line of each page is its heading; a leading "*" marks a name (drawn brighter).
    const PAGES = [
        ["POMODORINO", "*Made by emileroutin", "", "github.com/emirattini/", "pomodorino", "Noncommercial license"],
        ["ICON", "*Photo: Luc Viatour /", "https://Lucnix.be", "CC BY-SA 3.0", "Background removed,", "resized"],
        ["FONTS · SIL OFL 1.1", "*Bebas Neue", "© 2010 Dharma Type", "*JetBrains Mono", "© 2020 The JetBrains", "Mono Project Authors"],
        ["FONTS · SIL OFL 1.1", "*Outfit", "© 2021 The Outfit", "Project Authors", "*Playfair Display", "© 2017 The Playfair", "Display Project Authors"],
        ["FONTS · SIL OFL 1.1", "*Noto Sans", "© 2022 The Noto", "Project Authors", "", "openfontlicense.org"]
    ];

    var page = 0;

    function initialize() {
        View.initialize();
    }

    function pageCount() as Number {
        return PAGES.size();
    }

    function onUpdate(dc as Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var lines = PAGES[page] as Array;
        var font = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(font);
        var y = cy - (lines.size() * lh) / 2 + lh / 2;
        for (var i = 0; i < lines.size(); i++) {
            var text = lines[i] as String;
            var color = Graphics.COLOR_LT_GRAY;
            if (i == 0) {
                color = Theme.GOAL;
            } else if (text.length() > 0 && text.substring(0, 1).equals("*")) {
                color = Graphics.COLOR_WHITE;
                text = text.substring(1, text.length());
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            y += lh;
        }

        // page dots at the bottom
        var n = PAGES.size();
        var gap = 14;
        var x0 = cx - (n - 1) * gap / 2;
        var dy = dc.getHeight() - 30;
        for (var i = 0; i < n; i++) {
            dc.setColor(i == page ? Graphics.COLOR_WHITE : Theme.DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x0 + i * gap, dy, i == page ? 4 : 3);
        }
    }
}

class CreditsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as CreditsView;

    function initialize(view as CreditsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.page = (_view.page + 1) % _view.pageCount();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.page = (_view.page + _view.pageCount() - 1) % _view.pageCount();
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        return onNextPage();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
