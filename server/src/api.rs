//! Handlers for the endpoints in spec §5. Each returns `Result<Response, ApiError>`;
//! [`run`] checks the API key first and turns any error into the JSON error response.

use std::future::Future;

use serde::Serialize;
use worker::{Env, Request, Response, RouteContext};

use crate::error::ApiError;
use crate::model::{Done, Ping, Session, SessionAck, Task, TaskList};
use crate::providers::{Demo, Provider, TaskProvider, Todoist};
use crate::store::Store;

/// What every authenticated request gets: the configured provider and the KV store.
pub struct App {
    provider: Provider,
    store: Store,
}

impl App {
    /// Checks `X-Api-Key` against the `API_KEY` secret, then builds the provider from the config.
    fn from_request(req: &Request, env: &Env) -> Result<Self, ApiError> {
        let expected = env
            .secret("API_KEY")
            .map_err(|_| ApiError::Internal("the API_KEY secret is not set".into()))?
            .to_string();
        let given = req.headers().get("X-Api-Key")?.unwrap_or_default();
        if expected.is_empty() || !constant_time_eq(given.as_bytes(), expected.as_bytes()) {
            return Err(ApiError::Unauthorized);
        }

        let var = |name: &str, default: &str| {
            env.var(name)
                .map(|v| v.to_string())
                .unwrap_or_else(|_| default.to_string())
        };
        let provider = match var("PROVIDER", "demo").as_str() {
            "demo" => Provider::Demo(Demo),
            "todoist" => {
                let token = env
                    .secret("TODOIST_TOKEN")
                    .map_err(|_| ApiError::Internal("the TODOIST_TOKEN secret is not set".into()))?
                    .to_string();
                Provider::Todoist(Todoist::new(token, var("TODOIST_FILTER", "today")))
            }
            other => return Err(ApiError::Internal(format!("unknown PROVIDER {other:?}"))),
        };

        Ok(App {
            provider,
            store: Store::new(env.kv("POMODORINO_KV")?),
        })
    }
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
    let result = match App::from_request(&req, &ctx.env) {
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
    // Providers without native time tracking leave spent_min empty: fill it from KV.
    for task in tasks.iter_mut().filter(|t| t.spent_min.is_none()) {
        task.spent_min = app.store.spent(app.provider.name(), &task.id).await?;
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
    let provider = app.provider.name();

    if app.store.seen_session(&session.session_id).await? {
        let spent_min = app.store.spent(provider, &session.task_id).await?;
        return json(&SessionAck {
            ok: true,
            spent_min,
            duplicate: true,
        });
    }

    let spent = match app.provider.log_session(&session.task_id, &session).await? {
        Some(native_total) => native_total,
        None => {
            app.store
                .add_spent(provider, &session.task_id, session.focus_min)
                .await?
        }
    };
    // Marked only after the provider accepted it: if logging fails, the watch's retry goes through.
    app.store.mark_session(&session.session_id).await?;
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

// ---- helpers ----

fn json<T: Serialize>(body: &T) -> Result<Response, ApiError> {
    Ok(Response::from_json(body)?)
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

/// Compares two secrets in time that doesn't depend on where they first differ,
/// so response timing can't be used to guess the key one character at a time.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_comparison() {
        assert!(constant_time_eq(b"s3cret", b"s3cret"));
        assert!(!constant_time_eq(b"s3cret", b"s3creT"));
        assert!(!constant_time_eq(b"s3cret", b"s3cre"));
    }

    #[test]
    fn task_ids() {
        assert!(is_safe_id("6X7rM8997g3RQmvh"));
        assert!(is_safe_id("PROJ-123"));
        assert!(!is_safe_id("../projects"));
        assert!(!is_safe_id(""));
    }
}
