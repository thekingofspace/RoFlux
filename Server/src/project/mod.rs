pub mod classify;
pub mod meta;
pub mod scan;

use serde_json::{Map, Value};

#[derive(Clone, Debug, Default)]
pub struct Loaded {
    pub class_name: Option<String>,
    pub name: Option<String>,
    pub parent: Option<String>,
    pub properties: Map<String, Value>,
    pub attributes: Map<String, Value>,
    pub tags: Vec<String>,
    pub children: Vec<crate::ir::Node>,
    pub skip: bool,
}

pub trait Transform: Send + Sync {
    fn file(&self, relative: &str, extension: &str, raw: &str) -> anyhow::Result<Option<Vec<Loaded>>>;
    fn source(&self, relative: &str, class_name: &str, source: String) -> anyhow::Result<String>;
    fn claims(&self, extension: &str) -> bool;
}

pub struct Passthrough;

impl Transform for Passthrough {
    fn file(&self, _: &str, _: &str, _: &str) -> anyhow::Result<Option<Vec<Loaded>>> {
        Ok(None)
    }

    fn source(&self, _: &str, _: &str, source: String) -> anyhow::Result<String> {
        Ok(source)
    }

    fn claims(&self, _: &str) -> bool {
        false
    }
}
