use serde::{Deserialize, Serialize};

use crate::ir::Tree;
use crate::patch::Patch;

pub const VERSION: u32 = 1;

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Outbound {
    Hello {
        protocol: u32,
        project: String,
        id: String,
        server: String,
    },
    Sync {
        cursor: usize,
        tree: Tree,
    },
    Patch {
        cursor: usize,
        patch: Patch,
    },
    Notice {
        level: String,
        text: String,
    },
    Pong {
        cursor: usize,
    },
}

#[derive(Clone, Debug, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum Inbound {
    Ready { place: Option<String> },
    Resync,
    Ping,
    Log { level: Option<String>, text: String },
}

impl Outbound {
    pub fn encode(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| String::from("{\"type\":\"notice\"}"))
    }
}
