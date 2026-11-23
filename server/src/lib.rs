//! Pomodorino proxy: the watch talks to this Worker in one small JSON format (spec §5),
//! and the Worker talks to the user's task manager.

mod api;
mod error;
mod model;
mod providers;
mod store;

use worker::{Context, Env, Request, Response, Result, Router, event};

#[event(fetch)]
async fn fetch(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    Router::new()
        .get_async("/v1/ping", |req, ctx| api::run(req, ctx, api::ping))
        .get_async("/v1/tasks", |req, ctx| api::run(req, ctx, api::tasks))
        .post_async("/v1/sessions", |req, ctx| {
            api::run(req, ctx, api::post_session)
        })
        .post_async("/v1/tasks/:id/complete", |req, ctx| {
            api::run(req, ctx, api::complete)
        })
        .run(req, env)
        .await
}
