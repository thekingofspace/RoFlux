use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Query, State};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::{Json, Router};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::json;

use crate::log;

use super::protocol::{Inbound, Outbound};
use super::state::{Channel, Shared};

#[derive(Deserialize)]
pub struct Cursor {
    pub cursor: Option<usize>,
}

pub fn router(shared: Arc<Shared>) -> Router {
    Router::new()
        .route("/", get(info))
        .route("/api/info", get(info))
        .route("/api/snapshot", get(snapshot))
        .route("/api/poll", get(poll))
        .route("/api/relay", post(relay))
        .route("/api/game", get(game))
        .route("/roflux", get(upgrade))
        .with_state(shared)
}

pub async fn serve(shared: Arc<Shared>, port: u16) -> Result<()> {
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;

    log::good(format!("listening on http://127.0.0.1:{port}"));
    log::info("connect the RoFlux plugin from Roblox Studio");

    axum::serve(listener, router(shared)).await?;

    Ok(())
}

async fn info(State(shared): State<Arc<Shared>>) -> impl IntoResponse {
    let build = shared.build.lock().await;

    Json(json!({
        "server": env!("CARGO_PKG_VERSION"),
        "protocol": super::protocol::VERSION,
        "project": build.config.name,
        "id": build.config.id,
        "clients": shared.connected(),
    }))
}

async fn relay(State(shared): State<Arc<Shared>>, Json(batch): Json<super::relay::Batch>) -> impl IntoResponse {
    let hooks = shared.build.lock().await.hooks.clone();

    let delivered = tokio::task::spawn_blocking(move || super::relay::deliver(&hooks, batch)).await;

    Json(json!({ "ok": delivered.is_ok() }))
}

async fn snapshot(State(shared): State<Arc<Shared>>) -> impl IntoResponse {
    axum::response::Response::builder()
        .header("content-type", "application/json")
        .body(axum::body::Body::from(shared.snapshot().await.encode()))
        .unwrap()
}

async fn poll(State(shared): State<Arc<Shared>>, Query(query): Query<Cursor>) -> impl IntoResponse {
    wait(&shared.main, query.cursor.unwrap_or(0)).await
}

async fn game(State(shared): State<Arc<Shared>>, Query(query): Query<Cursor>) -> impl IntoResponse {
    match query.cursor {
        Some(cursor) => wait(&shared.game, cursor).await,
        None => delivery(shared.game.cursor().await, Vec::new()),
    }
}

async fn wait(channel: &Channel, cursor: usize) -> axum::response::Response {
    let mut receiver = channel.subscribe();
    let (next, pending) = channel.since(cursor).await;

    if !pending.is_empty() {
        return delivery(next, pending);
    }

    let waited = tokio::time::timeout(Duration::from_secs(25), receiver.recv()).await;

    if waited.is_err() {
        return delivery(next, Vec::new());
    }

    let (next, pending) = channel.since(cursor).await;
    delivery(next, pending)
}

fn delivery(next: usize, messages: Vec<Arc<String>>) -> axum::response::Response {
    let body = format!(
        "{{\"cursor\":{},\"messages\":[{}]}}",
        next,
        messages
            .iter()
            .map(|value| value.as_str())
            .collect::<Vec<_>>()
            .join(",")
    );

    axum::response::Response::builder()
        .header("content-type", "application/json")
        .body(axum::body::Body::from(body))
        .unwrap()
}

async fn upgrade(State(shared): State<Arc<Shared>>, socket: WebSocketUpgrade) -> impl IntoResponse {
    socket.on_upgrade(move |socket| session(shared, socket))
}

async fn session(shared: Arc<Shared>, socket: WebSocket) {
    let (mut writer, mut reader) = socket.split();
    let mut receiver = shared.main.subscribe();

    shared.clients.fetch_add(1, Ordering::Relaxed);
    log::sync(format!("studio connected ({} total)", shared.connected()));

    let opening = [shared.hello().await, shared.snapshot().await];

    for message in opening {
        if writer.send(Message::Text(message.encode().into())).await.is_err() {
            shared.clients.fetch_sub(1, Ordering::Relaxed);
            return;
        }
    }

    let pump = shared.clone();

    let mut outgoing = tokio::spawn(async move {
        loop {
            match receiver.recv().await {
                Ok(message) => {
                    if writer.send(Message::Text(message.as_str().into())).await.is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {
                    let refreshed = pump.snapshot().await;
                    if writer.send(Message::Text(refreshed.encode().into())).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    let listen = shared.clone();

    let mut incoming = tokio::spawn(async move {
        while let Some(Ok(message)) = reader.next().await {
            let Message::Text(text) = message else {
                continue;
            };

            let Ok(parsed) = serde_json::from_str::<Inbound>(&text) else {
                continue;
            };

            match parsed {
                Inbound::Ready { place } => {
                    let label = place.unwrap_or_else(|| "studio".into());
                    log::sync(format!("plugin ready in {label}"));
                }
                Inbound::Resync => {
                    log::sync("plugin asked for a full resync");
                    let refreshed = listen.snapshot().await;
                    listen.publish(refreshed).await;
                }
                Inbound::Ping => {
                    let cursor = listen.cursor().await;
                    listen.publish(Outbound::Pong { cursor }).await;
                }
                Inbound::Log { level, text } => {
                    match level.as_deref() {
                        Some("error") => log::fail(format!("studio: {text}")),
                        Some("warn") => log::warn(format!("studio: {text}")),
                        _ => log::sync(format!("studio: {text}")),
                    }
                }
            }
        }
    });

    tokio::select! {
        _ = &mut outgoing => incoming.abort(),
        _ = &mut incoming => outgoing.abort(),
    }

    shared.clients.fetch_sub(1, Ordering::Relaxed);
    log::sync(format!("studio disconnected ({} left)", shared.connected()));
}
