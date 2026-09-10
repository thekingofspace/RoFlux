use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::paths;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Ownership {
    Managed,
    Passthrough,
    Reference,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Node {
    pub id: String,
    pub name: String,
    #[serde(rename = "className")]
    pub class_name: String,
    pub ownership: Ownership,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub properties: Map<String, Value>,
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub attributes: Map<String, Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub children: Vec<Node>,
    #[serde(default, skip_serializing_if = "Vec::is_empty", rename = "filePaths")]
    pub file_paths: Vec<String>,
}

impl Node {
    pub fn new(id: impl Into<String>, name: impl Into<String>, class_name: impl Into<String>) -> Self {
        Node {
            id: id.into(),
            name: name.into(),
            class_name: class_name.into(),
            ownership: Ownership::Managed,
            properties: Map::new(),
            attributes: Map::new(),
            tags: Vec::new(),
            children: Vec::new(),
            file_paths: Vec::new(),
        }
    }

    pub fn passthrough(id: impl Into<String>, name: impl Into<String>, class_name: impl Into<String>) -> Self {
        let mut node = Node::new(id, name, class_name);
        node.ownership = Ownership::Passthrough;
        node
    }

    pub fn find_child(&self, name: &str) -> Option<&Node> {
        self.children.iter().find(|child| child.name == name)
    }

    pub fn child_index(&self, name: &str) -> Option<usize> {
        self.children.iter().position(|child| child.name == name)
    }

    pub fn sort(&mut self) {
        self.children.sort_by(|a, b| a.name.cmp(&b.name));
        for child in &mut self.children {
            child.sort();
        }
    }

    pub fn descendants(&self) -> usize {
        self.children.iter().map(|child| 1 + child.descendants()).sum()
    }

    pub fn scripts(&self) -> usize {
        let own = usize::from(matches!(
            self.class_name.as_str(),
            "Script" | "LocalScript" | "ModuleScript"
        ));
        own + self.children.iter().map(Node::scripts).sum::<usize>()
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Tree {
    pub root: Node,
}

impl Tree {
    pub fn new(name: &str) -> Self {
        let mut root = Node::passthrough("", name, "DataModel");
        root.file_paths.push("default.project.json".into());
        Tree { root }
    }

    pub fn reserve(&mut self, path: &[String], class_of: impl Fn(usize, &str) -> String) -> &mut Node {
        let mut cursor = &mut self.root;
        let mut trail = String::new();

        for (depth, part) in path.iter().enumerate() {
            trail = paths::child(&trail, part);

            let index = match cursor.child_index(part) {
                Some(index) => index,
                None => {
                    let class_name = class_of(depth, part);
                    cursor.children.push(Node::passthrough(trail.clone(), part, class_name));
                    cursor.children.len() - 1
                }
            };

            cursor = &mut cursor.children[index];
        }

        cursor
    }

    pub fn sort(&mut self) {
        self.root.sort();
    }
}

pub fn reindex_root(root: &mut Node) {
    root.id = String::new();

    for child in &mut root.children {
        reindex(child, "");
    }
}

pub fn reindex(node: &mut Node, parent: &str) {
    node.id = paths::child(parent, &node.name);
    let id = node.id.clone();
    for child in &mut node.children {
        reindex(child, &id);
    }
}
