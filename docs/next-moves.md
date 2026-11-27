# Next moves

Where Pomodorino stands (27 November 2026) and what to do next, in order.

**Today:** a Connect IQ watch app for 45 round, five-button Garmin watches, with a glance and tasks from
Todoist. Anyone can connect their Todoist through the hosted server (`pomodorino.erattini.workers.dev`,
Rust on Cloudflare Workers + D1). Version 1.1.0 is **submitted to the Garmin store and waiting for approval**.

**Done since the first plan:**
- Server CI: `cargo fmt` / `clippy` / `test` on every change, deploys from `main` after one approval on
  GitHub (`.github/workflows/server.yml`, environment `production`).
- Uptime check twice a day (`.github/workflows/uptime.yml`): GitHub emails you if the server is down or over
  the free plan's daily requests (Cloudflare error 1027).
- 45 watches: fonts per screen size and icons per watch in `devices/` (see the README's Setup).
- Store listing, screenshots, hero and cover images (`docs/store/`); website on GitHub Pages (`site/`).

**The reusable part** is the server and its watch API ([`tasks-spec.md`](tasks-spec.md) §5, pairing in
[`auth-flow.html`](auth-flow.html)). Any watch that can make HTTP requests and open a link on the phone can
use them as they are. Every other platform needs its own watch app.

## The order I'd go in

| # | Move | Why now | Size |
|---|---|---|---|
| 1 | Monitoring on Cloudflare | strangers will depend on the server as soon as the store approves the app | an hour |
| 2 | Unit tests on the watch | 45 watches and a timer that runs in the background: the logic must not regress | an evening, then as you go |
| 3 | After approval: watch reviews and issues | the first users tell you what to do next | ongoing |
| 4 | Italian translation | one strings file | an evening |
| 5 | A second task app (TickTick or Microsoft To Do) | the server is built for it (`TaskProvider`); widens who can use it | a few days each |
| 6 | A second watch platform: Wear OS | the biggest open smartwatch platform; the server is reused unchanged | weeks (new app) |
| – | Phone app, Apple Watch, other sport watch brands | see below: not worth it yet, or not possible | |

---

## 1. Monitoring on Cloudflare

The free plan has no bill to run up: past 100,000 requests a day the Worker answers with error 1027 until
midnight UTC. The uptime check already notices that. What's missing is seeing *why* something fails.

- **Workers Logs:** `[observability] enabled = true` in `server/wrangler.toml`, then deploy. Every request
  and every `console_log!` becomes searchable in the dashboard (Workers → pomodorino → Logs), kept for a few
  days. Included in the free plan.
- **Notifications** (dashboard → Notifications): check that the Workers weekly summary is on; it shows the
  request trend before it gets close to the limit.
- **D1:** Cloudflare emails when a free database reaches its daily limits; nothing to set.
- **Cleanup:** delete the old, unused KV namespace (`npx wrangler kv namespace list`, then
  `npx wrangler kv namespace delete --namespace-id <id>`).

## 2. Unit tests on the watch

Connect IQ runs `(:test)` functions in the simulator (`monkeyc --unit-test`, then `monkeydo ... -t`).
Start with the logic that doesn't draw anything: the session engine (`PomoEngine`), the statistics and streak
(`Stats`), the offline queue (`TaskSync`). Running them in CI would need the SDK there (see below).

**The watch app in CI: later, optional.** CI could check that the app compiles and attach the `.iq` to a
GitHub release. That needs the Connect IQ SDK in CI (its download sits behind a license prompt; community
Docker images exist) and your developer key as a secret. Garmin has no upload API, so publishing to the store
stays manual either way.

## 3. After the store approval

- Donations: the Buy Me a Coffee link is in the README; add it to the store description and the server's home
  page if Garmin's store rules allow links there.
- Ask users which task app to support next (store reviews, a GitHub discussion) rather than guessing.
- **More watches** if people ask: touch watches with two buttons (Venu, vivoactive: taps and swipes where the
  buttons are missing), MIP screens with 64 colors, monochrome Instinct, rectangular screens. Test each in
  the simulator (149 device profiles are installed) before adding it to `manifest.xml`.

## 4. Italian translation

The strings are in one file (`resources/strings/strings.xml`); add `resources-ita/strings/strings.xml`.
Connect IQ picks it by the watch's language.

## 5. Other task apps

**Verdict: yes, one at a time.** The server already has the seams:
- the `TaskProvider` trait in `server/src/providers/`
- a `provider` column on users
- an OAuth module

Per app: register an OAuth app, write the adapter (today's tasks, log the minutes, complete), then add a
provider choice to the connect page ("Connect with Todoist / TickTick / ..."). The watch menu item becomes
"Connect tasks".

| App | Public API + OAuth | Today's list | Log minutes | Complete | Notes | Priority |
|---|---|---|---|---|---|---|
| **TickTick** | yes (Open API) | needs checking | needs checking | yes | popular with Pomodoro users (it has its own timer) | **high**, if the API covers it |
| **Microsoft To Do** | yes (Microsoft Graph) | due-date filter | in the task's notes | yes | large user base, free | **high** |
| **Google Tasks** | yes | due-date filter | in the notes | yes | very few fields; Google requires an app verification for public use | medium |
| **ClickUp, Jira** | yes | via filters | **as real time entries** | yes | for professionals: focus time becomes logged work time | medium |
| **Notion** | yes | depends on each user's database | as a property | as a property | each user would have to map their fields | low |
| **Things, Apple Reminders** | no web API | | | | not possible from a server | no |

Each one also needs a line on the privacy page.

## 6. Other watch brands

**Verdict: Wear OS is the one to do, after Garmin is in good shape.** Each brand is a new app in a new
language. Only the server, the API and the design carry over.

| Platform | Apps from others? | Language | Verdict |
|---|---|---|---|
| **Wear OS** (Pixel Watch, Galaxy Watch, OnePlus, TicWatch) | yes, Google Play | Kotlin, Compose for Wear OS | **next platform**: biggest open one; tiles work like glances; it can open a link on the phone, so the pairing flow works as it is |
| **Apple Watch** | yes, App Store | Swift, SwiftUI | later: needs a Mac and the $99/year developer program, usually with an iPhone companion app |
| **Amazfit (Zepp OS)** | yes, Zepp store | JavaScript | maybe: cheap, long battery life, similar audience to Garmin; a smaller market |
| **Huawei (HarmonyOS)** | yes, AppGallery | ArkTS | not now: mostly regional |
| **Fitbit** | platform winding down in favour of Wear OS | | no |
| **Polar, Coros, Suunto** | no general on-watch apps (Suunto's SuuntoPlus is limited to workouts) | | not possible |

Before starting Wear OS, freeze the watch API: changes only add fields, never remove or rename. Then every
app version on every platform keeps working against one server.

## A phone app

**Verdict: not now.** Phone Pomodoro timers are a crowded market (TickTick, Forest, Todoist
integrations...). Pomodorino's point is the timer on the wrist with the phone in a drawer. Something worth
considering later instead: a small **web page with your statistics** (focus time per task and per day), built
from data the server already stores.
