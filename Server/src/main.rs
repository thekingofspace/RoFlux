mod cli;
mod compile;
mod hooks;
mod ir;
mod literal;
mod log;
mod patch;
mod plugin;
mod paths;
mod project;
mod sync;

#[tokio::main]
async fn main() {
    if let Err(error) = cli::run().await {
        log::fail(format!("{error:#}"));
        std::process::exit(1);
    }
}
