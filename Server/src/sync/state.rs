use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use tokio::sync::{broadcast, Mutex};

use crate::compile::Build;
use crate::patch::Patch;

use super::protocol::Outbound;

pub struct Shared {
    pub build: Mutex<Build>,
    pub outbound: broadcast::Sender<Arc<String>>,
    pub history: Mutex<Vec<Arc<String>>>,
    pub clients: AtomicUsize,
    pub limit: usize,
}

impl Shared {
    pub fn new(build: Build) -> Arc<Self> {
        let (outbound, _) = broadcast::channel(256);

        Arc::new(Shared {
            build: Mutex::new(build),
            outbound,
            history: Mutex::new(Vec::new()),
            clients: AtomicUsize::new(0),
            limit: 512,
        })
    }

    pub fn connected(&self) -> usize {
        self.clients.load(Ordering::Relaxed)
    }

    pub async fn cursor(&self) -> usize {
        self.history.lock().await.len()
    }

    pub async fn publish(&self, message: Outbound) {
        let encoded = Arc::new(message.encode());

        {
            let mut history = self.history.lock().await;
            history.push(encoded.clone());

            if history.len() > self.limit {
                let excess = history.len() - self.limit;
                history.drain(..excess);
            }
        }

        let _ = self.outbound.send(encoded);
    }

    pub async fn since(&self, cursor: usize) -> Vec<Arc<String>> {
        let history = self.history.lock().await;

        if cursor >= history.len() {
            return Vec::new();
        }

        history[cursor..].to_vec()
    }

    pub async fn snapshot(&self) -> Outbound {
        let build = self.build.lock().await;
        let cursor = self.history.lock().await.len();

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
