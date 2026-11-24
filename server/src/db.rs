//! The D1 (SQLite) database: users, their watches, and what Todoist can't store.
//! Tables are in `migrations/0001_users.sql`.
//!
//! D1 is strongly consistent, unlike KV: Todoist's refresh tokens change on every refresh, and
//! reusing an old one revokes the user's access, so we must never read a stale token.

use std::collections::HashMap;

use serde::Deserialize;
use worker::wasm_bindgen::JsValue;
use worker::{D1Database, D1PreparedStatement, Result};

pub struct Db {
    d1: D1Database,
}

/// A watch, linked to a user or still pairing.
#[derive(Deserialize)]
pub struct Device {
    pub key_hash: String,
    pub user_id: Option<String>,
    pub created_at: i64,
}

#[derive(Deserialize)]
pub struct User {
    pub id: String,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at: Option<i64>,
}

/// Tokens from an OAuth login or refresh.
pub struct Tokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at: Option<i64>,
}

/// Values for `?` placeholders. `JsValue` is what D1's JavaScript API takes.
fn text(s: &str) -> JsValue {
    JsValue::from_str(s)
}

fn int(n: i64) -> JsValue {
    JsValue::from_f64(n as f64) // JS numbers are exact up to 2^53, plenty for timestamps
}

fn opt_text(s: Option<&str>) -> JsValue {
    s.map_or(JsValue::NULL, text)
}

fn opt_int(n: Option<i64>) -> JsValue {
    n.map_or(JsValue::NULL, int)
}

impl Db {
    pub fn new(d1: D1Database) -> Self {
        Self { d1 }
    }

    fn query(&self, sql: &str, args: &[JsValue]) -> Result<D1PreparedStatement> {
        self.d1.prepare(sql).bind(args)
    }

    /// Runs a write and returns how many rows it changed.
    async fn write(&self, sql: &str, args: &[JsValue]) -> Result<usize> {
        let result = self.query(sql, args)?.run().await?;
        Ok(result.meta()?.and_then(|m| m.changes).unwrap_or(0))
    }

    // ---- pairing ----

    pub async fn add_pending_device(&self, key_hash: &str, code: &str, now: i64) -> Result<()> {
        self.write(
            "INSERT INTO devices (key_hash, code, created_at) VALUES (?, ?, ?)",
            &[text(key_hash), text(code), int(now)],
        )
        .await?;
        Ok(())
    }

    /// Forgets pairings that were started but never finished.
    pub async fn delete_pending_before(&self, cutoff: i64) -> Result<()> {
        self.write(
            "DELETE FROM devices WHERE user_id IS NULL AND created_at < ?",
            &[int(cutoff)],
        )
        .await?;
        Ok(())
    }

    pub async fn pending_by_code(&self, code: &str) -> Result<Option<Device>> {
        self.query(
            "SELECT key_hash, user_id, created_at FROM devices WHERE code = ? AND user_id IS NULL",
            &[text(code)],
        )?
        .first(None)
        .await
    }

    pub async fn pending_by_nonce(&self, nonce: &str) -> Result<Option<Device>> {
        self.query(
            "SELECT key_hash, user_id, created_at FROM devices WHERE nonce = ? AND user_id IS NULL",
            &[text(nonce)],
        )?
        .first(None)
        .await
    }

    pub async fn set_nonce(&self, key_hash: &str, nonce: &str) -> Result<()> {
        self.write(
            "UPDATE devices SET nonce = ? WHERE key_hash = ?",
            &[text(nonce), text(key_hash)],
        )
        .await?;
        Ok(())
    }

    pub async fn link_device(&self, key_hash: &str, user_id: &str) -> Result<()> {
        self.write(
            "UPDATE devices SET user_id = ?, code = NULL, nonce = NULL WHERE key_hash = ?",
            &[text(user_id), text(key_hash)],
        )
        .await?;
        Ok(())
    }

    // ---- devices and users ----

    pub async fn device(&self, key_hash: &str) -> Result<Option<Device>> {
        self.query(
            "SELECT key_hash, user_id, created_at FROM devices WHERE key_hash = ?",
            &[text(key_hash)],
        )?
        .first(None)
        .await
    }

    pub async fn delete_device(&self, key_hash: &str) -> Result<()> {
        self.write("DELETE FROM devices WHERE key_hash = ?", &[text(key_hash)])
            .await?;
        Ok(())
    }

    pub async fn device_count(&self, user_id: &str) -> Result<u32> {
        let n: Option<u32> = self
            .query(
                "SELECT COUNT(*) AS n FROM devices WHERE user_id = ?",
                &[text(user_id)],
            )?
            .first(Some("n"))
            .await?;
        Ok(n.unwrap_or(0))
    }

    pub async fn user(&self, id: &str) -> Result<Option<User>> {
        self.query(
            "SELECT id, access_token, refresh_token, expires_at FROM users WHERE id = ?",
            &[text(id)],
        )?
        .first(None)
        .await
    }

    /// Creates the user, or updates the tokens of the one already connected with this account.
    /// Returns the user's id (`new_id` for a new user, the existing id otherwise).
    pub async fn upsert_user(
        &self,
        new_id: &str,
        provider: &str,
        account: &str,
        tokens: &Tokens,
        now: i64,
    ) -> Result<String> {
        let id: Option<String> = self
            .query(
                "INSERT INTO users (id, provider, account, access_token, refresh_token, expires_at, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT (provider, account) DO UPDATE SET
                     access_token = excluded.access_token,
                     refresh_token = excluded.refresh_token,
                     expires_at = excluded.expires_at
                 RETURNING id",
                &[
                    text(new_id),
                    text(provider),
                    text(account),
                    text(&tokens.access_token),
                    opt_text(tokens.refresh_token.as_deref()),
                    opt_int(tokens.expires_at),
                    int(now),
                ],
            )?
            .first(Some("id"))
            .await?;
        Ok(id.unwrap_or_else(|| new_id.to_string()))
    }

    /// Stores refreshed tokens, but only if the refresh token is still the one we refreshed with
    /// (compare-and-swap). Returns false if another request refreshed first.
    pub async fn replace_tokens(
        &self,
        user_id: &str,
        old_refresh: &str,
        tokens: &Tokens,
    ) -> Result<bool> {
        let changed = self
            .write(
                "UPDATE users SET access_token = ?, refresh_token = ?, expires_at = ?
                 WHERE id = ? AND refresh_token = ?",
                &[
                    text(&tokens.access_token),
                    opt_text(tokens.refresh_token.as_deref()),
                    opt_int(tokens.expires_at),
                    text(user_id),
                    text(old_refresh),
                ],
            )
            .await?;
        Ok(changed == 1)
    }

    /// Removes the user and everything stored for them.
    pub async fn delete_user(&self, user_id: &str) -> Result<()> {
        let id = [text(user_id)];
        self.d1
            .batch(vec![
                self.query("DELETE FROM devices WHERE user_id = ?", &id)?,
                self.query("DELETE FROM sessions WHERE user_id = ?", &id)?,
                self.query("DELETE FROM spent WHERE user_id = ?", &id)?,
                self.query("DELETE FROM users WHERE id = ?", &id)?,
            ])
            .await?;
        Ok(())
    }

    // ---- sessions and minutes ----

    /// Records the session id. Returns false if it was already there (a retry from the watch).
    pub async fn mark_session(&self, user_id: &str, session_id: &str, now: i64) -> Result<bool> {
        let changed = self
            .write(
                "INSERT OR IGNORE INTO sessions (user_id, id, created_at) VALUES (?, ?, ?)",
                &[text(user_id), text(session_id), int(now)],
            )
            .await?;
        Ok(changed == 1)
    }

    pub async fn seen_session(&self, user_id: &str, session_id: &str) -> Result<bool> {
        let row: Option<i64> = self
            .query(
                "SELECT 1 AS one FROM sessions WHERE user_id = ? AND id = ?",
                &[text(user_id), text(session_id)],
            )?
            .first(Some("one"))
            .await?;
        Ok(row.is_some())
    }

    /// Minutes per task for this user, in one query.
    pub async fn spent_all(&self, user_id: &str) -> Result<HashMap<String, u32>> {
        #[derive(Deserialize)]
        struct Row {
            task_id: String,
            minutes: u32,
        }
        let rows: Vec<Row> = self
            .query(
                "SELECT task_id, minutes FROM spent WHERE user_id = ?",
                &[text(user_id)],
            )?
            .all()
            .await?
            .results()?;
        Ok(rows.into_iter().map(|r| (r.task_id, r.minutes)).collect())
    }

    pub async fn spent(&self, user_id: &str, task_id: &str) -> Result<Option<u32>> {
        self.query(
            "SELECT minutes FROM spent WHERE user_id = ? AND task_id = ?",
            &[text(user_id), text(task_id)],
        )?
        .first(Some("minutes"))
        .await
    }

    /// Adds `minutes` to the task's total in one atomic statement and returns the new total.
    pub async fn add_spent(&self, user_id: &str, task_id: &str, minutes: u32) -> Result<u32> {
        let total: Option<u32> = self
            .query(
                "INSERT INTO spent (user_id, task_id, minutes) VALUES (?, ?, ?)
                 ON CONFLICT (user_id, task_id) DO UPDATE SET minutes = minutes + excluded.minutes
                 RETURNING minutes",
                &[text(user_id), text(task_id), int(minutes.into())],
            )?
            .first(Some("minutes"))
            .await?;
        Ok(total.unwrap_or(minutes))
    }
}
