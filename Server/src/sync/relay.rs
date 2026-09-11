use serde::Deserialize;
use serde_json::Value;

use crate::hooks::Hooks;

const LIMIT: usize = 256;

#[derive(Deserialize)]
pub struct Batch {
    #[serde(default)]
    pub events: Vec<Relayed>,
}

#[derive(Deserialize)]
pub struct Relayed {
    pub kind: String,
    #[serde(default)]
    pub session: Option<String>,
    #[serde(default, rename = "gameSession")]
    pub game_session: Option<String>,
    #[serde(default)]
    pub context: Option<String>,
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub level: Option<String>,
    #[serde(default)]
    pub args: Option<Args>,
}

#[derive(Deserialize)]
pub struct Args {
    #[serde(default)]
    pub n: usize,
    #[serde(default)]
    pub items: Value,
}

fn text(value: &Option<String>) -> Value {
    value.clone().map(Value::String).unwrap_or(Value::Null)
}

fn item(items: &Value, index: usize) -> Value {
    match items {
        Value::Object(map) => map.get(&index.to_string()).cloned().unwrap_or(Value::Null),
        Value::Array(list) => list.get(index - 1).cloned().unwrap_or(Value::Null),
        _ => Value::Null,
    }
}

fn tuple(args: &Option<Args>) -> Vec<Value> {
    let Some(args) = args else {
        return Vec::new();
    };

    (1..=args.n.min(LIMIT)).map(|index| item(&args.items, index)).collect()
}

fn values(entry: &Relayed) -> Option<(&'static str, Vec<Value>)> {
    let session = text(&entry.session);
    let game = text(&entry.game_session);
    let context = text(&entry.context);

    let (event, mut values) = match entry.kind.as_str() {
        "event" => ("event", vec![session]),
        "gameEvent" => ("gameEvent", vec![session, game, context]),
        "log" => (
            "log",
            vec![session, game, context, text(&entry.message), text(&entry.level)],
        ),
        "gameStart" => ("gameStart", vec![session, game]),
        "gameEnd" => ("gameEnd", vec![session, game]),
        "connect" => ("connect", vec![session]),
        _ => return None,
    };

    if matches!(event, "event" | "gameEvent") {
        values.extend(tuple(&entry.args));
    }

    Some((event, values))
}

pub fn deliver(hooks: &Hooks, batch: Batch) {
    for entry in &batch.events {
        if let Some((event, values)) = values(entry) {
            hooks.relay(event, &values);
        }
    }
}
