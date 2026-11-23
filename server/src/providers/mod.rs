//! Task-manager adapters (spec §6).
//!
//! Every provider implements [`TaskProvider`]. The server picks one at runtime and stores it in
//! the [`Provider`] enum, whose impl simply forwards each call to the variant inside.

mod demo;
mod todoist;

pub use demo::Demo;
pub use todoist::Todoist;

use crate::error::ProviderError;
use crate::model::{Session, Task};

// `async fn` in a public trait triggers a lint, because callers can't require the returned future
// to be `Send`. The Workers runtime is single-threaded, so we never need `Send`.
#[allow(async_fn_in_trait)]
pub trait TaskProvider {
    /// Short name, used in `/v1/ping` and in KV keys.
    fn name(&self) -> &'static str;

    /// Today's tasks in the provider's own order. `spent_min` is `None` unless the provider tracks
    /// time itself; the server fills it from KV otherwise.
    async fn list_today(&self) -> Result<Vec<Task>, ProviderError>;

    /// Records a finished session on the task. Returns the provider's own total of minutes spent
    /// (`Some`) or `None` when the provider doesn't track time (the server keeps the total in KV).
    async fn log_session(
        &self,
        task_id: &str,
        session: &Session,
    ) -> Result<Option<u32>, ProviderError>;

    async fn complete(&self, task_id: &str) -> Result<(), ProviderError>;
}

/// One variant per provider. Adding Jira later = one more variant + one more line per match.
pub enum Provider {
    Demo(Demo),
    Todoist(Todoist),
}

impl TaskProvider for Provider {
    fn name(&self) -> &'static str {
        match self {
            Provider::Demo(p) => p.name(),
            Provider::Todoist(p) => p.name(),
        }
    }

    async fn list_today(&self) -> Result<Vec<Task>, ProviderError> {
        match self {
            Provider::Demo(p) => p.list_today().await,
            Provider::Todoist(p) => p.list_today().await,
        }
    }

    async fn log_session(
        &self,
        task_id: &str,
        session: &Session,
    ) -> Result<Option<u32>, ProviderError> {
        match self {
            Provider::Demo(p) => p.log_session(task_id, session).await,
            Provider::Todoist(p) => p.log_session(task_id, session).await,
        }
    }

    async fn complete(&self, task_id: &str) -> Result<(), ProviderError> {
        match self {
            Provider::Demo(p) => p.complete(task_id).await,
            Provider::Todoist(p) => p.complete(task_id).await,
        }
    }
}
