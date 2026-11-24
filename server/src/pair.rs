//! Connecting a watch to a Todoist account, without typing anything on the watch:
//!
//! 1. Watch → `POST /v1/pair`: we create a device key (kept by the watch) and a pairing code.
//! 2. The watch asks the phone to open `/connect?code=...` (Garmin Connect shows a notification).
//! 3. `/connect/start` sends the browser to Todoist's login, with a random `state` that is also
//!    set as a cookie, so the login can only be finished in the browser that started it.
//! 4. Todoist → `/oauth/callback`: we get the tokens, create or find the user, and link the watch.
//! 5. Meanwhile the watch polls `GET /v1/pair/status` with its key until it's linked.

use serde::Serialize;
use worker::{Env, Headers, Request, Response, RouteContext};

use crate::api::{json, now_secs, todoist_app};
use crate::db::Db;
use crate::error::ApiError;
use crate::keys;
use crate::oauth;
use crate::pages::{esc, page};

/// How long a pairing code works.
const PAIR_TTL_SECS: i64 = 15 * 60;
const STATE_COOKIE: &str = "pomodorino_state";

fn db(env: &Env) -> Result<Db, ApiError> {
    Ok(Db::new(env.d1("DB")?))
}

fn query(req: &Request, name: &str) -> Result<Option<String>, ApiError> {
    Ok(req
        .url()?
        .query_pairs()
        .find(|(k, _)| k == name)
        .map(|(_, v)| v.into_owned()))
}

/// `POST /v1/pair` (no key needed): starts pairing a watch.
pub async fn start(req: Request, ctx: RouteContext<()>) -> Result<Response, ApiError> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Started {
        ok: bool,
        code: String,
        device_key: String,
        connect_url: String,
    }

    let db = db(&ctx.env)?;
    let now = now_secs();
    db.delete_pending_before(now - PAIR_TTL_SECS).await?;
    let device_key = keys::device_key();
    let code = keys::pairing_code();
    db.add_pending_device(&keys::hash(&device_key), &code, now)
        .await?;

    let origin = req.url()?.origin().ascii_serialization();
    json(&Started {
        ok: true,
        connect_url: format!("{origin}/connect"),
        code,
        device_key,
    })
}

/// `GET /v1/pair/status` with the device key: `{ ok, linked }`, or 404 `expired`.
pub async fn status(req: Request, ctx: RouteContext<()>) -> Result<Response, ApiError> {
    #[derive(Serialize)]
    struct Status {
        ok: bool,
        linked: bool,
    }

    let key = req.headers().get("X-Api-Key")?.unwrap_or_default();
    let device = db(&ctx.env)?
        .device(&keys::hash(&key))
        .await?
        .ok_or(ApiError::Expired)?;
    let linked = device.user_id.is_some();
    if !linked && now_secs() - device.created_at > PAIR_TTL_SECS {
        return Err(ApiError::Expired);
    }
    json(&Status { ok: true, linked })
}

/// The pairing code from `?code=`, tidied up (people may retype it from the watch in lower case).
fn code_param(req: &Request) -> Result<String, ApiError> {
    let code = query(req, "code")?.ok_or(ApiError::Expired)?;
    Ok(code.trim().to_ascii_uppercase())
}

/// `GET /connect?code=...`: the page the phone opens.
pub async fn connect_page(req: Request, ctx: RouteContext<()>) -> Result<Response, ApiError> {
    let code = code_param(&req)?;
    let device = db(&ctx.env)?
        .pending_by_code(&code)
        .await?
        .ok_or(ApiError::Expired)?;
    if now_secs() - device.created_at > PAIR_TTL_SECS {
        return Err(ApiError::Expired);
    }
    let code = esc(&code);
    Ok(page(
        "Connect your watch",
        &format!(
            "<p>Continue only if this code is on <b>your</b> watch. If someone sent you this link, close it.</p>\
             <p class=\"code\">{code}</p>\
             <a class=\"button\" href=\"/connect/start?code={code}\">Connect with Todoist</a>\
             <p><small>Pomodorino will see your tasks, add a comment when you finish a session, \
             and complete tasks you mark as done on the watch.</small></p>"
        ),
    )?)
}

/// `GET /connect/start?code=...`: off to Todoist's login.
pub async fn connect_start(req: Request, ctx: RouteContext<()>) -> Result<Response, ApiError> {
    let code = code_param(&req)?;
    let db = db(&ctx.env)?;
    let device = db.pending_by_code(&code).await?.ok_or(ApiError::Expired)?;
    if now_secs() - device.created_at > PAIR_TTL_SECS {
        return Err(ApiError::Expired);
    }
    let state = keys::nonce();
    db.set_nonce(&device.key_hash, &state).await?;

    let login = todoist_app(&ctx.env)?.authorize_url(&state)?;
    // A 302 by hand: `Response::redirect` comes with read-only headers, and we need the cookie too.
    let headers = Headers::new();
    headers.set("Location", login.as_str())?;
    headers.set(
        "Set-Cookie",
        &format!(
            "{STATE_COOKIE}={state}; Path=/oauth; Max-Age={PAIR_TTL_SECS}; HttpOnly; Secure; SameSite=Lax"
        ),
    )?;
    let response = Response::empty()?.with_status(302).with_headers(headers);
    Ok(response)
}

/// `GET /oauth/callback?code=...&state=...` (or `?error=access_denied`): Todoist sends the browser back.
pub async fn callback(req: Request, ctx: RouteContext<()>) -> Result<Response, ApiError> {
    let state = query(&req, "state")?.ok_or(ApiError::BadRequest("bad_state"))?;
    // The state must match the cookie set by /connect/start in this same browser.
    let cookie = cookie(&req, STATE_COOKIE)?.unwrap_or_default();
    if !keys::constant_time_eq(cookie.as_bytes(), state.as_bytes()) {
        return Err(ApiError::BadRequest("wrong_browser"));
    }
    if query(&req, "error")?.is_some() {
        return Ok(page(
            "Not connected",
            "<p>You didn't allow access, so nothing was connected. You can try again from the watch.</p>",
        )?);
    }
    let code = query(&req, "code")?.ok_or(ApiError::BadRequest("bad_code"))?;

    let db = db(&ctx.env)?;
    let now = now_secs();
    let device = db
        .pending_by_nonce(&state)
        .await?
        .ok_or(ApiError::Expired)?;
    if now - device.created_at > PAIR_TTL_SECS {
        return Err(ApiError::Expired);
    }

    let tokens = todoist_app(&ctx.env)?.exchange(&code, now).await?;
    let account = oauth::account_id(&tokens.access_token).await?;
    let user_id = db
        .upsert_user(&keys::user_id(), "todoist", &account, &tokens, now)
        .await?;
    db.link_device(&device.key_hash, &user_id).await?;

    let response = page(
        "Connected",
        "<p>Your watch is connected to Todoist. It will show today's tasks in a few seconds.</p>\
         <p>You can close this page.</p>",
    )?;
    // Clear the state cookie. Headers are set on a copy, then swapped in.
    let headers = response.headers().clone();
    headers.set(
        "Set-Cookie",
        &format!("{STATE_COOKIE}=; Path=/oauth; Max-Age=0; HttpOnly; Secure; SameSite=Lax"),
    )?;
    let response = response.with_headers(headers);
    Ok(response)
}

/// The value of one cookie from the `Cookie` header ("a=1; b=2").
fn cookie(req: &Request, name: &str) -> Result<Option<String>, ApiError> {
    let header = req.headers().get("Cookie")?.unwrap_or_default();
    Ok(header
        .split(';')
        .filter_map(|pair| pair.trim().split_once('='))
        .find(|(k, _)| *k == name)
        .map(|(_, v)| v.to_string()))
}
