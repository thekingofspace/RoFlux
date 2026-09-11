use std::sync::{Mutex, OnceLock};

use mlua::{Lua, MultiValue, Result, Table, Value};
use serde_json::{json, Map, Number, Value as Json};
use tokio::sync::mpsc::UnboundedSender;

const DEPTH: usize = 16;

#[derive(Clone, Copy, Debug)]
pub enum Target {
    Studio,
    Game,
}

pub struct Outgoing {
    pub target: Target,
    pub args: Json,
}

static OUTBOX: OnceLock<Mutex<Option<UnboundedSender<Outgoing>>>> = OnceLock::new();

fn slot() -> &'static Mutex<Option<UnboundedSender<Outgoing>>> {
    OUTBOX.get_or_init(|| Mutex::new(None))
}

pub fn connect(sender: UnboundedSender<Outgoing>) {
    if let Ok(mut held) = slot().lock() {
        *held = Some(sender);
    }
}

fn number(value: f64) -> Json {
    if value.is_nan() {
        return Json::String("nan".into());
    }

    if value.is_infinite() {
        return Json::String(if value > 0.0 { "inf" } else { "-inf" }.into());
    }

    Number::from_f64(value).map(Json::Number).unwrap_or(Json::Null)
}

fn key(value: &Value) -> String {
    match value {
        Value::String(text) => text.to_string_lossy().to_string(),
        Value::Integer(number) => number.to_string(),
        Value::Number(number) => number.to_string(),
        Value::Boolean(flag) => flag.to_string(),
        other => format!("<{}>", other.type_name()),
    }
}

pub fn to_json(value: &Value, depth: usize) -> Json {
    match value {
        Value::Nil => Json::Null,
        Value::Boolean(flag) => Json::Bool(*flag),
        Value::Integer(integer) => Json::from(*integer),
        Value::Number(float) => number(*float),
        Value::String(text) => Json::String(text.to_string_lossy().to_string()),
        Value::Table(table) => {
            if depth >= DEPTH {
                return Json::String("<too deep>".into());
            }

            let length = table.raw_len();
            let count = table.clone().pairs::<Value, Value>().filter(Result::is_ok).count();

            if length > 0 && count == length {
                let items = (1..=length)
                    .map(|index| to_json(&table.raw_get::<Value>(index).unwrap_or(Value::Nil), depth + 1))
                    .collect();

                return Json::Array(items);
            }

            let mut map = Map::new();

            for pair in table.clone().pairs::<Value, Value>() {
                let Ok((field, entry)) = pair else {
                    continue;
                };

                map.insert(key(&field), to_json(&entry, depth + 1));
            }

            Json::Object(map)
        }
        other => Json::String(format!("<{}>", other.type_name())),
    }
}

fn tuple(values: MultiValue) -> Json {
    let list = values.into_vec();
    let mut items = Map::new();

    for (index, value) in list.iter().enumerate() {
        if !value.is_nil() {
            items.insert((index + 1).to_string(), to_json(value, 0));
        }
    }

    json!({ "n": list.len(), "items": items })
}

fn send(target: Target, values: MultiValue) -> bool {
    let Ok(held) = slot().lock() else {
        return false;
    };

    match held.as_ref() {
        Some(sender) => sender
            .send(Outgoing {
                target,
                args: tuple(values),
            })
            .is_ok(),
        None => false,
    }
}

pub fn install(lua: &Lua, roflux: &Table) -> Result<()> {
    roflux.set(
        "fireStudio",
        lua.create_function(|_, values: MultiValue| Ok(send(Target::Studio, values)))?,
    )?;

    roflux.set(
        "fireInGame",
        lua.create_function(|_, values: MultiValue| Ok(send(Target::Game, values)))?,
    )?;

    Ok(())
}
