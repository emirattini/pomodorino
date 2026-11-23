//! The JSON contract between the watch and this server (spec §5).
//! `rename_all = "camelCase"` maps Rust's `estimate_min` to the JSON's `estimateMin`.

use serde::{Deserialize, Serialize};

/// Longest title we send to the watch (in characters, not bytes).
pub const MAX_TITLE: usize = 60;
/// Most tasks we send to the watch: it has little memory.
pub const MAX_TASKS: usize = 20;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Task {
    pub id: String,
    pub title: String,
    pub estimate_min: Option<u32>,
    pub spent_min: Option<u32>,
    pub project: Option<String>,
}

impl Task {
    /// Applies the size limits of the contract.
    pub fn normalized(mut self) -> Self {
        self.title = truncate(&self.title, MAX_TITLE);
        self.project = self.project.map(|p| truncate(&p, 24));
        self
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub session_id: String,
    pub task_id: String,
    pub started_at: String, // ISO 8601, passed through as is
    pub ended_at: String,
    pub focus_min: u32,
    pub pomodori: u32,
    #[serde(default)]
    pub interrupted: bool,
}

impl Session {
    /// Rejects values no real session can have, before anything is written.
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.session_id.is_empty() || self.session_id.len() > 64 {
            return Err("bad_session_id");
        }
        if self.task_id.is_empty() {
            return Err("bad_task_id");
        }
        if self.focus_min > 24 * 60 || self.pomodori > 100 {
            return Err("bad_duration");
        }
        Ok(())
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskList {
    pub fetched_at: String,
    pub tasks: Vec<Task>,
}

#[derive(Serialize)]
pub struct Ping {
    pub ok: bool,
    pub provider: &'static str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionAck {
    pub ok: bool,
    pub spent_min: Option<u32>,
    pub duplicate: bool,
}

/// `{ "ok": true }`
#[derive(Serialize)]
pub struct Done {
    pub ok: bool,
}

/// Cuts `s` to at most `max` characters, ending with "…" when it was cut.
/// Works on chars, so it never splits a multi-byte UTF-8 character (slicing bytes would panic).
pub fn truncate(s: &str, max: usize) -> String {
    let s = s.trim();
    if s.chars().count() <= max {
        return s.to_string();
    }
    let mut out: String = s.chars().take(max - 1).collect();
    out.truncate(out.trim_end().len());
    out.push('…');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncate_keeps_short_titles() {
        assert_eq!(truncate("  Write report ", 60), "Write report");
    }

    #[test]
    fn truncate_counts_chars_not_bytes() {
        let t = truncate("Caffè è più buono così", 10);
        assert_eq!(t.chars().count(), 10);
        assert_eq!(t, "Caffè è p…");
    }

    #[test]
    fn task_json_is_camel_case() {
        let t = Task {
            id: "1".into(),
            title: "x".into(),
            estimate_min: Some(30),
            spent_min: None,
            project: None,
        };
        let json = serde_json::to_string(&t).unwrap();
        assert_eq!(
            json,
            r#"{"id":"1","title":"x","estimateMin":30,"spentMin":null,"project":null}"#
        );
    }

    #[test]
    fn session_validation() {
        let mut s: Session = serde_json::from_str(
            r#"{"sessionId":"a1","taskId":"t","startedAt":"","endedAt":"","focusMin":50,"pomodori":2}"#,
        )
        .unwrap();
        assert!(!s.interrupted); // missing field -> #[serde(default)]
        assert_eq!(s.validate(), Ok(()));
        s.focus_min = 5000;
        assert_eq!(s.validate(), Err("bad_duration"));
    }
}
