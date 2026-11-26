# Connect IQ Store listing

Copy the parts below into the fields of the upload form at https://apps.garmin.com/developer/.

## App name

Pomodorino

## Type / category

Watch App, Productivity (or Tools)

## Devices

45 watches, all round with five buttons (the list in `manifest.xml`):

- **Forerunner**: 70, 165, 165 Music, 170, 170 Music, 255, 255 Music, 265, 265S, 570 (42 and 47 mm), 955 / Solar,
  965, 970
- **fēnix**: 7S, 7, 7X (also quatix 7, quatix 7X Solar, tactix 7, Enduro 2), 7S Pro, 7 Pro, 7X Pro (also the
  Solar Editions without Wi-Fi), 8 (43, 47, 51 mm, Pro, Solar; also tactix 8, quatix 8), 9 (43, 47, 51 mm, Pro,
  Pro Solar), fēnix E
- **epix**: Gen 2, Pro Gen 2 (42, 47, 51 mm; also quatix 7 Pro, D2 Mach 1 Pro, tactix 7 AMOLED)
- **Enduro**: 3, 4
- **Instinct**: 3 AMOLED (45 and 50 mm)
- **MARQ**: Gen 2 (all editions, Aviator), Gen 3

## Description

A pomodoro timer for your wrist, with your Todoist tasks. Focus for 25 minutes, take a short break, and after four rounds a long one. All the times can be changed on the watch.

Work on your tasks (optional, needs a free Todoist account)
- Connect Todoist once from your phone: no typing on the watch.
- Pick one of today's tasks and the timer runs on it. The time you focus is added to the task as a comment.
- At the end, see estimated vs actual time, then complete the task or keep it for later. Write an estimate in the task title, like "Report ~1h30", or use Todoist's duration.
- Left a task open overnight? Each day's time goes to Todoist separately, and the next morning the app asks if you're still on it.
- No phone nearby? Sessions wait on the watch and are sent later.

The timer
- Keeps running after you leave the app. When a session ends, the watch buzzes and asks you to open Pomodorino again.
- A daily pomodoro goal, a streak of days you reached it, and a chart of the last 7 days.
- Five watch-face styles to choose from: Ember, Drain, Mono, Liquid and Classic.
- Optional auto-start of the next session.
- START is button-only. Taps on the screen are ignored, so a stray touch can't pause your timer.

Controls: START starts, pauses and resumes. UP opens the menu (tasks, skip break, restart, statistics, settings, Connect Todoist). DOWN shows the statistics.

Privacy: tasks go through Pomodorino's server, which keeps only what Todoist can't store (minutes spent per task). Details: https://pomodorino.erattini.workers.dev/privacy
Pomodorino is not created by, affiliated with, or supported by Doist.

Keep cooking!

Enjoying it? Buy me a coffee: https://buymeacoffee.com/emileroutin

Credits
Made by emileroutin. Source code (PolyForm Noncommercial 1.0.0, free for noncommercial use): https://github.com/emirattini/pomodorino
Icon and store image: tomato photo by Luc Viatour / https://Lucnix.be (Wikimedia Commons), licensed CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/). Changes: background removed, cropped and resized. The icon is shared under the same licence.
Fonts (SIL Open Font License 1.1, https://openfontlicense.org): Bebas Neue © 2010 Dharma Type; JetBrains Mono © 2020 The JetBrains Mono Project Authors; Outfit © 2021 The Outfit Project Authors; Playfair Display © 2017 The Playfair Display Project Authors; Noto Sans © 2022 The Noto Project Authors.

## Short description

The same, for skimmers (about 750 characters). Use this one or the full one above.

A pomodoro timer for your wrist, with your Todoist tasks.

• Focus 25 minutes, break 5, a long break every four. All times can be changed on the watch.
• Connect Todoist from your phone, pick one of today's tasks, and your focus time is added to it.
• When you finish, see estimated vs actual time.
• Keeps running in the background: the watch buzzes when it's break time.
• Daily goal, streaks, a 7-day chart, and five styles to choose from.

START starts and pauses, UP opens the menu, DOWN shows your stats.

Todoist is optional and works with a free account. Privacy: https://pomodorino.erattini.workers.dev/privacy
Pomodorino is not created by, affiliated with, or supported by Doist.

Keep cooking! Enjoying it? Buy me a coffee: https://buymeacoffee.com/emileroutin

## What's new (version 1.1.0)

- 45 watches: Forerunner 70 to 970, fēnix 7, 8, 9 and E, epix, Enduro 3 and 4, Instinct 3 AMOLED, MARQ.
- Connect Todoist from your phone: today's tasks on the watch, time spent added to each task.
- A task left open overnight: each day's time goes to Todoist on its own, and the next morning the app asks
  whether you're still working on it.

Version 1.0.0: first release (Forerunner 165).

## Files

- App package: `bin/Pomodorino.iq` (build with `./build.sh release`)
- Hero image (1440x720): `docs/store/hero_tasks.png` (today's tasks + Drain, from 1.1.0; made with
  `tools/hero.py OUT --tasks`). Earlier: `docs/store/hero.png` (Ember + Liquid) or
  `docs/store/hero_drain_mono.png`, made with `tools/hero.py OUT [FRONT BACK]`
- Cover image (500x500): one of `docs/store/covers/cover_<style>.png` (comparison: `cover_sheet.png`),
  made with `tools/cover.py docs/store/covers`
- Icons for the store on the watch ("App Store on Device", optional, 128x128): `docs/store/device_icons/`:
  `icon_128_full.png` in the 24-bit color slot, `icon_128_64colors.png` in the 64 color slot. Made with
  `tools/store_icons.py`.
- Icon: the store takes it from the app package. If the form asks for a bigger image, the original photo is on
  Wikimedia Commons (File:Tomates_cerises_Luc_Viatour.jpg) and can be cut out again with `tools/photo_icon.py`.
- Screenshots (390x390): `docs/store/screens/screen_<n>_<name>.png`.
  - 1-6: one per style plus the statistics screen, made with `tools/screens.py docs/store/screens` from a
    port of the styles' drawing code and the app's own fonts.
  - 7-11, the Todoist features: today's tasks, the timer on a task, estimate vs actual at the end, "Still
    working on" on a new day, connecting from the phone. Real captures from the simulator
    (`tools/sim.sh`, Forerunner 165) with the server's demo tasks.
