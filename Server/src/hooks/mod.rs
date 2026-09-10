pub mod api;
pub mod files;

use std::collections::HashSet;
use std::path::Path;
use std::sync::Mutex;

use anyhow::{anyhow, Result};
use mlua::{Function, Lua, LuaSerdeExt, MultiValue, Table, Thread, ThreadStatus, Value as LuaValue};
use serde_json::Value;

use crate::ir::Node;
use crate::log;
use crate::project::{meta, Loaded, Transform};

pub struct Hooks {
    lua: Mutex<Lua>,
    extensions: HashSet<String>,
    scripts: usize,
}

impl Hooks {
    pub fn count(&self) -> usize {
        self.scripts
    }

    pub fn load(root: &Path) -> Result<Self> {
        let lua = Lua::new();
        api::install(&lua, root.to_path_buf())?;

        let folder = root.join("scripts");
        let mut scripts = 0;

        if folder.is_dir() {
            let mut files = Vec::new();

            for entry in walkdir::WalkDir::new(&folder).sort_by_file_name() {
                let entry = entry?;

                if !entry.file_type().is_file() {
                    continue;
                }

                let name = entry.file_name().to_string_lossy().to_string();

                if !crate::project::classify::is_luau(&name) || crate::project::classify::definition(&name) {
                    continue;
                }

                files.push(entry.path().to_path_buf());
            }

            for file in files {
                let relative = file
                    .strip_prefix(root)
                    .unwrap_or(&file)
                    .to_string_lossy()
                    .replace('\\', "/");

                let body = std::fs::read_to_string(&file)?;

                run(&lua, &body, &relative).map_err(|error| anyhow!("{relative}: {error}"))?;
                scripts += 1;
            }
        }

        let mut extensions = HashSet::new();

        for pair in api::transpilers(&lua)?.pairs::<String, Function>() {
            let (extension, _) = pair?;
            extensions.insert(extension);
        }

        Ok(Hooks {
            lua: Mutex::new(lua),
            extensions,
            scripts,
        })
    }

    pub fn notify(&self, event: &str, relative: &str) {
        let Ok(lua) = self.lua.lock() else {
            return;
        };

        let context = match context(&lua, relative) {
            Ok(context) => context,
            Err(error) => {
                log::warn(format!("hook context failed: {error}"));
                return;
            }
        };

        if let Err(error) = broadcast(&lua, event, context) {
            log::warn(format!("{event} hook failed: {error}"));
        }
    }

    pub fn drain(&self) {
        let Ok(lua) = self.lua.lock() else {
            return;
        };

        let Ok(pending) = api::pending(&lua) else {
            return;
        };

        let Ok(length) = pending.raw_len().try_into() else {
            return;
        };

        let mut resumed: Vec<Thread> = Vec::new();

        for index in 1..=length {
            if let Ok(thread) = pending.raw_get::<Thread>(index) {
                resumed.push(thread);
            }
        }

        pending.clear().ok();

        for thread in resumed {
            if thread.status() != ThreadStatus::Resumable {
                continue;
            }

            if let Err(error) = thread.resume::<MultiValue>(()) {
                log::warn(format!("deferred hook failed: {error}"));
                continue;
            }

            if thread.status() == ThreadStatus::Resumable {
                pending.push(thread).ok();
            }
        }
    }
}

fn run(lua: &Lua, body: &str, name: &str) -> Result<()> {
    let chunk = lua.load(body).set_name(name).into_function()?;
    let thread = lua.create_thread(chunk)?;

    thread.resume::<MultiValue>(())?;

    if thread.status() == ThreadStatus::Resumable {
        return Err(anyhow!("scripts must not yield while loading"));
    }

    Ok(())
}

fn context(lua: &Lua, relative: &str) -> mlua::Result<Table> {
    let context = lua.create_table()?;
    context.set("path", relative)?;
    context.set("name", relative.rsplit('/').next().unwrap_or(relative))?;
    context.set(
        "extension",
        relative.rsplit_once('.').map(|(_, tail)| tail.to_ascii_lowercase()).unwrap_or_default(),
    )?;
    Ok(context)
}

fn invoke(lua: &Lua, callback: &Function, context: &Table) -> Result<Option<LuaValue>> {
    let thread = lua.create_thread(callback.clone())?;
    let produced = thread.resume::<MultiValue>(context.clone())?;

    if thread.status() == ThreadStatus::Resumable {
        api::pending(lua)?.push(thread)?;
        log::warn("a hook yielded, its result was skipped for this pass");
        return Ok(None);
    }

    Ok(produced.into_vec().into_iter().next())
}

fn broadcast(lua: &Lua, event: &str, context: Table) -> Result<()> {
    let listeners = api::listeners(lua, event)?;

    for pair in listeners.clone().pairs::<i64, Function>() {
        let (_, callback) = pair?;
        invoke(lua, &callback, &context)?;
    }

    Ok(())
}

fn chain(lua: &Lua, event: &str, context: &Table) -> Result<()> {
    let listeners = api::listeners(lua, event)?;

    for pair in listeners.clone().pairs::<i64, Function>() {
        let (_, callback) = pair?;

        let produced = invoke(lua, &callback, context)?;

        match produced {
            Some(LuaValue::String(text)) => {
                context.set("source", text.to_string_lossy())?;
            }
            Some(LuaValue::Table(table)) => {
                if let Ok(source) = table.get::<String>("source") {
                    context.set("source", source)?;
                }
            }
            _ => {}
        }
    }

    Ok(())
}

fn single(decoded: &Value) -> Loaded {
    let parsed = meta::parse(decoded, "transpiler");

    if parsed.ignore {
        return Loaded {
            skip: true,
            ..Loaded::default()
        };
    }

    let mut children = Vec::new();

    for (name, child) in &parsed.children {
        let class_name = child.class_name.clone().unwrap_or_else(|| "Folder".into());
        let mut node = Node::new("", name, class_name);
        crate::project::scan::apply_declaration(&mut node, child);
        children.push(node);
    }

    Loaded {
        class_name: parsed.class_name.clone(),
        name: parsed.name.clone(),
        parent: parsed.parent.clone(),
        properties: parsed.properties.clone(),
        attributes: parsed.attributes.clone(),
        tags: parsed.tags.clone(),
        children,
        skip: false,
    }
}

fn declaration(lua: &Lua, value: LuaValue) -> Result<Option<Vec<Loaded>>> {
    if let LuaValue::String(text) = &value {
        let mut loaded = Loaded {
            class_name: Some("ModuleScript".into()),
            ..Loaded::default()
        };

        loaded
            .properties
            .insert("Source".into(), Value::String(text.to_string_lossy().to_string()));

        return Ok(Some(vec![loaded]));
    }

    let LuaValue::Table(_) = &value else {
        return Ok(None);
    };

    let decoded: Value = lua.from_value(value)?;

    match &decoded {
        Value::Array(items) => {
            let mut built = Vec::new();

            for item in items {
                built.push(single(item));
            }

            Ok(Some(built))
        }
        _ => Ok(Some(vec![single(&decoded)])),
    }
}

impl Transform for Hooks {
    fn claims(&self, extension: &str) -> bool {
        self.extensions.contains(extension)
    }

    fn source(&self, relative: &str, class_name: &str, source: String) -> Result<String> {
        let lua = self.lua.lock().map_err(|_| anyhow!("hook runtime is poisoned"))?;

        let listeners = api::listeners(&lua, "read")?.raw_len() + api::listeners(&lua, "transfer")?.raw_len();

        if listeners == 0 {
            return Ok(source);
        }

        let context = context(&lua, relative)?;
        context.set("className", class_name)?;
        context.set("source", source.clone())?;

        chain(&lua, "read", &context)?;
        chain(&lua, "transfer", &context)?;

        Ok(context.get::<String>("source").unwrap_or(source))
    }

    fn file(&self, relative: &str, extension: &str, raw: &str) -> Result<Option<Vec<Loaded>>> {
        let lua = self.lua.lock().map_err(|_| anyhow!("hook runtime is poisoned"))?;

        let Ok(callback) = api::transpilers(&lua)?.get::<Function>(extension) else {
            return Ok(None);
        };

        let context = context(&lua, relative)?;
        context.set("source", raw)?;
        context.set("text", raw)?;

        let Some(produced) = invoke(&lua, &callback, &context)? else {
            return Ok(None);
        };

        declaration(&lua, produced)
    }
}
