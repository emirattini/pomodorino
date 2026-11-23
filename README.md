# Pomodorino 🍅

A Pomodoro watch app for the Garmin Forerunner 165 (and 165 Music), built with Connect IQ.

## Features

- **Pomodoro sessions**: focus, short break, and a long break every N pomodoros. Defaults are 25 / 5 / 15 min with a long break every 4.
- **Runs in the background**: the timer is based on wall-clock time. You can exit the app and when a session ends the watch prompts *"Pomodoro done! Break time."*. Tap it to reopen the app. With the app open you get vibration, a tone, and the backlight instead.
- **Daily goal**: an outer gold ring fills as you complete pomodoros. You also get a streak of consecutive goal days and a 7-day bar chart.
- **Auto-start (optional)**: the next session starts by itself. It stops after a long break so a forgotten timer doesn't run all night.
- **5 screen styles**: Ember, Drain, Mono, Liquid, Classic. Pick one in Settings → Style, which shows a live preview of each.
- **On-watch settings**: style, focus, short break, long break, long break interval, daily goal, auto-start.
- **Tasks (optional)**: work on today's tasks from Todoist. Pick a task when the app opens and see its title on
  the timer. When you finish, you get *estimated vs actual* time, can complete the task, and the focus time is
  logged on it. Sessions are queued on the watch while the phone is away. This needs the small server in
  [`server/`](server/README.md) (Rust, Cloudflare Workers free plan). Spec: [`docs/tasks-spec.md`](docs/tasks-spec.md).

## Controls

| Button | Action |
|---|---|
| START (top right) | Start / pause / resume (button only: screen taps are ignored so a stray touch can't stop the timer) |
| UP (or swipe down) / hold UP | Menu: choose / finish task (task mode), skip break, restart session, stop, statistics, settings, credits |
| DOWN (or swipe up) | Statistics (last 7 days, streak) |
| BACK | Exit. The timer keeps running and you'll get a prompt when the session ends |

In number pickers and the style picker: UP/DOWN to change, START to save, BACK to cancel.
On the task summary: UP/DOWN to choose *Complete task* or *Continue later*, START to confirm, BACK to go back to the timer.

Task mode is turned on from the phone: Garmin Connect → your watch → Activities & Apps → Pomodorino → Settings
(*Work on tasks*, *Server URL*, *API key*). See [server/README.md](server/README.md).

## Setup (Manjaro / Arch)

1. Install the SDK Manager: `yay -S connectiq-sdk-manager`
2. Run `connectiq-sdk-manager` and log in with your Garmin account. Download the latest **SDK**, then under **Devices** download **Forerunner 165** (and 165 Music if you have it).
3. Build: `./build.sh`. The first run creates a developer key (`developer_key.der`). Keep it, because future builds must be signed with the same key.
4. Try it in the simulator: `./build.sh sim`

## Install on the watch (sideload)

1. Connect the watch via USB. On Linux it shows up as an MTP device (via your file manager / gvfs, or `jmtpfs`).
2. Copy `bin/Pomodorino.prg` to `GARMIN/APPS/` on the watch.
3. Unplug. The app appears in the watch's apps list (START → scroll to *Pomodorino*). You can also add it to your favorites/apps loop.

## Notes & limitations

- Garmin lets background events fire at most **once every 5 minutes**. With a short break under 5 min, the notification for its end may arrive a little late when the app is closed. While the app is open, alerts are always exact.
- The background prompt depends on your watch's notification and Do Not Disturb settings.
- Pomodoros are counted on the day they finish. Changing the daily goal updates today but not past days.
- Task mode needs the phone connected to fetch tasks. Without it, the last list is shown and finished sessions wait
  in a queue (up to 50) until the phone is back. The app asks for the *Communications* permission for this.
- Settings and history are stored on the watch. Reinstalling the app with a different developer key or app ID will reset them.

## Project layout

```
source/PomoEngine.mc          timer state machine (shared with background)
source/PomoServiceDelegate.mc background service: wake prompt at session end
source/PomoController.mc      foreground state, actions, alerts
source/Stats.mc               daily history, streak
source/MainView.mc            main screen (draws the chosen style) + button handling
source/Styles.mc              style registry, frame data, shared drawing helpers
source/styles/                the 5 styles
source/StylePicker.mc         live style preview picker
source/Theme.mc               colors and text helpers
source/StatsView.mc           7-day chart
source/Menus.mc               main & settings menus
source/NumberPicker.mc        number picker for settings
source/CreditsView.mc         credits for the icon photo and fonts
source/TaskSync.mc            server requests, offline queue of finished sessions, task list cache
source/TaskViews.mc           task list, loading screen, estimated-vs-actual summary
resources/settings/           phone settings (task mode, server URL, API key)
server/                       Rust proxy for task managers (Cloudflare Workers), see server/README.md
docs/tasks-spec.md            task integration spec (Italian)
resources/fonts/              bitmap fonts, generated by tools/build_fonts.sh from tools/fonts/ (all SIL OFL)
tools/variants.py             animated design mockups (docs/variants/)
tools/photo_icon.py           photo -> launcher icon cutouts (docs/icons/photo/)
docs/store/                   Connect IQ Store listing text and images
```

## Credits

- **Launcher icon:** photo by Luc Viatour / https://Lucnix.be, from
  [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Tomates_cerises_Luc_Viatour.jpg),
  licensed [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
  Changes: background removed, cropped and resized. The icon (`resources/drawables/launcher_icon.png`,
  `docs/icons/photo/vine_single_*`) is therefore also licensed CC BY-SA 3.0.
- **Fonts** (all [SIL Open Font License 1.1](https://openfontlicense.org), licence texts in `tools/fonts/OFL-*.txt`):
  Bebas Neue © 2010 Dharma Type; JetBrains Mono © 2020 The JetBrains Mono Project Authors;
  Outfit © 2021 The Outfit Project Authors; Playfair Display © 2017 The Playfair Display Project Authors
  (Reserved Font Name "Playfair Display"); Noto Sans © 2022 The Noto Project Authors.
  The app bundles bitmap versions of these fonts under the names Timer*/Label*/Small*.

