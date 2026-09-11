use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use serde_json::json;
use tokio::sync::{broadcast, Mutex};

use crate::compile::Build;
use crate::hooks::outbox::{Outgoing, Target};
use crate::patch::Patch;

use super::protocol::Outbound;

struct Backlog {
    dropped: usize,
    items: Vec<Arc<String>>,
}

pub struct Channel {
    backlog: Mutex<Backlog>,
    sender: broadcast::Sender<Arc<String>>,
    limit: usize,
}

impl Channel {
    pub fn new(limit: usize) -> Self {
        let (sender, _) = broadcast::channel(256);

        Channel {
            backlog: Mutex::new(Backlog {
                dropped: 0,
                items: Vec::new(),
            }),
            sender,
            limit,
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Arc<String>> {
        self.sender.subscribe()
    }

    pub async fn cursor(&self) -> usize {
        let backlog = self.backlog.lock().await;
        backlog.dropped + backlog.items.len()
    }

    pub async fn push(&self, encoded: Arc<String>) {
        {
            let mut backlog = self.backlog.lock().await;
            backlog.items.push(encoded.clone());

            if backlog.items.len() > self.limit {
                let excess = backlog.items.len() - self.limit;
                backlog.items.drain(..excess);
                backlog.dropped += excess;
            }
        }

        let _ = self.sender.send(encoded);
    }

    pub async fn since(&self, cursor: usize) -> (usize, Vec<Arc<String>>) {
        let backlog = self.backlog.lock().await;
        let end = backlog.dropped + backlog.items.len();
        let start = cursor.saturating_sub(backlog.dropped).min(backlog.items.len());

        (end, backlog.items[start..].to_vec())
    }
}

pub struct Shared {
    pub build: Mutex<Build>,
    pub main: Channel,
    pub game: Channel,
    pub clients: AtomicUsize,
}

impl Shared {
    pub fn new(build: Build) -> Arc<Self> {
        Arc::new(Shared {
            build: Mutex::new(build),
            main: Channel::new(512),
            game: Channel::new(256),
            clients: AtomicUsize::new(0),
        })
    }

    pub fn connected(&self) -> usize {
        self.clients.load(Ordering::Relaxed)
    }

    pub async fn cursor(&self) -> usize {
        self.main.cursor().await
    }

    pub async fn publish(&self, message: Outbound) {
        self.main.push(Arc::new(message.encode())).await;
    }

    pub async fn send(&self, outgoing: Outgoing) {
        match outgoing.target {
            Target::Studio => self.publish(Outbound::Message { args: outgoing.args }).await,
            Target::Game => {
                let encoded = json!({ "type": "message", "args": outgoing.args }).to_string();
                self.game.push(Arc::new(encoded)).await;
            }
        }
    }

    pub async fn snapshot(&self) -> Outbound {
        let build = self.build.lock().await;
        let cursor = self.main.cursor().await;

        Outbound::Sync {
            cursor,
            tree: build.snapshot(),
        }
    }

    pub async fn hello(&self) -> Outbound {
        let build = self.build.lock().await;

        Outbound::Hello {
            protocol: super::protocol::VERSION,
            project: build.config.name.clone(),
            id: build.config.id.clone(),
            server: env!("CARGO_PKG_VERSION").to_string(),
        }
    }

    pub async fn broadcast_patch(&self, patch: Patch) {
        let cursor = self.cursor().await;
        self.publish(Outbound::Patch { cursor, patch }).await;
    }
}
