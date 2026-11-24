//! Handlers for the endpoints in spec §5. Each returns `Result<Response, ApiError>`;
//! [`run`] finds who's calling first and turns any error into the JSON error response.

use std::future::Future;

use serde::Serialize;
use worker::{Env, Request, Response, RouteContext};

use crate::db::{Db, User};
use crate::error::{ApiError, ProviderError};
use crate::keys::{self, constant_time_eq};
use crate::model::{Done, Ping, Session, SessionAck, Task, TaskList};
use crate::oauth::TodoistApp;
use crate::providers::{Demo, Provider, TaskProvider, Todoist};

/// The user id of the owner's key (the `API_KEY` secret, the single-user setup).
const OWNER: &str = "owner";
/// Refresh a token when it has less than this left.
const REFRESH_MARGIN_SECS: i64 = 5 * 60;

/// What every authenticated request gets: who it is, their provider, and the database.
pub struct App {
    provider: Provider,
    db: Db,
    user_id: String,
}

impl App {
    /// Finds the caller from `X-Api-Key`: the owner's key, or a watch connected with "Connect Todoist".
    async fn from_request(req: &Request, env: &Env) -> Result<Self, ApiError> {
        let given = req.headers().get("X-Api-Key")?.unwrap_or_default();
        if given.is_empty() {
            return Err(ApiError::Unauthorized);
        }
        let db = Db::new(env.d1("DB")?);
        let var = |name: &str, default: &str| {
            env.var(name)
                .map(|v| v.to_string())
                .unwrap_or_else(|_| default.to_string())
        };

        let owner_key = env
            .secret("API_KEY")
            .map(|s| s.to_string())
            .unwrap_or_default();
        if !owner_key.is_empty() && constant_time_eq(given.as_bytes(), owner_key.as_bytes()) {
            let provider = match var("PROVIDER", "demo").as_str() {
                "demo" => Provider::Demo(Demo),
                "todoist" => {
                    let token = env
                        .secret("TODOIST_TOKEN")
                        .map_err(|_| {
                            ApiError::Internal("the TODOIST_TOKEN secret is not set".into())
                        })?
                        .to_string();
                    Provider::Todoist(Todoist::new(token, var("TODOIST_FILTER", "today")))
                }
                other => return Err(ApiError::Internal(format!("unknown PROVIDER {other:?}"))),
            };
            return Ok(App {
                provider,
                db,
                user_id: OWNER.to_string(),
            });
        }

        let key_hash = keys::hash(&given);
        let user_id = db
            .device(&key_hash)
            .await?
            .and_then(|d| d.user_id) // a watch still pairing isn't allowed in yet
            .ok_or(ApiError::Unauthorized)?;
        let user = db.user(&user_id).await?.ok_or(ApiError::Unauthorized)?;
        let token = fresh_token(&db, env, user).await?;
        Ok(App {
            provider: Provider::Todoist(Todoist::new(token, var("TODOIST_FILTER", "today"))),
            db,
            user_id,
        })
    }
}

/// The user's access token, refreshed first if it's about to expire.
async fn fresh_token(db: &Db, env: &Env, user: User) -> Result<String, ApiError> {
    let now = now_secs();
    // `let ... else`: take both values if present, otherwise the token doesn't expire.
    let (Some(expires_at), Some(refresh)) = (user.expires_at, user.refresh_token.as_deref()) else {
        return Ok(user.access_token);
    };
    if expires_at - now > REFRESH_MARGIN_SECS {
        return Ok(user.access_token);
    }
    let tokens = match todoist_app(env)?.refresh(refresh, now).await {
        Ok(tokens) => tokens,
        // Todoist refuses the refresh token: the user revoked access (or it was reused).
        Err(ProviderError::Status {
            status: 400 | 401, ..
        }) => return Err(ApiError::Reconnect),
        Err(e) => return Err(e.into()),
    };
    if db.replace_tokens(&user.id, refresh, &tokens).await? {
        Ok(tokens.access_token)
    } else {
        // Another request refreshed at the same moment and stored its tokens first: use those.
        db.user(&user.id)
            .await?
            .map(|u| u.access_token)
            .ok_or(ApiError::Unauthorized)
    }
}

/// The Todoist app's credentials: `TODOIST_CLIENT_ID` (a var) and `TODOIST_CLIENT_SECRET` (a secret).
pub fn todoist_app(env: &Env) -> Result<TodoistApp, ApiError> {
    let client_id = env
        .var("TODOIST_CLIENT_ID")
        .map(|v| v.to_string())
        .unwrap_or_default();
    let client_secret = env
        .secret("TODOIST_CLIENT_SECRET")
        .map(|v| v.to_string())
        .unwrap_or_default();
    if client_id.is_empty() || client_secret.is_empty() {
        return Err(ApiError::Internal(
            "the Todoist OAuth app isn't configured".into(),
        ));
    }
    Ok(TodoistApp {
        client_id,
        client_secret,
    })
}

/// Runs `handler` for an authenticated request; any `Err` becomes `{ ok: false, error }`.
///
/// `F` is any function taking the App, the request and the route context and returning a future,
/// which is exactly what an `async fn` with those parameters is.
pub async fn run<F, Fut>(
    req: Request,
    ctx: RouteContext<()>,
    handler: F,
) -> worker::Result<Response>
where
    F: FnOnce(App, Request, RouteContext<()>) -> Fut,
    Fut: Future<Output = Result<Response, ApiError>>,
{
    let result = match App::from_request(&req, &ctx.env).await {
        Ok(app) => handler(app, req, ctx).await,
        Err(e) => Err(e),
    };
    result.or_else(ApiError::into_response)
}

// ---- endpoints ----

/// `GET /v1/ping`
pub async fn ping(app: App, _req: Request, _ctx: RouteContext<()>) -> Result<Response, ApiError> {
    json(&Ping {
        ok: true,
        provider: app.provider.name(),
    })
}

/// `GET /v1/tasks?scope=today`
pub async fn tasks(app: App, req: Request, _ctx: RouteContext<()>) -> Result<Response, ApiError> {
    let url = req.url()?;
    let scope = url
        .query_pairs()
        .find(|(k, _)| k == "scope")
        .map(|(_, v)| v.into_owned());
    if scope.as_deref().is_some_and(|s| s != "today") {
        return Err(ApiError::BadRequest("unsupported_scope"));
    }

    let mut tasks = app.provider.list_today().await?;
    // Providers without native time tracking leave spent_min empty: fill it from the database.
    let spent = app.db.spent_all(&app.user_id).await?;
    for task in tasks.iter_mut().filter(|t| t.spent_min.is_none()) {
        task.spent_min = spent.get(&task.id).copied();
    }
    let tasks = tasks.into_iter().map(Task::normalized).collect();
    json(&TaskList {
        fetched_at: now_iso(),
        tasks,
    })
}

/// `POST /v1/sessions` — idempotent: a `sessionId` seen before is acknowledged, not logged again.
pub async fn post_session(
    app: App,
    mut req: Request,
    _ctx: RouteContext<()>,
) -> Result<Response, ApiError> {
    let session: Session = req
        .json()
        .await
        .map_err(|_| ApiError::BadRequest("bad_json"))?;
    session.validate().map_err(ApiError::BadRequest)?;
    let user = app.user_id.as_str();

    if app.db.seen_session(user, &session.session_id).await? {
        let spent_min = app.db.spent(user, &session.task_id).await?;
        return json(&SessionAck {
            ok: true,
            spent_min,
            duplicate: true,
        });
    }

    let spent = match app.provider.log_session(&session.task_id, &session).await? {
        Some(native_total) => native_total,
        None => {
            app.db
                .add_spent(user, &session.task_id, session.focus_min)
                .await?
        }
    };
    // Marked only after the provider accepted it: if logging fails, the watch's retry goes through.
    app.db
        .mark_session(user, &session.session_id, now_secs())
        .await?;
    json(&SessionAck {
        ok: true,
        spent_min: Some(spent),
        duplicate: false,
    })
}

/// `POST /v1/tasks/{id}/complete`
pub async fn complete(
    app: App,
    _req: Request,
    ctx: RouteContext<()>,
) -> Result<Response, ApiError> {
    let id = ctx.param("id").ok_or(ApiError::NotFound)?;
    if !is_safe_id(id) {
        return Err(ApiError::BadRequest("bad_task_id"));
    }
    app.provider.complete(id).await?;
    json(&Done { ok: true })
}

/// `DELETE /v1/device`: "Disconnect Todoist" on the watch. Forgets the watch; when it was the user's
/// last one, also revokes the token at Todoist and deletes everything stored for the user.
///
/// Runs through [`open`], not [`run`]: it only needs to know which watch is calling, and must work
/// even when Todoist no longer accepts the user's token (that's often why people disconnect).
pub async fn disconnect(req: Request, ctx: RouteContext<()>) -> Result<Response, ApiError> {
    let key = req.headers().get("X-Api-Key")?.unwrap_or_default();
    let db = Db::new(ctx.env.d1("DB")?);
    let key_hash = keys::hash(&key);
    let user_id = db
        .device(&key_hash)
        .await?
        .and_then(|d| d.user_id)
        .ok_or(ApiError::Unauthorized)?;

    db.delete_device(&key_hash).await?;
    if db.device_count(&user_id).await? == 0 {
        if let (Ok(todoist), Some(user)) = (todoist_app(&ctx.env), db.user(&user_id).await?) {
            // Best effort: the data is deleted either way, and the user can also revoke in Todoist.
            if let Err(e) = todoist.revoke(&user.access_token).await {
                worker::console_warn!("revoke failed: {e}");
            }
        }
        db.delete_user(&user_id).await?;
    }
    json(&Done { ok: true })
}

// ---- helpers ----

pub fn json<T: Serialize>(body: &T) -> Result<Response, ApiError> {
    Ok(Response::from_json(body)?)
}

/// Runs a handler that needs no key (pairing); any `Err` becomes `{ ok: false, error }`.
pub async fn open<F, Fut>(
    req: Request,
    ctx: RouteContext<()>,
    handler: F,
) -> worker::Result<Response>
where
    F: FnOnce(Request, RouteContext<()>) -> Fut,
    Fut: Future<Output = Result<Response, ApiError>>,
{
    handler(req, ctx).await.or_else(ApiError::into_response)
}

pub fn now_secs() -> i64 {
    (worker::js_sys::Date::now() / 1000.0) as i64
}

fn now_iso() -> String {
    worker::js_sys::Date::new_0().to_iso_string().into()
}

/// Task ids go into provider URLs, so only allow characters that need no escaping.
fn is_safe_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn task_ids() {
        assert!(is_safe_id("6X7rM8997g3RQmvh"));
        assert!(is_safe_id("PROJ-123"));
        assert!(!is_safe_id("../projects"));
        assert!(!is_safe_id(""));
    }
}
