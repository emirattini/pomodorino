//! Thin wrapper around Workers KV (spec §7.4).
//!
//! Keys:
//! - `session:{sessionId}`        marker for de-duplication, expires after 30 days
//! - `spent:{provider}:{taskId}`  minutes logged so far, for providers without native time tracking

use worker::{KvStore, Result};

const SESSION_TTL_SECS: u64 = 30 * 24 * 60 * 60;

pub struct Store {
    kv: KvStore,
}

impl Store {
    pub fn new(kv: KvStore) -> Self {
        Self { kv }
    }

    /// Has this session already been recorded? (Retries from the watch's offline queue.)
    pub async fn seen_session(&self, session_id: &str) -> Result<bool> {
        let marker = self.kv.get(&session_key(session_id)).text().await?;
        Ok(marker.is_some())
    }

    pub async fn mark_session(&self, session_id: &str) -> Result<()> {
        self.kv
            .put(&session_key(session_id), "1")?
            .expiration_ttl(SESSION_TTL_SECS)
            .execute()
            .await?;
        Ok(())
    }

    pub async fn spent(&self, provider: &str, task_id: &str) -> Result<Option<u32>> {
        let value = self.kv.get(&spent_key(provider, task_id)).text().await?;
        // `and_then` + `.ok()`: a missing key or a non-number both become None.
        Ok(value.and_then(|v| v.parse().ok()))
    }

    /// Adds `minutes` to the task's total and returns the new total.
    /// KV has no atomic increment; that's fine for one user, whose watch sends one session at a time.
    pub async fn add_spent(&self, provider: &str, task_id: &str, minutes: u32) -> Result<u32> {
        let total = self.spent(provider, task_id).await?.unwrap_or(0) + minutes;
        self.kv
            .put(&spent_key(provider, task_id), total)?
            .execute()
            .await?;
        Ok(total)
    }
}

fn session_key(session_id: &str) -> String {
    format!("session:{session_id}")
}

fn spent_key(provider: &str, task_id: &str) -> String {
    format!("spent:{provider}:{task_id}")
}
