//! Pomodorino proxy: the watch talks to this Worker in one small JSON format (spec §5),
//! and the Worker talks to the user's task manager.

mod api;
mod db;
mod error;
mod estimate;
mod keys;
mod model;
mod oauth;
mod pages;
mod pair;
mod providers;

use worker::{Context, Env, Request, Response, Result, Router, event};

#[event(fetch)]
async fn fetch(req: Request, env: Env, _ctx: Context) -> Result<Response> {
    Router::new()
        // The watch, with its key
        .get_async("/v1/ping", |req, ctx| api::run(req, ctx, api::ping))
        .get_async("/v1/tasks", |req, ctx| api::run(req, ctx, api::tasks))
        .post_async("/v1/sessions", |req, ctx| {
            api::run(req, ctx, api::post_session)
        })
        .post_async("/v1/tasks/:id/complete", |req, ctx| {
            api::run(req, ctx, api::complete)
        })
        .delete_async("/v1/device", |req, ctx| {
            api::open(req, ctx, api::disconnect)
        })
        // The watch, pairing (pair.rs)
        .post_async("/v1/pair", |req, ctx| api::open(req, ctx, pair::start))
        .get_async("/v1/pair/status", |req, ctx| {
            api::open(req, ctx, pair::status)
        })
        // The phone's browser
        .get_async("/connect", |req, ctx| {
            pages::route(req, ctx, pair::connect_page)
        })
        .get_async("/connect/start", |req, ctx| {
            pages::route(req, ctx, pair::connect_start)
        })
        .get_async("/oauth/callback", |req, ctx| {
            pages::route(req, ctx, pair::callback)
        })
        .get("/privacy", |_, _| pages::privacy())
        .get("/", |_, _| pages::home())
        .run(req, env)
        .await
}
