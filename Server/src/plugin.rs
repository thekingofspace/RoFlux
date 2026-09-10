use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use include_dir::{include_dir, Dir};

use crate::compile::place;
use crate::log;
use crate::project::{scan, Passthrough};

static SOURCE: Dir<'_> = include_dir!("$CARGO_MANIFEST_DIR/../Plugin");

pub const NAME: &str = "RoFlux";
pub const FILE: &str = "RoFlux.rbxm";

pub fn studio_folder() -> Result<PathBuf> {
    if cfg!(target_os = "windows") {
        let base = std::env::var("LOCALAPPDATA").map_err(|_| anyhow!("LOCALAPPDATA is not set"))?;
        return Ok(PathBuf::from(base).join("Roblox").join("Plugins"));
    }

    let home = std::env::var("HOME").map_err(|_| anyhow!("HOME is not set"))?;

    if cfg!(target_os = "macos") {
        return Ok(PathBuf::from(home).join("Documents").join("Roblox").join("Plugins"));
    }

    Ok(PathBuf::from(home).join(".local").join("share").join("Roblox").join("Plugins"))
}

pub fn unpack(into: &Path) -> Result<()> {
    if into.exists() {
        std::fs::remove_dir_all(into)?;
    }

    std::fs::create_dir_all(into)?;
    SOURCE.extract(into)?;

    Ok(())
}

pub fn write(output: &Path) -> Result<()> {
    let staging = std::env::temp_dir().join("roflux-plugin-source");

    unpack(&staging)?;

    let node = scan::build_folder(&staging, &Passthrough, NAME)?;

    if let Some(parent) = output.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }

    place::write_model(&node, output)?;

    let _ = std::fs::remove_dir_all(&staging);

    Ok(())
}

pub fn install(target: Option<PathBuf>) -> Result<PathBuf> {
    let folder = match target {
        Some(folder) => folder,
        None => studio_folder()?,
    };

    std::fs::create_dir_all(&folder)?;

    let output = folder.join(FILE);
    let replacing = output.exists();

    write(&output)?;

    if replacing {
        log::info("replaced the installed copy");
    }

    Ok(output)
}
