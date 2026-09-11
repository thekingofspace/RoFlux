use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use notify::{Event, EventKind, RecursiveMode, Watcher};
use tokio::sync::mpsc;

use crate::log;
use crate::project::classify;

use super::protocol::Outbound;
use super::state::Shared;

const DEBOUNCE: Duration = Duration::from_millis(120);

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Change {
    Added(String),
    Removed(String),
    Changed(String),
}

impl Change {
    pub fn path(&self) -> &str {
        match self {
            Change::Added(path) | Change::Removed(path) | Change::Changed(path) => path,
        }
    }

    pub fn event(&self) -> &'static str {
        match self {
            Change::Added(_) => "added",
            Change::Removed(_) => "removed",
            Change::Changed(_) => "changed",
        }
    }
}

fn relevant(path: &Path) -> bool {
    let Some(name) = path.file_name().map(|value| value.to_string_lossy().to_string()) else {
        return false;
    };

    if name.starts_with('.') || name.ends_with('~') {
        return false;
    }

    if name == "sourcemap.json" {
        return false;
    }

    if path.components().any(|part| {
        let value = part.as_os_str().to_string_lossy();
        value == "target" || value == "node_modules" || value == ".git"
    }) {
        return false;
    }

    true
}

fn classify_event(kind: &EventKind) -> Option<fn(String) -> Change> {
    match kind {
        EventKind::Create(_) => Some(Change::Added),
        EventKind::Remove(_) => Some(Change::Removed),
        EventKind::Modify(_) => Some(Change::Changed),
        _ => None,
    }
}

pub async fn run(shared: Arc<Shared>, root: PathBuf) -> Result<()> {
    let (sender, mut receiver) = mpsc::unbounded_channel::<Change>();

    let mut watcher = notify::recommended_watcher(move |result: notify::Result<Event>| {
        let Ok(event) = result else {
            return;
        };

        let Some(build) = classify_event(&event.kind) else {
            return;
        };

        for path in event.paths {
            if !relevant(&path) {
                continue;
            }

            let _ = sender.send(build(path.to_string_lossy().replace('\\', "/")));
        }
    })?;

    watcher.watch(&root, RecursiveMode::Recursive)?;
    log::info(format!("watching {}", root.display()));

    let mut batch: Vec<Change> = Vec::new();

    loop {
        let first = match receiver.recv().await {
            Some(change) => change,
            None => break,
        };

        batch.clear();
        batch.push(first);

        loop {
            match tokio::time::timeout(DEBOUNCE, receiver.recv()).await {
                Ok(Some(change)) => {
                    if !batch.contains(&change) {
                        batch.push(change);
                    }
                }
                _ => break,
            }
        }

        apply(&shared, &root, &batch).await;
    }

    Ok(())
}

async fn apply(shared: &Arc<Shared>, root: &Path, batch: &[Change]) {
    let mut build = shared.build.lock().await;

    let touched_hooks = batch.iter().any(|change| {
        let path = change.path();
        path.contains("/scripts/") && classify::is_luau(path)
    });

    let manifest = build.manifest.clone();

    let touched_config = batch
        .iter()
        .any(|change| change.path().ends_with(&manifest));

    if touched_hooks {
        log::info("hook scripts changed, reloading");

        if let Err(error) = build.reload_hooks() {
            log::fail(format!("hook reload failed: {error}"));
            shared
                .publish(Outbound::Notice {
                    level: "error".into(),
                    text: format!("hook reload failed: {error}"),
                })
                .await;
            return;
        }
    }

    if touched_config {
        log::info(format!("{manifest} changed, reloading"));

        if let Err(error) = build.reload_config() {
            log::fail(format!("project reload failed: {error}"));
            shared
                .publish(Outbound::Notice {
                    level: "error".into(),
                    text: format!("project reload failed: {error}"),
                })
                .await;
            return;
        }
    }

    for change in batch {
        let relative = change
            .path()
            .strip_prefix(&root.to_string_lossy().replace('\\', "/"))
            .unwrap_or(change.path())
            .trim_start_matches('/')
            .to_string();

        build.hooks.notify(change.event(), &relative);
    }

    let patch = match build.rebuild() {
        Ok(patch) => patch,
        Err(error) => {
            log::fail(format!("rebuild failed: {error}"));
            shared
                .publish(Outbound::Notice {
                    level: "error".into(),
                    text: format!("rebuild failed: {error}"),
                })
                .await;
            return;
        }
    };

    if patch.is_empty() {
        return;
    }

    log::sync(format!("{} ({})", patch.summary(), build.stats()));

    for line in patch.lines(25) {
        log::detail(&line);
    }

    build.hooks.emit(
        "sync",
        &serde_json::json!({
            "added": patch.added(),
            "updated": patch.updated(),
            "removed": patch.removed(),
            "summary": patch.summary(),
            "lines": patch.lines(500),
            "clients": shared.connected(),
        }),
    );

    drop(build);

    shared.broadcast_patch(patch).await;
}
