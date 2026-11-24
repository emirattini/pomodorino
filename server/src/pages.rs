//! The few web pages the phone shows while connecting: small, no JavaScript, no external assets.

use std::future::Future;

use worker::{Request, Response, RouteContext};

use crate::error::ApiError;

const REPO: &str = "https://github.com/emirattini/pomodorino";

/// Runs a page handler; an error becomes a friendly page instead of JSON.
pub async fn route<F, Fut>(
    req: Request,
    ctx: RouteContext<()>,
    handler: F,
) -> worker::Result<Response>
where
    F: FnOnce(Request, RouteContext<()>) -> Fut,
    Fut: Future<Output = Result<Response, ApiError>>,
{
    match handler(req, ctx).await {
        Ok(response) => Ok(response),
        Err(e) => {
            if e.status() >= 500 {
                worker::console_error!("{e}");
            }
            let (title, text) = match e {
                ApiError::Expired | ApiError::NotFound => (
                    "This link has expired",
                    "Pairing links work for 15 minutes. Choose <b>Connect Todoist</b> on your watch again.",
                ),
                ApiError::BadRequest("wrong_browser") => (
                    "Start again from the watch",
                    "This login was started in another browser. Choose <b>Connect Todoist</b> on your watch \
                     again and open the link it sends.",
                ),
                _ => (
                    "Something went wrong",
                    "Todoist couldn't be reached, or the login didn't finish. Try again from your watch in a moment.",
                ),
            };
            Ok(page(title, &format!("<p>{text}</p>"))?.with_status(e.status()))
        }
    }
}

/// A complete HTML page. `body` is trusted markup: escape anything user-supplied with [`esc`].
pub fn page(title: &str, body: &str) -> worker::Result<Response> {
    let title = esc(title);
    Response::from_html(format!(
        r#"<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>{title} · Pomodorino</title>
<style>
  body {{ margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0b0b0c;
         color: #eee; font: 17px/1.5 system-ui, -apple-system, sans-serif; }}
  main {{ max-width: 26rem; padding: 2rem 1.5rem; text-align: center; }}
  .logo {{ font-size: 3rem; }}
  h1 {{ font-size: 1.45rem; margin: .5rem 0 1rem; }}
  p {{ color: #bbb; }}
  .code {{ font: 600 1.6rem ui-monospace, monospace; letter-spacing: .2em; color: #fff;
          background: #1c1c1f; border-radius: .6rem; padding: .5rem 1rem; display: inline-block; }}
  a.button {{ display: block; margin: 1.5rem 0 .5rem; padding: .9rem; border-radius: .7rem;
             background: #e44332; color: #fff; text-decoration: none; font-weight: 600; }}
  small, small a {{ color: #777; }}
</style></head>
<body><main><div class="logo">🍅</div><h1>{title}</h1>{body}
<p><small><a href="/privacy">Privacy</a> · <a href="{REPO}">Pomodorino on GitHub</a></small></p>
</main></body></html>"#
    ))
}

/// Escapes text for HTML.
pub fn esc(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '&' => "&amp;".to_string(),
            '<' => "&lt;".to_string(),
            '>' => "&gt;".to_string(),
            '"' => "&quot;".to_string(),
            '\'' => "&#39;".to_string(),
            c => c.to_string(),
        })
        .collect()
}

pub fn home() -> worker::Result<Response> {
    page(
        "Pomodorino",
        &format!(
            "<p>The server behind the Pomodorino app for Garmin watches. To connect your tasks, choose \
             <b>Connect Todoist</b> in the app's menu on your watch.</p>\
             <p><a href=\"{REPO}\">Source code and instructions</a></p>"
        ),
    )
}

pub fn privacy() -> worker::Result<Response> {
    page(
        "Privacy",
        &format!(
            r#"<div style="text-align:left">
<p>When you connect Todoist, this server stores:</p>
<ul>
<li>your Todoist account id and the access tokens Todoist gives it, to read today's tasks, add a comment
when you finish a session, and complete tasks you mark as done on the watch;</li>
<li>a fingerprint (SHA-256) of your watch's key, not the key itself;</li>
<li>the ids of the sessions your watch sent and the minutes spent per task.</li>
</ul>
<p>Nothing else: no name, email or location. Nothing is shared with anyone or used for anything else.
The server runs on Cloudflare Workers.</p>
<p><b>To delete everything</b>, choose <b>Disconnect Todoist</b> in the app's menu: the server forgets
you and tells Todoist to revoke its access. You can also remove Pomodorino in Todoist → Settings →
Integrations.</p>
<p>Questions: <a href="{REPO}/issues">open an issue on GitHub</a>.</p>
</div>"#
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escapes_html() {
        assert_eq!(
            esc(r#"<a href="x">&'"#),
            "&lt;a href=&quot;x&quot;&gt;&amp;&#39;"
        );
    }
}
