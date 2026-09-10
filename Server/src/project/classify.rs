#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    Ignored,
    InitMeta,
    InitScript(Script),
    Script(Script),
    Instance,
    Sidecar(String),
    Asset(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Script {
    Module,
    Server,
    Client,
}

impl Script {
    pub fn class_name(self) -> &'static str {
        match self {
            Script::Module => "ModuleScript",
            Script::Server => "Script",
            Script::Client => "LocalScript",
        }
    }
}

fn strip(name: &str, suffix: &str) -> Option<String> {
    name.strip_suffix(suffix).map(str::to_string)
}

pub fn is_luau(name: &str) -> bool {
    name.ends_with(".luau") || name.ends_with(".lua")
}

pub fn definition(name: &str) -> bool {
    name.ends_with(".d.luau") || name.ends_with(".d.lua")
}

pub fn extension(name: &str) -> String {
    name.rsplit_once('.').map(|(_, tail)| tail.to_ascii_lowercase()).unwrap_or_default()
}

pub fn classify(name: &str) -> (Kind, String) {
    let lower = name.to_ascii_lowercase();

    if definition(&lower) || lower.starts_with('.') {
        return (Kind::Ignored, String::new());
    }

    if lower == "init.meta.json" {
        return (Kind::InitMeta, String::new());
    }

    if lower == "default.project.json" {
        return (Kind::Ignored, String::new());
    }

    for (suffix, script) in [
        (".server.luau", Script::Server),
        (".server.lua", Script::Server),
        (".client.luau", Script::Client),
        (".client.lua", Script::Client),
    ] {
        if let Some(stem) = strip(&lower, suffix) {
            let stem = &name[..stem.len()];
            if stem.eq_ignore_ascii_case("init") {
                return (Kind::InitScript(script), String::new());
            }
            return (Kind::Script(script), stem.to_string());
        }
    }

    for suffix in [".luau", ".lua"] {
        if let Some(stem) = strip(&lower, suffix) {
            let stem = &name[..stem.len()];
            if stem.eq_ignore_ascii_case("init") {
                return (Kind::InitScript(Script::Module), String::new());
            }
            return (Kind::Script(Script::Module), stem.to_string());
        }
    }

    if let Some(stem) = strip(&lower, ".inst.json") {
        return (Kind::Instance, name[..stem.len()].to_string());
    }

    if let Some(stem) = strip(&lower, ".meta.json") {
        return (Kind::Sidecar(name[..stem.len()].to_string()), name[..stem.len()].to_string());
    }

    let stem = name.rsplit_once('.').map(|(head, _)| head).unwrap_or(name);
    (Kind::Asset(extension(&lower)), stem.to_string())
}

pub fn asset_class(extension: &str) -> Option<&'static str> {
    match extension {
        "txt" | "md" | "csv" | "html" | "css" | "toml" | "yml" | "yaml" => Some("StringValue"),
        "json" => Some("ModuleScript"),
        _ => None,
    }
}
