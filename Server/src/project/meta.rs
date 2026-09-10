use serde_json::{Map, Value};

use crate::log;

#[derive(Clone, Debug, Default)]
pub struct Meta {
    pub class_name: Option<String>,
    pub parent: Option<String>,
    pub path: Option<String>,
    pub from_model: Option<String>,
    pub name: Option<String>,
    pub ignore: bool,
    pub properties: Map<String, Value>,
    pub attributes: Map<String, Value>,
    pub tags: Vec<String>,
    pub children: Vec<(String, Meta)>,
}

const DIRECTIVES: &[&str] = &[
    "$ClassName",
    "$Parent",
    "$Path",
    "$FromModel",
    "$Name",
    "$Ignore",
    "$Properties",
    "$Attributes",
    "$Tags",
    "$Children",
    "$ProjectID",
    "$Default",
];

fn text(value: &Value) -> Option<String> {
    value.as_str().map(str::to_string)
}

fn typed(value: &Value) -> bool {
    value
        .as_object()
        .map(|object| object.contains_key("$Type"))
        .unwrap_or(false)
}

fn is_declaration(value: &Value) -> bool {
    value
        .as_object()
        .map(|object| {
            !object.contains_key("$Type")
                && (object.contains_key("$ClassName")
                || object.contains_key("$Path")
                || object.contains_key("$FromModel")
                || object.contains_key("$Properties")
                || object.contains_key("$Children")
                || object.values().any(is_declaration))
        })
        .unwrap_or(false)
}

pub fn parse(value: &Value, origin: &str) -> Meta {
    let mut meta = Meta::default();

    let Some(object) = value.as_object() else {
        log::warn(format!("{origin}: expected an object"));
        return meta;
    };

    for (key, entry) in object {
        match key.as_str() {
            "$ClassName" => meta.class_name = text(entry),
            "$Parent" => meta.parent = text(entry),
            "$Path" => meta.path = text(entry),
            "$FromModel" => meta.from_model = text(entry),
            "$Name" => meta.name = text(entry),
            "$Ignore" => meta.ignore = entry.as_bool().unwrap_or(false),
            "$ProjectID" | "$Default" => {}
            "$Properties" => {
                if let Some(fields) = entry.as_object() {
                    for (field, field_value) in fields {
                        meta.properties.insert(field.clone(), field_value.clone());
                    }
                }
            }
            "$Attributes" => {
                if let Some(fields) = entry.as_object() {
                    for (field, field_value) in fields {
                        meta.attributes.insert(field.clone(), field_value.clone());
                    }
                }
            }
            "$Tags" => {
                if let Some(items) = entry.as_array() {
                    meta.tags.extend(items.iter().filter_map(text));
                }
            }
            "$Children" => {
                if let Some(fields) = entry.as_object() {
                    for (child, child_value) in fields {
                        meta.children.push((child.clone(), parse(child_value, origin)));
                    }
                }
            }
            other if other.starts_with('$') => {
                if is_declaration(entry) {
                    let child = other.trim_start_matches('$').to_string();
                    log::warn(format!(
                        "{origin}: \"{other}\" is not a directive, reading it as the child \"{child}\""
                    ));
                    meta.children.push((child, parse(entry, origin)));
                } else if DIRECTIVES.contains(&other) {
                    log::warn(format!("{origin}: \"{other}\" has an unexpected value"));
                } else {
                    log::warn(format!("{origin}: unknown directive \"{other}\""));
                }
            }
            other => {
                if entry.is_object() && !typed(entry) {
                    meta.children.push((other.to_string(), parse(entry, origin)));
                } else {
                    meta.properties.insert(other.to_string(), entry.clone());
                }
            }
        }
    }

    meta
}

pub fn parse_many(value: &Value, origin: &str) -> Vec<Meta> {
    match value {
        Value::Array(items) => items.iter().map(|item| parse(item, origin)).collect(),
        _ => vec![parse(value, origin)],
    }
}

pub fn read(path: &std::path::Path) -> anyhow::Result<Value> {
    let raw = std::fs::read_to_string(path)?;
    let trimmed = raw.trim_start_matches('\u{feff}');

    if trimmed.trim().is_empty() {
        return Ok(Value::Object(Map::new()));
    }

    Ok(serde_json::from_str(trimmed)?)
}
