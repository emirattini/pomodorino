//! Errors, and the single place where they become HTTP responses (spec §5, "Errors").
//!
//! Handlers return `Result<_, ApiError>` and use `?`. Thanks to the `From` impls below,
//! `?` converts provider, KV and runtime errors into `ApiError` automatically.

use std::fmt;

use serde::Serialize;
use worker::{KvError, Response};

/// What can go wrong while talking to a task manager.
#[derive(Debug)]
pub enum ProviderError {
    /// The request never got an answer (DNS, network, timeout).
    Unreachable(String),
    /// The provider answered with an unexpected status code.
    Status { status: u16, body: String },
    /// The provider says the task doesn't exist.
    NotFound,
    /// The answer wasn't the JSON we expected.
    Decode(String),
}

/// Everything a handler can fail with.
#[derive(Debug)]
pub enum ApiError {
    Unauthorized,
    NotFound,
    BadRequest(&'static str),
    Provider(ProviderError),
    Internal(String),
}

impl ApiError {
    pub fn status(&self) -> u16 {
        match self {
            ApiError::Unauthorized => 401,
            ApiError::NotFound | ApiError::Provider(ProviderError::NotFound) => 404,
            ApiError::BadRequest(_) => 400,
            ApiError::Provider(ProviderError::Unreachable(_)) => 503,
            ApiError::Provider(_) => 502,
            ApiError::Internal(_) => 500,
        }
    }

    /// Short machine-readable code for the `error` field.
    pub fn code(&self) -> &'static str {
        match self {
            ApiError::Unauthorized => "unauthorized",
            ApiError::NotFound | ApiError::Provider(ProviderError::NotFound) => "not_found",
            ApiError::BadRequest(code) => code,
            ApiError::Provider(ProviderError::Unreachable(_)) => "provider_unreachable",
            ApiError::Provider(_) => "provider_error",
            ApiError::Internal(_) => "internal",
        }
    }

    /// Turns the error into `{ "ok": false, "error": "<code>" }` with the matching status.
    /// Details are logged, not sent: the watch only needs the code.
    pub fn into_response(self) -> worker::Result<Response> {
        if self.status() >= 500 {
            worker::console_error!("{self}");
        }
        #[derive(Serialize)]
        struct Body {
            ok: bool,
            error: &'static str,
        }
        Ok(Response::from_json(&Body {
            ok: false,
            error: self.code(),
        })?
        .with_status(self.status()))
    }
}

// `Display` gives `{}` formatting (used by the log line above and by `.to_string()`).
impl fmt::Display for ProviderError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProviderError::Unreachable(e) => write!(f, "provider unreachable: {e}"),
            ProviderError::Status { status, body } => {
                write!(f, "provider returned {status}: {body}")
            }
            ProviderError::NotFound => write!(f, "task not found at provider"),
            ProviderError::Decode(e) => write!(f, "unexpected provider response: {e}"),
        }
    }
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ApiError::Provider(e) => write!(f, "{e}"),
            ApiError::Internal(e) => write!(f, "internal error: {e}"),
            other => write!(f, "{}", other.code()),
        }
    }
}

impl std::error::Error for ProviderError {}
impl std::error::Error for ApiError {}

impl From<ProviderError> for ApiError {
    fn from(e: ProviderError) -> Self {
        ApiError::Provider(e)
    }
}

impl From<worker::Error> for ApiError {
    fn from(e: worker::Error) -> Self {
        ApiError::Internal(e.to_string())
    }
}

impl From<KvError> for ApiError {
    fn from(e: KvError) -> Self {
        ApiError::Internal(format!("kv: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_codes_follow_the_contract() {
        assert_eq!(ApiError::Unauthorized.status(), 401);
        assert_eq!(ApiError::Provider(ProviderError::NotFound).status(), 404);
        assert_eq!(
            ApiError::Provider(ProviderError::Unreachable("dns".into())).status(),
            503
        );
        let upstream = ProviderError::Status {
            status: 500,
            body: String::new(),
        };
        assert_eq!(ApiError::from(upstream).status(), 502);
    }
}
