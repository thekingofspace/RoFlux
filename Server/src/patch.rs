use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::ir::{Node, Ownership, Tree};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "lowercase")]
pub enum Op {
    Add {
        parent: String,
        node: Node,
    },
    Update {
        id: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        name: Option<String>,
        #[serde(rename = "className", skip_serializing_if = "Option::is_none")]
        class_name: Option<String>,
        #[serde(skip_serializing_if = "Map::is_empty")]
        properties: Map<String, Value>,
        #[serde(skip_serializing_if = "Map::is_empty")]
        attributes: Map<String, Value>,
        #[serde(rename = "clearedAttributes", skip_serializing_if = "Vec::is_empty")]
        cleared_attributes: Vec<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        tags: Option<Vec<String>>,
    },
    Remove {
        id: String,
    },
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Patch {
    pub ops: Vec<Op>,
}

impl Patch {
    pub fn is_empty(&self) -> bool {
        self.ops.is_empty()
    }

    pub fn added(&self) -> usize {
        self.ops.iter().filter(|op| matches!(op, Op::Add { .. })).count()
    }

    pub fn updated(&self) -> usize {
        self.ops.iter().filter(|op| matches!(op, Op::Update { .. })).count()
    }

    pub fn removed(&self) -> usize {
        self.ops.iter().filter(|op| matches!(op, Op::Remove { .. })).count()
    }

    pub fn lines(&self, limit: usize) -> Vec<String> {
        let mut out = Vec::new();

        for op in &self.ops {
            if out.len() >= limit {
                out.push(format!("and {} more", self.ops.len() - limit));
                break;
            }

            out.push(match op {
                Op::Add { parent, node } => {
                    let extra = node.descendants();
                    let tail = if extra > 0 {
                        format!(" (+{extra} inside)")
                    } else {
                        String::new()
                    };

                    format!("+ {} [{}]{}", crate::paths::child(parent, &node.name), node.class_name, tail)
                }
                Op::Update {
                    id,
                    properties,
                    attributes,
                    cleared_attributes,
                    tags,
                    class_name,
                    ..
                } => {
                    let mut fields: Vec<String> = properties.keys().cloned().collect();

                    if class_name.is_some() {
                        fields.push("class".into());
                    }

                    for key in attributes.keys() {
                        fields.push(format!("@{key}"));
                    }

                    for key in cleared_attributes {
                        fields.push(format!("-@{key}"));
                    }

                    if tags.is_some() {
                        fields.push("tags".into());
                    }

                    format!("~ {} ({})", id, fields.join(", "))
                }
                Op::Remove { id } => format!("- {id}"),
            });
        }

        out
    }

    pub fn summary(&self) -> String {
        format!("+{} ~{} -{}", self.added(), self.updated(), self.removed())
    }
}

pub fn diff(before: &Tree, after: &Tree) -> Patch {
    let mut patch = Patch::default();
    walk(&before.root, &after.root, &mut patch);
    patch
}

fn walk(before: &Node, after: &Node, patch: &mut Patch) {
    if after.ownership == Ownership::Reference {
        return;
    }

    compare(before, after, patch);

    for child in &after.children {
        if child.ownership == Ownership::Reference {
            continue;
        }

        match before.find_child(&child.name) {
            Some(existing) => walk(existing, child, patch),
            None => patch.ops.push(Op::Add {
                parent: after.id.clone(),
                node: strip(child),
            }),
        }
    }

    for child in &before.children {
        if child.ownership != Ownership::Managed {
            continue;
        }

        if after.find_child(&child.name).is_none() {
            patch.ops.push(Op::Remove { id: child.id.clone() });
        }
    }
}

fn compare(before: &Node, after: &Node, patch: &mut Patch) {
    let class_name = (before.class_name != after.class_name).then(|| after.class_name.clone());

    let mut properties = Map::new();

    for (key, value) in &after.properties {
        if before.properties.get(key) != Some(value) {
            properties.insert(key.clone(), value.clone());
        }
    }

    let mut attributes = Map::new();

    for (key, value) in &after.attributes {
        if before.attributes.get(key) != Some(value) {
            attributes.insert(key.clone(), value.clone());
        }
    }

    let cleared_attributes = before
        .attributes
        .keys()
        .filter(|key| !after.attributes.contains_key(*key))
        .cloned()
        .collect::<Vec<_>>();

    let tags = (before.tags != after.tags).then(|| after.tags.clone());

    if class_name.is_none()
        && properties.is_empty()
        && attributes.is_empty()
        && cleared_attributes.is_empty()
        && tags.is_none()
    {
        return;
    }

    patch.ops.push(Op::Update {
        id: after.id.clone(),
        name: None,
        class_name,
        properties,
        attributes,
        cleared_attributes,
        tags,
    });
}

fn strip(node: &Node) -> Node {
    let mut copy = node.clone();
    copy.children.retain(|child| child.ownership != Ownership::Reference);

    for child in &mut copy.children {
        *child = strip(child);
    }

    copy
}

pub fn syncable(tree: &Tree) -> Tree {
    Tree {
        root: strip(&tree.root),
    }
}
