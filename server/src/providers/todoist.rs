//! Todoist adapter, REST API v1 (https://developer.todoist.com/api/v1/).
//!
//! - List:     GET  /tasks/filter?query=<filter>   -> { results: [task], next_cursor },
//!   most urgent first (API priority 4 = "P1" in the app), otherwise in Todoist's order
//! - Estimate: the task's `duration` field (Pro plan), when its unit is "minute"; otherwise a tag
//!   like `~50m` in the title or description (see `estimate.rs`)
//! - Log time: POST /comments { task_id, content }  (Todoist has no time tracking: total kept in KV)
//! - Complete: POST /tasks/{id}/close               -> 204

use std::cmp::Reverse;
use std::collections::HashMap;

use serde::Deserialize;
use serde::de::DeserializeOwned;
use worker::wasm_bindgen::JsValue;
use worker::{Fetch, Headers, Method, Request, RequestInit, Response, Url};

use super::TaskProvider;
use crate::error::ProviderError;
use crate::estimate;
use crate::model::{MAX_TASKS, Session, Task};

const BASE: &str = "https://api.todoist.com/api/v1";

pub struct Todoist {
    token: String,
    filter: String,
}

// ---- Todoist's JSON, only the fields we use (serde ignores the rest) ----

#[derive(Deserialize)]
struct Page<T> {
    results: Vec<T>,
}

#[derive(Deserialize)]
struct TodoistTask {
    id: String,
    content: String,
    #[serde(default)]
    description: String,
    project_id: String,
    /// 1 (normal) to 4 (urgent). The app shows it the other way round: 4 is "P1".
    #[serde(default)]
    priority: u8,
    duration: Option<Duration>,
}

#[derive(Deserialize)]
struct Duration {
    amount: Amount,
    unit: String,
}

/// The docs allow the amount to be a number or a string: accept both.
#[derive(Deserialize)]
#[serde(untagged)]
enum Amount {
    Number(u32),
    Text(String),
}

#[derive(Deserialize)]
struct Project {
    id: String,
    name: String,
}

impl Duration {
    /// Minutes, for durations in minutes. A duration in days is a calendar span, not an estimate.
    fn minutes(&self) -> Option<u32> {
        if self.unit != "minute" {
            return None;
        }
        match &self.amount {
            Amount::Number(n) => Some(*n),
            Amount::Text(s) => s.parse().ok(),
        }
    }
}

impl Todoist {
    pub fn new(token: String, filter: String) -> Self {
        Self { token, filter }
    }

    /// Sends one request with the auth header (and a JSON body, if any).
    /// Any status outside 2xx becomes a `ProviderError`.
    async fn send(
        &self,
        method: Method,
        url: &str,
        json: Option<String>,
    ) -> Result<Response, ProviderError> {
        let unreachable = |e: worker::Error| ProviderError::Unreachable(e.to_string());

        let headers = Headers::new();
        headers
            .set("Authorization", &format!("Bearer {}", self.token))
            .map_err(unreachable)?;
        let mut init = RequestInit::new();
        init.with_method(method);
        if let Some(body) = json {
            headers
                .set("Content-Type", "application/json")
                .map_err(unreachable)?;
            init.with_body(Some(JsValue::from_str(&body)));
        }
        init.with_headers(headers);

        let request = Request::new_with_init(url, &init).map_err(unreachable)?;
        let mut response = Fetch::Request(request).send().await.map_err(unreachable)?;

        match response.status_code() {
            200..=299 => Ok(response),
            404 => Err(ProviderError::NotFound),
            status => {
                let body = response.text().await.unwrap_or_default();
                Err(ProviderError::Status { status, body })
            }
        }
    }

    async fn get_json<T: DeserializeOwned>(&self, url: &str) -> Result<T, ProviderError> {
        let mut response = self.send(Method::Get, url, None).await?;
        response
            .json()
            .await
            .map_err(|e| ProviderError::Decode(e.to_string()))
    }

    /// project id -> project name. Only used to label tasks, so callers may ignore failures.
    async fn project_names(&self) -> Result<HashMap<String, String>, ProviderError> {
        let page: Page<Project> = self.get_json(&format!("{BASE}/projects?limit=200")).await?;
        Ok(page.results.into_iter().map(|p| (p.id, p.name)).collect())
    }
}

impl TaskProvider for Todoist {
    fn name(&self) -> &'static str {
        "todoist"
    }

    async fn list_today(&self) -> Result<Vec<Task>, ProviderError> {
        // parse_with_params URL-encodes the filter ("today | overdue" -> "today+%7C+overdue").
        let url = Url::parse_with_params(
            &format!("{BASE}/tasks/filter"),
            &[("query", self.filter.as_str()), ("limit", "50")],
        )
        .map_err(|e| ProviderError::Decode(e.to_string()))?;
        let mut page: Page<TodoistTask> = self.get_json(url.as_str()).await?;
        // Most urgent first. The sort is stable: equal priorities keep Todoist's order.
        page.results.sort_by_key(|t| Reverse(t.priority));

        // Missing project names are not worth failing the whole list for.
        let projects = self.project_names().await.unwrap_or_default();

        let tasks = page
            .results
            .into_iter()
            .take(MAX_TASKS)
            .map(|t| Task {
                // Pro's duration field first, then a `~50m` tag in the title, then in the description.
                estimate_min: t
                    .duration
                    .as_ref()
                    .and_then(Duration::minutes)
                    .or_else(|| estimate::find(&t.content))
                    .or_else(|| estimate::find(&t.description)),
                title: estimate::strip(&t.content),
                project: projects.get(&t.project_id).cloned(),
                spent_min: None,
                id: t.id,
            })
            .collect();
        Ok(tasks)
    }

    async fn log_session(
        &self,
        task_id: &str,
        session: &Session,
    ) -> Result<Option<u32>, ProviderError> {
        let note = if session.interrupted {
            " (interrupted)"
        } else {
            ""
        };
        let body = serde_json::json!({
            "task_id": task_id,
            "content": format!("🍅 {} · {} min{note}", session.pomodori, session.focus_min),
        });
        self.send(
            Method::Post,
            &format!("{BASE}/comments"),
            Some(body.to_string()),
        )
        .await?;
        Ok(None)
    }

    async fn complete(&self, task_id: &str) -> Result<(), ProviderError> {
        self.send(Method::Post, &format!("{BASE}/tasks/{task_id}/close"), None)
            .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sorts_most_urgent_first_and_keeps_order_otherwise() {
        let json = r#"{"results":[
            {"id":"a","content":"A","project_id":"p","priority":1},
            {"id":"b","content":"B","project_id":"p","priority":4},
            {"id":"c","content":"C","project_id":"p","priority":1},
            {"id":"d","content":"D","project_id":"p","priority":3}
        ]}"#;
        let mut page: Page<TodoistTask> = serde_json::from_str(json).unwrap();
        page.results.sort_by_key(|t| Reverse(t.priority));
        let ids: Vec<&str> = page.results.iter().map(|t| t.id.as_str()).collect();
        assert_eq!(ids, ["b", "d", "a", "c"]);
    }

    #[test]
    fn reads_todoist_task_json() {
        let json = r#"{"results":[
            {"id":"6X7rM8997g3RQmvh","content":"Buy milk","project_id":"p1","priority":1,
             "duration":{"amount":30,"unit":"minute"}},
            {"id":"2","content":"Trip","project_id":"p1","duration":{"amount":"2","unit":"day"}},
            {"id":"3","content":"No estimate","project_id":"p2","duration":null}
        ],"next_cursor":null}"#;
        let page: Page<TodoistTask> = serde_json::from_str(json).unwrap();
        let minutes: Vec<Option<u32>> = page
            .results
            .iter()
            .map(|t| t.duration.as_ref().and_then(Duration::minutes))
            .collect();
        assert_eq!(minutes, [Some(30), None, None]);
    }
}
