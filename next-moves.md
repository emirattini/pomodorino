# Next moves

Where Pomodorino stands (November 2026) and what to do next, in order.

**Today:** a Connect IQ watch app for the Forerunner 165 / 165 Music only, with a glance and tasks from
Todoist. Anyone can connect their Todoist through the hosted server (`pomodorino.erattini.workers.dev`,
Rust on Cloudflare Workers + D1). The server is deployed by hand with `npx wrangler deploy`. Not on the
Garmin store yet.

**The reusable part** is the server and its watch API ([`docs/tasks-spec.md`](docs/tasks-spec.md) §5,
pairing in [`docs/auth-flow.html`](docs/auth-flow.html)). Any watch that can make HTTP requests and open a
link on the phone can use them as they are. Every other platform needs its own watch app.

## The order I'd go in

| # | Move | Why now | Size |
|---|---|---|---|
| 1 | Automatic server deploys (GitHub Actions) | small, and makes every later change safer | an evening |
| 2 | Garmin store release, then more Garmin watches | same code, one listing, the audience we already target | days per device family |
| 3 | A second task app (TickTick or Microsoft To Do) | the server is built for it (`TaskProvider`); widens who can use it | a few days each |
| 4 | A second watch platform: Wear OS | the biggest open smartwatch platform; the server is reused unchanged | weeks (new app) |
| – | Phone app, Apple Watch, other sport watch brands | see below: not worth it yet, or not possible | |

---

## 1. Automatic deploys with GitHub Actions

**Verdict: yes, first.** It's small and it puts the tests in front of every deploy.

A workflow `.github/workflows/server.yml`:

- **On every push and pull request that touches `server/`:** install Rust with the wasm target, then
  `cargo fmt --check`, `cargo clippy`, `cargo test`.
- **On push to `main`, if the checks pass:** `wrangler d1 migrations apply pomodorino --remote`, then
  `wrangler deploy` (with `cloudflare/wrangler-action`).
- **A safety catch:** deploy through a GitHub *environment* called `production` with **required
  reviewers** = you. Each deploy then waits for one click on GitHub. Users depend on the server once the app
  is on the store, so a bad push shouldn't go live on its own. The catch can be removed later.

You set up once:
1. A Cloudflare API token from the "Edit Cloudflare Workers" template, plus **D1: Edit**, limited to your
   account.
2. Repo secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

The worker's own secrets (`TODOIST_CLIENT_SECRET`, `API_KEY`, `TODOIST_TOKEN`) stay on Cloudflare; a
deploy doesn't touch them. Pull requests from forks never get the repo secrets, so they can't deploy.

**The watch app in CI: later, optional.** CI could check that the app compiles and attach the `.iq` to a
GitHub release. That needs the Connect IQ SDK in CI (its download sits behind a license prompt; community
Docker images exist) and your developer key as a secret. Garmin has no upload API, so publishing to the store
stays manual either way.

## 2. Garmin first: the store, then every Garmin watch

**Verdict: yes, this is the main road.** The code, the store listing and the users are all Garmin's.
Connect IQ runs on most current Garmin watches, so each new device is mostly layout and testing work.

### 2a. Store release (Forerunner 165 family)
- Listing text: [`docs/store/listing.md`](docs/store/listing.md). Say that tasks need a Todoist account
  and go through our server.
- Screenshots: `tools/screens.py`, `docs/store/screens/`.
- Privacy policy URL: `https://pomodorino.erattini.workers.dev/privacy`. Support: GitHub issues.
- Start as a **beta app** on the store, then publish.
- Cloudflare usage alerts before strangers depend on it (the free plan allows about 100k requests a day).
- Donations: a GitHub Sponsors, Ko-fi or Buy Me a Coffee link in the README, the store description, the
  server's home page and the watch's credits. Check Garmin's store rules on links in descriptions first.

### 2b. More Garmin devices
The app is built for one screen: 390×390 AMOLED, round, five buttons. What changes per device:

| What differs | Where it bites | Work |
|---|---|---|
| **Screen size** (218 to 454 px) | the bitmap fonts in `resources/fonts/` are cut for 390 px | generate a font set per resolution (`tools/build_fonts.sh`) under resource qualifiers such as `resources-round-454x454/`; the layouts already use fractions of the screen |
| **Display type**: AMOLED vs MIP (64 colors) vs monochrome (Instinct) | gradients, greys and the glance bar | check on MIP; give monochrome its own simple theme, or leave it out |
| **Input**: touch watches with 2 buttons (Venu, vivoactive) | controls assume START/UP/DOWN/BACK | handle taps and swipes in the delegates where the buttons are missing |
| **Memory** | older watches give apps far less | check the peak in the simulator's memory view |
| **Shape**: rectangular (Venu Sq), semi-octagon (Instinct) | round layouts | later, or not at all |

Rollout in tiers, each one tested in the simulator (149 device profiles are installed) before it's added to
`manifest.xml`:
1. **Round AMOLED with buttons**, closest to the 165: Forerunner 265/265S/965, the newer Forerunners,
   Fenix 8 / Epix Pro, Venu 3, vivoactive 5/6.
2. **Round MIP**: Forerunner 255/955, Fenix 7, Enduro, Instinct 3 (round models).
3. **The rest** (Instinct monochrome, rectangular, older models), if people ask.

## 3. Other task apps

**Verdict: yes, one at a time, after the store release.** The server already has the seams:
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

Pick the second app by asking users (store reviews, a GitHub discussion) rather than guessing. Each one
also needs a line on the privacy page.

## 4. Other watch brands

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

## 5. A phone app

**Verdict: agree, not now.** Phone Pomodoro timers are a crowded market (TickTick, Forest, Todoist
integrations...). Pomodorino's point is the timer on the wrist with the phone in a drawer. Something worth
considering later instead: a small **web page with your statistics** (focus time per task and per day), built
from data the server already stores.

## Smaller things worth doing along the way

- **Monitoring:** Cloudflare usage notifications and Workers logs, so errors show up before users report them.
- **Italian translation:** the strings are in one file (`resources/strings/strings.xml`); add
  `resources-ita/`.
- **Cleanup:** delete the old, unused KV namespace on Cloudflare.
- **Tests on the watch side:** Connect IQ supports `(:test)` unit tests. The timer and queue logic would
  benefit.
