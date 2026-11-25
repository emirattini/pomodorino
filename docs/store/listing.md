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

A pomodoro timer for your wrist. Focus for 25 minutes, take a short break, and after four rounds a long one. All the times can be changed on the watch.

- Keeps running after you leave the app. When a session ends, the watch buzzes and asks you to open Pomodorino again.
- A daily pomodoro goal, a streak of days you reached it, and a chart of the last 7 days.
- Five watch-face styles to choose from: Ember, Drain, Mono, Liquid and Classic.
- Optional auto-start of the next session.
- START is button-only. Taps on the screen are ignored, so a stray touch can't pause your timer.

Controls: START starts, pauses and resumes. UP opens the menu (skip break, restart, stop, statistics, settings, credits). DOWN shows the statistics.

Credits
Made by emileroutin. Source code (PolyForm Noncommercial 1.0.0, free for noncommercial use): https://github.com/emirattini/pomodorino
Icon and store image: tomato photo by Luc Viatour / https://Lucnix.be (Wikimedia Commons), licensed CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/). Changes: background removed, cropped and resized. The icon is shared under the same licence.
Fonts (SIL Open Font License 1.1, https://openfontlicense.org): Bebas Neue © 2010 Dharma Type; JetBrains Mono © 2020 The JetBrains Mono Project Authors; Outfit © 2021 The Outfit Project Authors; Playfair Display © 2017 The Playfair Display Project Authors; Noto Sans © 2022 The Noto Project Authors.

## What's new (version 1.0.0)

First release.

## Files

- App package: `bin/Pomodorino.iq` (build with `./build.sh release`)
- Hero image (1440x720): `docs/store/hero.png` (Ember + Liquid) or `docs/store/hero_drain_mono.png`,
  made with `tools/hero.py OUT [FRONT BACK]`
- Cover image (500x500): one of `docs/store/covers/cover_<style>.png` (comparison: `cover_sheet.png`),
  made with `tools/cover.py docs/store/covers`
- Icon: the store takes it from the app package. If the form asks for a bigger image, the original photo is on
  Wikimedia Commons (File:Tomates_cerises_Luc_Viatour.jpg) and can be cut out again with `tools/photo_icon.py`.
- Screenshots (390x390, one per style plus the statistics screen): `docs/store/screens/screen_<n>_<name>.png`, made with
  `tools/screens.py docs/store/screens` from a port of the styles' drawing code and the app's own fonts.
  Replace them with simulator captures once the simulator runs.
