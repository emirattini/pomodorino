//! Todoist OAuth (https://developer.todoist.com/api/v1/authorization.md): the "Connect with Todoist"
//! login, and refreshing tokens. Tokens of apps created in Todoist's App Management Console expire
//! after an hour and come with a refresh token that changes on every refresh.

use serde::Deserialize;
use worker::{Fetch, Headers, Method, Request, RequestInit, Response, Url};

use crate::db::Tokens;
use crate::error::ProviderError;

const AUTHORIZE_URL: &str = "https://app.todoist.com/oauth/authorize";
const TOKEN_URL: &str = "https://api.todoist.com/oauth/access_token";
const REVOKE_URL: &str = "https://api.todoist.com/api/v1/access_tokens";
const USER_URL: &str = "https://api.todoist.com/api/v1/user";
/// Read tasks, add comments, close tasks.
const SCOPE: &str = "data:read_write";

/// The app registered in Todoist's App Management Console.
pub struct TodoistApp {
    pub client_id: String,
    pub client_secret: String,
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
}

impl TokenResponse {
    fn into_tokens(self, now: i64) -> Tokens {
        Tokens {
            access_token: self.access_token,
            refresh_token: self.refresh_token,
            // `map` on Option: only computed when Todoist sent an expiry.
            expires_at: self.expires_in.map(|secs| now + secs),
        }
    }
}

impl TodoistApp {
    /// Where the browser goes to log in. `state` comes back unchanged to the callback.
    pub fn authorize_url(&self, state: &str) -> Result<Url, ProviderError> {
        Url::parse_with_params(
            AUTHORIZE_URL,
            &[
                ("client_id", self.client_id.as_str()),
                ("scope", SCOPE),
                ("state", state),
                ("response_type", "code"),
            ],
        )
        .map_err(|e| ProviderError::Decode(e.to_string()))
    }

    /// Exchanges the code from the callback for tokens.
    pub async fn exchange(&self, code: &str, now: i64) -> Result<Tokens, ProviderError> {
        let response: TokenResponse = post_form(
            TOKEN_URL,
            &[
                ("client_id", &self.client_id),
                ("client_secret", &self.client_secret),
                ("code", code),
            ],
        )
        .await?;
        Ok(response.into_tokens(now))
    }

    /// Trades the refresh token for new tokens. The old refresh token stops working.
    pub async fn refresh(&self, refresh_token: &str, now: i64) -> Result<Tokens, ProviderError> {
        let response: TokenResponse = post_form(
            TOKEN_URL,
            &[
                ("client_id", &self.client_id),
                ("client_secret", &self.client_secret),
                ("grant_type", "refresh_token"),
                ("refresh_token", refresh_token),
            ],
        )
        .await?;
        Ok(response.into_tokens(now))
    }

    /// Tells Todoist to forget the token (on Disconnect). Errors are ignored by the caller.
    pub async fn revoke(&self, access_token: &str) -> Result<(), ProviderError> {
        let url = Url::parse_with_params(
            REVOKE_URL,
            &[
                ("client_id", self.client_id.as_str()),
                ("client_secret", self.client_secret.as_str()),
                ("access_token", access_token),
            ],
        )
        .map_err(|e| ProviderError::Decode(e.to_string()))?;
        send(Method::Delete, url.as_str(), &Headers::new(), None).await?;
        Ok(())
    }
}

/// The Todoist account id behind a token, so connecting the same account twice finds the same user.
pub async fn account_id(access_token: &str) -> Result<String, ProviderError> {
    #[derive(Deserialize)]
    struct Account {
        id: String,
    }
    let headers = Headers::new();
    headers
        .set("Authorization", &format!("Bearer {access_token}"))
        .map_err(unreachable)?;
    let mut response = send(Method::Get, USER_URL, &headers, None).await?;
    let account: Account = response
        .json()
        .await
        .map_err(|e| ProviderError::Decode(e.to_string()))?;
    Ok(account.id)
}

fn unreachable(e: worker::Error) -> ProviderError {
    ProviderError::Unreachable(e.to_string())
}

/// POSTs `application/x-www-form-urlencoded` fields and decodes the JSON answer.
async fn post_form<T: for<'de> Deserialize<'de>>(
    url: &str,
    fields: &[(&str, &str)],
) -> Result<T, ProviderError> {
    let body = form_urlencoded::Serializer::new(String::new())
        .extend_pairs(fields)
        .finish();
    let headers = Headers::new();
    headers
        .set("Content-Type", "application/x-www-form-urlencoded")
        .map_err(unreachable)?;
    let mut response = send(Method::Post, url, &headers, Some(body)).await?;
    response
        .json()
        .await
        .map_err(|e| ProviderError::Decode(e.to_string()))
}

async fn send(
    method: Method,
    url: &str,
    headers: &Headers,
    body: Option<String>,
) -> Result<Response, ProviderError> {
    let mut init = RequestInit::new();
    init.with_method(method).with_headers(headers.clone());
    if let Some(body) = body {
        init.with_body(Some(body.into()));
    }
    let request = Request::new_with_init(url, &init).map_err(unreachable)?;
    let mut response = Fetch::Request(request).send().await.map_err(unreachable)?;
    match response.status_code() {
        200..=299 => Ok(response),
        status => Err(ProviderError::Status {
            status,
            body: response.text().await.unwrap_or_default(),
        }),
    }
}
