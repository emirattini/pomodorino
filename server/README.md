# pomodorino-server

The server between the Pomodorino watch app and Todoist, written in Rust for Cloudflare Workers.
The watch only speaks the small JSON API in [`docs/tasks-spec.md`](../docs/tasks-spec.md) §5. This server
turns it into Todoist calls and keeps what Todoist can't store (minutes spent per task, sessions already
received) in a D1 (SQLite) database.

Anyone can connect: **Connect Todoist** in the watch menu opens a page on the phone, the user logs in to
Todoist, and the watch is linked. Nothing to type on the watch, no settings.

> **Using the app? You don't need any of this.** The app uses the server already running at
> `https://pomodorino.erattini.workers.dev`. This folder is for developing the server, or for running your
> own copy and pointing the app at it with the **Own server URL** setting.

## How connecting works

```
watch                         server                               phone
  │ POST /v1/pair ──────────▶ new device key + code (15 min)
  │ ◀── { code, deviceKey }
  │ openWebPage(/connect?code=K7F2QM9X) ──── Garmin Connect notification ──▶ │
  │                                                     GET /connect: "Connect with Todoist"
  │                            /connect/start: state cookie, 302 to Todoist login
  │                            /oauth/callback: tokens → user, watch linked ◀── │
  │ GET /v1/pair/status (every 3 s) ──▶ { linked: true }
  │ from now on: X-Api-Key: <deviceKey>
```

Every request of the login, refresh and disconnect, with who keeps what, is drawn in
[`docs/auth-flow.html`](../docs/auth-flow.html) (open it in a browser).

The watch keeps its key; the server stores only its SHA-256. Todoist tokens expire after an hour and are
refreshed automatically (D1 is strongly consistent, which matters: Todoist revokes everything if an old
refresh token is reused). **Disconnect Todoist** deletes the watch and, if it was the account's last
one, revokes the token and deletes the user's data. What's stored is listed at `/privacy`.

## Endpoints

| Method and path | Key | Does |
|---|---|---|
| `GET /v1/ping` | yes | `{ ok, provider }` |
| `GET /v1/tasks?scope=today` | yes | today's tasks, most urgent first (at most 20, titles up to 60 characters) |
| `POST /v1/sessions` | yes | records a session. The same `sessionId` twice is counted once (`duplicate: true`) |
| `POST /v1/tasks/{id}/complete` | yes | completes the task |
| `DELETE /v1/device` | yes | disconnects this watch |
| `POST /v1/pair` | no | starts pairing: `{ code, deviceKey, connectUrl }` |
| `GET /v1/pair/status` | the new key | `{ linked }`, or 404 `expired` |
| `GET /connect`, `/connect/start`, `/oauth/callback` | no | the pages the phone opens |
| `GET /privacy` | no | what the server stores |

Errors are `{ "ok": false, "error": "<code>" }`: 400, 401 (`unauthorized`; `reconnect` when Todoist no
longer accepts the token), 404 (`not_found`, `expired`), 502 (Todoist error) or 503 (unreachable).

## Tools

Rust was installed for your user only, without editing your shell profile. Put it on the PATH first:

```sh
export PATH="$HOME/.cargo/bin:$PATH"      # or add this line to ~/.zshrc
```

`wrangler` (Cloudflare's CLI) runs through `npx`, so nothing else needs installing.

## Run it locally

```sh
cd server
npx wrangler d1 migrations apply pomodorino --local      # once: creates the local database
echo 'API_KEY=dev-key' > .dev.vars                        # local secrets (git-ignored)
npx wrangler dev --var PROVIDER:demo                      # http://localhost:8787
curl -H 'X-Api-Key: dev-key' localhost:8787/v1/tasks
```

`API_KEY` is the owner's key: with `PROVIDER:demo` it serves four example tasks, with `todoist` it uses
the `TODOIST_TOKEN` secret. To try the Todoist login locally, also put `TODOIST_CLIENT_SECRET=...` in
`.dev.vars`, pass `--var TODOIST_CLIENT_ID:...`, and add `http://localhost:8787/oauth/callback` as a
redirect URL of the Todoist app.

Checks:

```sh
cargo test                                           # unit tests (run natively, no Workers needed)
cargo clippy --target wasm32-unknown-unknown         # lints
cargo fmt                                            # standard formatting
```

## Deploy your own (free plan)

1. `npx wrangler login`.
2. `npx wrangler d1 create pomodorino`, paste the printed `database_id` into `wrangler.toml`, then
   `npx wrangler d1 migrations apply pomodorino --remote`.
3. `npx wrangler deploy` once, to get the URL (`https://pomodorino.<your-subdomain>.workers.dev`).
4. Register a Todoist app at https://app.todoist.com/app/settings/integrations/app-management:
   - **OAuth redirect URL**: `https://pomodorino.<your-subdomain>.workers.dev/oauth/callback`
   - copy the **Client ID** into `TODOIST_CLIENT_ID` in `wrangler.toml`
   - `npx wrangler secret put TODOIST_CLIENT_SECRET` and paste the **Client secret**
5. `npx wrangler deploy` again. Check: `https://pomodorino.<your-subdomain>.workers.dev/` shows a page.
6. In the watch app, `TaskSync.DEFAULT_SERVER` (source/TaskSync.mc) is the server everyone uses.
   Change it, or set **Own server URL** in the app's phone settings.

### Automatic deploys

[`.github/workflows/server.yml`](../.github/workflows/server.yml) checks every change to `server/`
(`cargo fmt --check`, clippy, tests). On `main` it then applies the D1 migrations and deploys, after an
approval: the deploy job runs in a GitHub environment called `production` with you as required reviewer.
Set up once, in the repo's Settings → Environments → `production`:
- **Required reviewers**: yourself.
- **Deployment branches**: `main` only.
- **Secrets**: `CLOUDFLARE_API_TOKEN` (Cloudflare → My Profile → API Tokens, template "Edit Cloudflare
  Workers", plus D1: Edit) and `CLOUDFLARE_ACCOUNT_ID` (`npx wrangler whoami`).

The "Run workflow" button on the Actions tab redeploys without a change. `npx wrangler deploy` by hand
still works.

Optional, single-user: `npx wrangler secret put API_KEY` (any long random string, `openssl rand -hex 24`)
and `npx wrangler secret put TODOIST_TOKEN` (Todoist → Settings → Integrations → Developer) let a watch
use that key directly. `./build.sh` compiles in `server/.server-url` and `server/.api-key` (both
git-ignored) for builds you install yourself; release builds never include them.

## Todoist specifics

- **Order**: most urgent first (P1, P2, ...), then Todoist's own order. `TODOIST_FILTER` (default `today`)
  is any Todoist filter, for example `today | overdue`.
- **Estimate**: the task's *duration* (Pro plan only), when it's set in minutes. On the free plan, write a
  tag in the title or description instead: `~50`, `~50m`, `~1h`, `~1h30`. For example
  `Consegna Pcd ~1h30`: the watch shows *Consegna Pcd* with a 1h 30' estimate.
- **Time spent**: every session adds a comment to the task, like `🍅 2 · 50 min`. Todoist has no field
  for time spent, so the server keeps the running total.
- **Complete**: closes the task. A recurring task moves to its next date instead.

## Layout

```
src/lib.rs                entry point: the router
src/api.rs                endpoint handlers; who is calling (owner key or connected watch); token refresh
src/pair.rs               connecting a watch: pairing code, Todoist login, callback
src/oauth.rs              Todoist OAuth: login URL, code exchange, refresh, revoke
src/db.rs                 D1: users, watches, sessions, minutes (tables in migrations/)
src/keys.rs               random keys and codes, hashing
src/pages.rs              the HTML pages the phone shows, and /privacy
src/model.rs              JSON types of the contract (serde)
src/error.rs              error types -> HTTP status codes, in one place
src/estimate.rs           `~50m` estimate tags
src/providers/            the TaskProvider trait; Todoist and demo adapters
```

New to Rust? [RUST_NOTES.md](RUST_NOTES.md) walks through the idioms used here, with pointers into the code.
