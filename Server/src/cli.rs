use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

use crate::compile::{place, types, Build};
use crate::log;
use crate::plugin;
use crate::sync::{server, state::Shared, watch};

#[derive(Parser)]
#[command(name = "roflux", version, about = "One way syncing from your editor into Roblox Studio")]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    Serve {
        #[arg(default_value = "default")]
        project: String,
        #[arg(short, long, default_value_t = 34872)]
        port: u16,
        #[arg(short, long)]
        quiet: bool,
    },
    Compile {
        #[arg(default_value = "default")]
        project: String,
        #[arg(short, long)]
        quiet: bool,
    },
    Init {
        #[arg(default_value = ".")]
        project: PathBuf,
    },
    Build {
        #[arg(default_value = "default")]
        project: String,
        #[arg(short, long)]
        output: PathBuf,
        #[arg(short, long)]
        quiet: bool,
    },
    Plugin {
        #[arg(short, long)]
        output: Option<PathBuf>,
        #[arg(short, long)]
        to: Option<PathBuf>,
    },
}

pub async fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Command::Serve { project, port, quiet } => serve(project, port, quiet).await,
        Command::Compile { project, quiet } => compile(project, quiet),
        Command::Init { project } => init(project),
        Command::Build { project, output, quiet } => build(project, output, quiet),
        Command::Plugin { output, to } => install(output, to),
    }
}

fn resolve(project: PathBuf) -> Result<PathBuf> {
    Ok(std::fs::canonicalize(&project)?)
}

const SUFFIX: &str = ".project.json";

fn locate(target: &str) -> Result<(PathBuf, String)> {
    let raw = std::path::Path::new(target);

    let candidate = if target.ends_with(SUFFIX) {
        raw.to_path_buf()
    } else if raw.is_dir() {
        raw.join("default.project.json")
    } else {
        std::path::PathBuf::from(format!("{target}{SUFFIX}"))
    };

    let folder = candidate
        .parent()
        .filter(|value| !value.as_os_str().is_empty())
        .unwrap_or(std::path::Path::new("."));

    let manifest = candidate
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| "default.project.json".into());

    if !folder.is_dir() {
        return Err(anyhow::anyhow!("there is no folder \"{}\"", folder.display()));
    }

    if !candidate.exists() {
        return Err(anyhow::anyhow!(
            "there is no {}, run \"roflux init\" to make one",
            candidate.display()
        ));
    }

    Ok((resolve(folder.to_path_buf())?, manifest))
}

fn compile(project: String, quiet: bool) -> Result<()> {
    log::set_quiet(quiet);

    let (root, manifest) = locate(&project)?;
    let build = Build::open(&root, &manifest)?;

    log::good(format!("compiled {}", build.stats()));
    log::info("wrote sourcemap.json");

    Ok(())
}

fn init(project: PathBuf) -> Result<()> {
    let root = resolve(project)?;

    std::fs::create_dir_all(root.join("scripts"))?;
    types::generate(&root)?;

    let manifest = root.join("default.project.json");

    if !manifest.exists() {
        let name = root
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_else(|| "Project".into());

        let body = format!(
            "{{\n    \"ProjectID\": \"{name}\",\n    \"Default\": \"ReplicatedStorage\"\n}}\n"
        );

        std::fs::write(&manifest, body)?;
        log::info("wrote default.project.json");
    }

    log::good("project ready");

    Ok(())
}

fn build(project: String, output: PathBuf, quiet: bool) -> Result<()> {
    log::set_quiet(quiet);

    let (root, manifest) = locate(&project)?;
    let built = Build::open(&root, &manifest)?;

    if let Some(parent) = output.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent)?;
        }
    }

    place::write(&built.tree, &output)?;

    log::good(format!("wrote {} ({})", output.display(), built.stats()));

    Ok(())
}

fn install(output: Option<PathBuf>, to: Option<PathBuf>) -> Result<()> {
    if let Some(output) = output {
        plugin::write(&output)?;
        log::good(format!("wrote {}", output.display()));
        return Ok(());
    }

    let written = plugin::install(to)?;

    log::good(format!("installed {}", written.display()));
    log::info("restart Roblox Studio to pick it up");

    Ok(())
}

async fn serve(project: String, port: u16, quiet: bool) -> Result<()> {
    log::set_quiet(quiet);

    let (root, manifest) = locate(&project)?;
    let build = Build::open(&root, &manifest)?;

    log::good(format!("{} loaded, {}", build.config.name, build.stats()));

    let shared = Shared::new(build);

    let (sender, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    crate::hooks::outbox::connect(sender);

    let forwarder = tokio::spawn({
        let shared = shared.clone();

        async move {
            while let Some(outgoing) = receiver.recv().await {
                shared.send(outgoing).await;
            }
        }
    });

    let watcher = tokio::spawn({
        let shared = shared.clone();
        let root = root.clone();

        async move {
            if let Err(error) = watch::run(shared, root).await {
                log::fail(format!("watcher stopped: {error}"));
            }
        }
    });

    tokio::select! {
        result = server::serve(shared.clone(), port) => result?,
        _ = tokio::signal::ctrl_c() => log::info("shutting down"),
    }

    watcher.abort();
    forwarder.abort();

    Ok(())
}
