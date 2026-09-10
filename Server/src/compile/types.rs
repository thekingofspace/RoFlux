use std::path::Path;

use anyhow::Result;
use serde_json::{json, Map, Value};

use crate::log;

pub const DEFINITIONS: &str = r#"export type RoFluxFile = {
	path: string,
	name: string,
	extension: string,
	source: string,
	text: string,
	className: string,
}

export type RoFluxDeclaration = { [string]: any }

export type RoFluxResult = string | RoFluxDeclaration | { RoFluxDeclaration } | nil

export type RoFluxListener = (file: RoFluxFile) -> RoFluxResult

declare roflux: {
	on: (event: string, callback: RoFluxListener) -> (),
	onRead: (callback: RoFluxListener) -> (),
	onTransfer: (callback: RoFluxListener) -> (),
	onAdded: (callback: RoFluxListener) -> (),
	onRemoved: (callback: RoFluxListener) -> (),
	onChanged: (callback: RoFluxListener) -> (),
	onCompile: (callback: RoFluxListener) -> (),
	onSync: (callback: RoFluxListener) -> (),
	transpile: (extension: string, callback: RoFluxListener) -> (),
	defer: (callback: () -> ()) -> (),
	log: (...any) -> (),
	warn: (...any) -> (),
}
"#;

pub fn write_definitions(root: &Path, name: &str) -> Result<()> {
    let file = root.join(name);
    let current = std::fs::read_to_string(&file).unwrap_or_default();

    if current == DEFINITIONS {
        return Ok(());
    }

    std::fs::write(&file, DEFINITIONS)?;
    log::info(format!("wrote {name}"));

    Ok(())
}

fn relaxed(raw: &str) -> String {
    let mut marked: Vec<(char, bool)> = Vec::with_capacity(raw.len());
    let mut chars = raw.chars().peekable();
    let mut inside = false;
    let mut escaped = false;

    while let Some(value) = chars.next() {
        if inside {
            marked.push((value, true));

            if escaped {
                escaped = false;
            } else if value == '\\' {
                escaped = true;
            } else if value == '"' {
                inside = false;
            }

            continue;
        }

        match value {
            '"' => {
                inside = true;
                marked.push((value, true));
            }
            '/' if matches!(chars.peek(), Some('/')) => {
                for next in chars.by_ref() {
                    if next == '\n' {
                        marked.push(('\n', false));
                        break;
                    }
                }
            }
            '/' if matches!(chars.peek(), Some('*')) => {
                chars.next();
                let mut previous = '\0';

                for next in chars.by_ref() {
                    if previous == '*' && next == '/' {
                        break;
                    }
                    previous = next;
                }
            }
            _ => marked.push((value, false)),
        }
    }

    let mut out = String::with_capacity(marked.len());

    for (index, (value, quoted)) in marked.iter().enumerate() {
        if !quoted && *value == ',' {
            let trailing = marked[index + 1..]
                .iter()
                .find(|(next, inner)| *inner || !next.is_whitespace())
                .map(|(next, inner)| !*inner && (*next == '}' || *next == ']'))
                .unwrap_or(false);

            if trailing {
                continue;
            }
        }

        out.push(*value);
    }

    out
}

pub fn write_settings(root: &Path, definitions: &str) -> Result<()> {
    let folder = root.join(".vscode");
    let file = folder.join("settings.json");

    std::fs::create_dir_all(&folder)?;

    let existing = std::fs::read_to_string(&file).ok();

    let mut settings: Map<String, Value> = match &existing {
        Some(raw) if !raw.trim().is_empty() => match serde_json::from_str(relaxed(raw).as_str()) {
            Ok(parsed) => parsed,
            Err(error) => {
                log::warn(format!(
                    ".vscode/settings.json could not be read ({error}), leaving it alone"
                ));
                return Ok(());
            }
        },
        _ => Map::new(),
    };

    let before = settings.clone();

    let mut files = settings
        .get("luau-lsp.types.definitionFiles")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();

    files.insert("RoFlux".into(), Value::String(definitions.into()));

    settings.insert("luau-lsp.types.definitionFiles".into(), Value::Object(files));
    settings.insert("luau-lsp.platform.type".into(), json!("roblox"));
    settings.insert("luau-lsp.sourcemap.enabled".into(), json!(true));
    settings.insert("luau-lsp.sourcemap.autogenerate".into(), json!(false));

    if settings == before {
        return Ok(());
    }

    let rendered = format!("{}\n", serde_json::to_string_pretty(&Value::Object(settings))?);
    std::fs::write(&file, rendered)?;
    log::info("wrote .vscode/settings.json");

    Ok(())
}

pub fn generate(root: &Path) -> Result<()> {
    let name = "types.d.luau";
    write_definitions(root, name)?;
    write_settings(root, name)?;
    Ok(())
}
