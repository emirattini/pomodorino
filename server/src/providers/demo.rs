//! Fixed example tasks, so the watch side can be tried without any account.

use super::TaskProvider;
use crate::error::ProviderError;
use crate::model::{Session, Task};

pub struct Demo;

// (id, title, estimate in minutes, project)
const TASKS: [(&str, &str, Option<u32>, &str); 4] = [
    ("demo_1", "Write the Q4 report", Some(50), "Work"),
    ("demo_2", "Review pull requests", Some(25), "Work"),
    (
        "demo_3",
        "Study Rust: ownership chapter",
        Some(75),
        "Learning",
    ),
    ("demo_4", "Plan tomorrow", None, "Personal"),
];

impl TaskProvider for Demo {
    fn name(&self) -> &'static str {
        "demo"
    }

    async fn list_today(&self) -> Result<Vec<Task>, ProviderError> {
        let tasks = TASKS
            .iter()
            .map(|&(id, title, estimate_min, project)| Task {
                id: id.to_string(),
                title: title.to_string(),
                estimate_min,
                spent_min: None,
                project: Some(project.to_string()),
            })
            .collect();
        Ok(tasks)
    }

    async fn log_session(
        &self,
        task_id: &str,
        _session: &Session,
    ) -> Result<Option<u32>, ProviderError> {
        if TASKS.iter().any(|(id, ..)| *id == task_id) {
            Ok(None) // the server keeps the total in KV
        } else {
            Err(ProviderError::NotFound)
        }
    }

    async fn complete(&self, _task_id: &str) -> Result<(), ProviderError> {
        Ok(())
    }
}
