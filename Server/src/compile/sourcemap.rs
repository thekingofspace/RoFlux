use serde::Serialize;

use crate::ir::{Node, Tree};

#[derive(Serialize)]
pub struct Entry {
    pub name: String,
    #[serde(rename = "className")]
    pub class_name: String,
    #[serde(rename = "filePaths", skip_serializing_if = "Vec::is_empty")]
    pub file_paths: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub children: Vec<Entry>,
}

fn convert(node: &Node) -> Entry {
    Entry {
        name: node.name.clone(),
        class_name: node.class_name.clone(),
        file_paths: node.file_paths.clone(),
        children: node.children.iter().map(convert).collect(),
    }
}

pub fn build(tree: &Tree) -> Entry {
    convert(&tree.root)
}

pub fn render(tree: &Tree) -> anyhow::Result<String> {
    Ok(serde_json::to_string(&build(tree))?)
}
