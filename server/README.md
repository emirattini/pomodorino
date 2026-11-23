# pomodorino-server

The proxy between the Pomodorino watch app and your task manager, written in Rust for Cloudflare Workers.
The watch only speaks the small JSON API in [`docs/tasks-spec.md`](../docs/tasks-spec.md) §5. This server
turns it into Todoist calls (more providers later) and keeps what Todoist can't store (minutes spent per
task, already-received session ids) in Workers KV.

Status: the MVP from the spec. Single user, configured with secrets. Providers: `demo` and `todoist`.

## Endpoints

All of them require the `X-Api-Key` header.

| Method and path | Does |
|---|---|
| `GET /v1/ping` | `{ ok, provider }`: checks the URL and key |
| `GET /v1/tasks?scope=today` | today's tasks (at most 20, titles up to 60 characters) |
| `POST /v1/sessions` | records a session. The same `sessionId` sent twice is only counted once (`duplicate: true`) |
| `POST /v1/tasks/{id}/complete` | completes the task at the provider |

Errors are `{ "ok": false, "error": "<code>" }` with 400, 401, 404, 502 (provider error) or 503 (provider unreachable).

## Tools

Rust was installed for your user only, without editing your shell profile. Put it on the PATH first:

```sh
export PATH="$HOME/.cargo/bin:$PATH"      # or add this line to ~/.zshrc
```

`wrangler` (Cloudflare's CLI) runs through `npx`, so nothing else needs installing.

## Run it locally

```sh
cd server
echo 'API_KEY=dev-key' > .dev.vars         # local secrets (git-ignored)
npx wrangler dev                           # http://localhost:8787, KV is simulated
curl -H 'X-Api-Key: dev-key' localhost:8787/v1/tasks
```

With the default `PROVIDER = "demo"` you get four example tasks. To try Todoist locally, add
`TODOIST_TOKEN=...` to `.dev.vars` and run `npx wrangler dev --var PROVIDER:todoist`.

Checks:

```sh
cargo test                                           # unit tests (run natively, no Workers needed)
cargo clippy --target wasm32-unknown-unknown         # lints
cargo fmt                                            # standard formatting
```

## Deploy (free plan)

1. `npx wrangler login` (opens the browser to log in to your Cloudflare account; create one if you don't have it).
2. `npx wrangler kv namespace create POMODORINO_KV`, then paste the printed `id` into `wrangler.toml`.
3. Pick a key for the watch: `openssl rand -hex 24`, then `npx wrangler secret put API_KEY` and paste it.
4. Todoist token: Todoist → Settings → Integrations → Developer → copy the API token, then
   `npx wrangler secret put TODOIST_TOKEN`.
5. In `wrangler.toml` set `PROVIDER = "todoist"`. `TODOIST_FILTER` (default `today`) is any Todoist filter,
   for example `today | overdue`.
6. `npx wrangler deploy`. It prints the URL, like `https://pomodorino.<your-subdomain>.workers.dev`.
7. Check it: `curl -H "X-Api-Key: <key>" https://pomodorino.<your-subdomain>.workers.dev/v1/ping`

## Connect the watch

In the Garmin Connect phone app: Devices → Forerunner 165 → Activities & Apps → Pomodorino → Settings.

- **Work on tasks**: on
- **Server URL**: the URL from the deploy step
- **API key**: the key from step 3

The next time Pomodorino opens, it shows today's tasks.

## Todoist specifics

- **Estimate**: the task's *duration* (Todoist → task → Duration), when it's set in minutes.
- **Time spent**: every session adds a comment to the task, like `🍅 2 · 50 min`. Todoist has no field
  for time spent, so the server keeps the running total in KV.
- **Complete**: closes the task. A recurring task moves to its next date instead.

## Layout

```
src/lib.rs                entry point: the router
src/api.rs                endpoint handlers, API key check
src/model.rs              JSON types of the contract (serde)
src/error.rs              error types -> HTTP status codes, in one place
src/store.rs              KV: session de-duplication, minutes spent
src/providers/mod.rs      the TaskProvider trait and the Provider enum
src/providers/todoist.rs  Todoist adapter
src/providers/demo.rs     fixed example tasks
```

New to Rust? [RUST_NOTES.md](RUST_NOTES.md) walks through the idioms used here, with pointers into the code.
