use mlua::{Function, Lua, LuaSerdeExt, Result, Table, Value};

use crate::log;

use super::Setup;

pub const EVENTS: &[&str] = &[
    "read",
    "transfer",
    "added",
    "removed",
    "changed",
    "compile",
    "sync",
    "tree",
    "event",
    "gameEvent",
    "log",
    "gameStart",
    "gameEnd",
];

pub fn state(lua: &Lua) -> Result<Table> {
    lua.named_registry_value::<Table>("roflux.state")
}

pub fn listeners(lua: &Lua, event: &str) -> Result<Table> {
    state(lua)?.get::<Table>("events")?.get::<Table>(event)
}

pub fn transpilers(lua: &Lua) -> Result<Table> {
    state(lua)?.get::<Table>("transpilers")
}

pub fn pending(lua: &Lua) -> Result<Table> {
    state(lua)?.get::<Table>("pending")
}

fn describe(values: &[Value]) -> String {
    values
        .iter()
        .map(|value| match value {
            Value::String(text) => text.to_string_lossy().to_string(),
            Value::Integer(number) => number.to_string(),
            Value::Number(number) => number.to_string(),
            Value::Boolean(flag) => flag.to_string(),
            Value::Nil => "nil".into(),
            other => format!("{other:?}"),
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn node(lua: &Lua, name: String, declaration: Value) -> Result<Value> {
    let decoded: serde_json::Value = match declaration {
        Value::Nil => serde_json::json!({}),
        Value::String(class) => serde_json::json!({ "$ClassName": class.to_string_lossy().to_string() }),
        other => lua.from_value(other)?,
    };

    let parsed = crate::project::meta::parse(&decoded, "roflux.tree.node");
    let class_name = parsed.class_name.clone().unwrap_or_else(|| "Folder".into());
    let mut built = crate::ir::Node::new("", name, class_name);
    crate::project::scan::apply_declaration(&mut built, &parsed);

    let value = lua.to_value(&built)?;

    if let Value::Table(table) = &value {
        super::fill(lua, table)?;
    }

    Ok(value)
}

pub fn install(lua: &Lua, setup: &Setup) -> Result<()> {
    let state = lua.create_table()?;
    let events = lua.create_table()?;

    for event in EVENTS {
        events.set(*event, lua.create_table()?)?;
    }

    state.set("events", events)?;
    state.set("transpilers", lua.create_table()?)?;
    state.set("pending", lua.create_table()?)?;

    lua.set_named_registry_value("roflux.state", &state)?;

    let roflux = lua.create_table()?;

    roflux.set(
        "on",
        lua.create_function(|lua, (event, callback): (String, Function)| {
            let list = listeners(lua, &event)
                .map_err(|_| mlua::Error::runtime(format!("unknown event \"{event}\"")))?;

            list.push(callback)?;
            Ok(())
        })?,
    )?;

    for event in EVENTS {
        let name = format!("on{}{}", event[..1].to_uppercase(), &event[1..]);
        let key = event.to_string();

        roflux.set(
            name,
            lua.create_function(move |lua, callback: Function| {
                listeners(lua, &key)?.push(callback)?;
                Ok(())
            })?,
        )?;
    }

    roflux.set(
        "transpile",
        lua.create_function(|lua, (extension, callback): (String, Function)| {
            let extension = extension.trim_start_matches('.').to_ascii_lowercase();
            transpilers(lua)?.set(extension, callback)?;
            Ok(())
        })?,
    )?;

    roflux.set(
        "defer",
        lua.create_function(|lua, callback: Function| {
            let thread = lua.create_thread(callback)?;
            pending(lua)?.push(thread)?;
            Ok(())
        })?,
    )?;

    roflux.set(
        "log",
        lua.create_function(|_, values: mlua::MultiValue| {
            log::hook(describe(&values.into_vec()));
            Ok(())
        })?,
    )?;

    roflux.set(
        "warn",
        lua.create_function(|_, values: mlua::MultiValue| {
            log::warn(describe(&values.into_vec()));
            Ok(())
        })?,
    )?;

    roflux.set(
        "error",
        lua.create_function(|_, values: mlua::MultiValue| {
            log::fail(describe(&values.into_vec()));
            Ok(())
        })?,
    )?;

    let tree = lua.create_table()?;

    tree.set(
        "node",
        lua.create_function(|lua, (name, declaration): (String, Value)| node(lua, name, declaration))?,
    )?;

    roflux.set("tree", tree)?;

    super::files::install(lua, &roflux, setup.root.clone())?;
    super::data::install(lua, &roflux, setup.root.clone())?;
    super::system::install(lua, &roflux, setup)?;
    super::outbox::install(lua, &roflux)?;

    lua.globals().set("roflux", roflux)?;

    Ok(())
}
