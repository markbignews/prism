use crate::chat_agent::{ChatAgent, StreamEvent};
use crate::models::*;
use crate::settings::Settings;
use log;
use std::path::Path;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, State};

pub struct AppState {
    pub agent: ChatAgent,
}

/// Start a native window drag from a renderer mousedown. CSS drag regions are
/// not consistently honored by macOS Overlay titlebars, so use the Tauri
/// window API as the authoritative path.
#[tauri::command]
pub fn start_window_dragging(window: tauri::Window) -> Result<(), String> {
    window.start_dragging().map_err(|error| error.to_string())
}

/// Return a stable platform identifier without relying on an optional
/// JavaScript OS plugin. `withGlobalTauri` exposes the core and event APIs, but
/// does not guarantee that `__TAURI__.os` exists in every Tauri 2 build.
#[tauri::command]
pub fn get_platform() -> &'static str {
    if cfg!(target_os = "macos") {
        "darwin"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else {
        "other"
    }
}

#[tauri::command]
pub async fn create_conversation(
    state: State<'_, Arc<AppState>>,
    mode: Option<String>,
) -> Result<String, String> {
    let lang = state.agent.language.read().await.clone();
    let id = state
        .agent
        .create_conversation(&lang, mode.as_deref().unwrap_or("balanced"))
        .await;
    Ok(id.to_string())
}

#[tauri::command]
pub async fn delete_conversation(
    state: State<'_, Arc<AppState>>,
    id: String,
) -> Result<(), String> {
    let uid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    state.agent.delete_conversation(uid).await;
    Ok(())
}

#[tauri::command]
pub async fn delete_message_pair(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    msg_id: String,
) -> Result<(), String> {
    let cid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    let mid = uuid::Uuid::parse_str(&msg_id).map_err(|e| e.to_string())?;
    state.agent.delete_message_pair(cid, mid).await;
    Ok(())
}

/// Remove a user message and everything after it before an edit or retry.
/// Keeping this server-side makes the model context match the rendered UI.
#[tauri::command]
pub async fn truncate_conversation(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    msg_id: String,
) -> Result<(), String> {
    let cid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    let mid = uuid::Uuid::parse_str(&msg_id).map_err(|e| e.to_string())?;
    state.agent.truncate_conversation(cid, mid).await
}

#[tauri::command]
pub async fn list_conversations(
    state: State<'_, Arc<AppState>>,
) -> Result<Vec<Conversation>, String> {
    Ok(state.agent.list_conversations().await)
}

#[tauri::command]
pub async fn get_conversation(
    state: State<'_, Arc<AppState>>,
    id: String,
) -> Result<Option<Conversation>, String> {
    let uid = uuid::Uuid::parse_str(&id).map_err(|e| e.to_string())?;
    Ok(state.agent.get_conversation(uid).await)
}

#[tauri::command]
pub async fn get_context_usage(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
) -> Result<Option<ContextUsageSnapshot>, String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|error| error.to_string())?;
    Ok(state.agent.context_usage(uid).await)
}

#[tauri::command]
pub async fn set_mode(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    mode: String,
) -> Result<(), String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    let m = ConversationMode::from_str(&mode);
    state.agent.set_mode(uid, m).await;
    Ok(())
}

#[tauri::command]
pub async fn set_title(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    title: String,
) -> Result<(), String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    let mut convs = state.agent.conversations.write().await;
    if let Some(conv) = convs.iter_mut().find(|c| c.id == uid) {
        conv.title = title;
        conv.updated_at = chrono::Utc::now();
    }
    drop(convs);
    state.agent.persist_conversations().await;
    Ok(())
}

#[tauri::command]
pub async fn send_message(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    text: String,
) -> Result<(), String> {
    log::info!(
        "send_message requested — conv_id={} text_len={}",
        conv_id,
        text.chars().count()
    );
    // ── Pre-flight: check API key ──────────────────────────
    if state.agent.client.api_key().await.is_empty() {
        log::error!("send_message rejected — API key is empty");
        return Err(
            "No API key configured. Please set your DeepSeek API key in Settings.".to_string(),
        );
    }

    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;

    let callback = {
        let app_clone = app.clone();
        Arc::new(move |event: StreamEvent| match event {
            StreamEvent::Reasoning(content) => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "reasoning", "content": content
                    }),
                );
            }
            StreamEvent::Text(content) => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "text", "content": content
                    }),
                );
            }
            StreamEvent::ToolCall(name, args, id) => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "tool-call", "name": name, "args": args, "id": id
                    }),
                );
            }
            StreamEvent::ToolResult(name, result) => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "tool-result", "name": name, "result": result
                    }),
                );
            }
            StreamEvent::Error(error) => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "error", "error": error
                    }),
                );
            }
            StreamEvent::Done {
                conv_id: cid,
                title,
            } => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "done", "convId": cid.to_string(), "title": title
                    }),
                );
            }
            StreamEvent::Processing(proc) => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "processing", "processing": proc
                    }),
                );
            }
            StreamEvent::Summarizing { conv_id } => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "summarizing", "convId": conv_id.to_string()
                    }),
                );
            }
            StreamEvent::ChaptersUpdated { conv_id } => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "chapters-updated", "convId": conv_id.to_string()
                    }),
                );
            }
            StreamEvent::SummarizeFailed { conv_id, error } => {
                let _ = app_clone.emit(
                    "msg:event",
                    serde_json::json!({
                        "type": "summarize-failed", "convId": conv_id.to_string(), "error": error
                    }),
                );
            }
        })
    };

    let result = state.agent.send_message(uid, &text, callback).await;
    match &result {
        Ok(()) => log::info!("send_message completed — conv_id={}", uid),
        Err(error) => log::error!("send_message failed — conv_id={} error={}", uid, error),
    }
    result
}

#[tauri::command]
pub async fn cancel_message(state: State<'_, Arc<AppState>>) -> Result<(), String> {
    state.agent.cancel().await;
    Ok(())
}

#[tauri::command]
pub async fn summarize_deselect(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
) -> Result<(), String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    let lang = state.agent.language.read().await.clone();
    state.agent.summarize_conversation(uid, &lang).await
}

#[tauri::command]
pub async fn re_summarize(state: State<'_, Arc<AppState>>, conv_id: String) -> Result<(), String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    let lang = state.agent.language.read().await.clone();
    state.agent.full_re_summarize(uid, &lang).await
}

// ─── Archives ───

#[tauri::command]
pub async fn query_emotions(state: State<'_, Arc<AppState>>) -> Result<Vec<EmotionEntry>, String> {
    let conversation_id = *state.agent.selected_conversation_id.read().await;
    let archives = state.agent.archives.lock().await;
    Ok(conversation_id
        .map(|id| archives.get_recent_emotions_for_conversation(id, 50))
        .unwrap_or_default())
}

#[tauri::command]
pub async fn query_persons(state: State<'_, Arc<AppState>>) -> Result<Vec<PersonRecord>, String> {
    let conversation_id = *state.agent.selected_conversation_id.read().await;
    let archives = state.agent.archives.lock().await;
    Ok(conversation_id
        .map(|id| {
            archives
                .all_persons()
                .into_iter()
                .filter(|person| {
                    person
                        .conversation_ids
                        .as_ref()
                        .map(|ids| ids.contains(&id))
                        .unwrap_or(false)
                })
                .collect()
        })
        .unwrap_or_default())
}

#[tauri::command]
pub async fn query_person(
    state: State<'_, Arc<AppState>>,
    name: String,
) -> Result<Option<PersonRecord>, String> {
    let conversation_id = *state.agent.selected_conversation_id.read().await;
    let archives = state.agent.archives.lock().await;
    Ok(conversation_id.and_then(|id| archives.find_person(&name, id)))
}

#[tauri::command]
pub async fn query_memory(
    state: State<'_, Arc<AppState>>,
    query: Option<String>,
) -> Result<Vec<MemoryEntry>, String> {
    let archives = state.agent.archives.lock().await;
    let queries = query.map(|q| vec![q]).unwrap_or_default();
    Ok(archives.search_memory(&queries))
}

#[tauri::command]
pub async fn query_narrative_events(
    state: State<'_, Arc<AppState>>,
    conv_id: Option<String>,
) -> Result<Vec<NarrativeEvent>, String> {
    let conversation_id = conv_id
        .as_deref()
        .map(uuid::Uuid::parse_str)
        .transpose()
        .map_err(|error| error.to_string())?;
    let archives = state.agent.archives.lock().await;
    Ok(archives
        .all_narrative_events()
        .into_iter()
        .filter(|event| {
            conversation_id
                .map(|id| event.conversation_id == id)
                .unwrap_or(true)
        })
        .collect())
}

#[tauri::command]
pub async fn get_usage_stats(state: State<'_, Arc<AppState>>) -> Result<UsageStats, String> {
    Ok(state.agent.client.usage_stats().await)
}

#[tauri::command]
pub async fn query_blindspots(
    state: State<'_, Arc<AppState>>,
) -> Result<Vec<BlindspotRecord>, String> {
    let conversation_id = *state.agent.selected_conversation_id.read().await;
    let archives = state.agent.archives.lock().await;
    Ok(conversation_id
        .map(|id| {
            archives
                .recent_blindspots(10)
                .into_iter()
                .filter(|blindspot| blindspot.conversation_id == id)
                .collect()
        })
        .unwrap_or_default())
}

#[tauri::command]
pub async fn get_chapters(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
) -> Result<Vec<StoryChapter>, String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    Ok(state
        .agent
        .get_conversation(uid)
        .await
        .map(|c| c.chapters)
        .unwrap_or_default())
}

#[tauri::command]
pub async fn get_chapter_messages(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    index: usize,
) -> Result<Vec<ChatMessage>, String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    Ok(state.agent.get_chapter_messages(uid, index).await)
}

#[tauri::command]
pub async fn search_chapters(
    state: State<'_, Arc<AppState>>,
    conv_id: String,
    query: String,
) -> Result<Vec<StoryChapter>, String> {
    let uid = uuid::Uuid::parse_str(&conv_id).map_err(|e| e.to_string())?;
    Ok(state.agent.search_chapters(uid, &query).await)
}

// ─── Settings ───

#[tauri::command]
pub async fn get_settings() -> Result<Settings, String> {
    Ok(Settings::load())
}

#[tauri::command]
pub async fn save_settings(
    state: State<'_, Arc<AppState>>,
    mut settings: Settings,
) -> Result<(), String> {
    let previous = Settings::load();
    settings.normalize_data_path();
    if settings.user_id.trim().is_empty() {
        settings.user_id = previous.user_id.clone();
    }
    settings.ensure_user_id();

    // Never persist the old display-only `iCloud Drive/Prism` label. Resolve
    // the actual iCloud Drive mirror on the Rust side as the source of truth.
    if settings.icloud_sync {
        let cloud_path = Settings::icloud_data_path().ok_or_else(|| {
            if cfg!(target_os = "macos") {
                "iCloud Drive is unavailable on this Mac.".to_string()
            } else {
                "Cloud storage sync is unavailable on this platform.".to_string()
            }
        })?;
        settings.data_path = cloud_path.to_string_lossy().to_string();
    }

    if previous.data_path != settings.data_path {
        state.agent.persist_conversations().await;
        migrate_storage_data(
            Path::new(&previous.data_path),
            Path::new(&settings.data_path),
        )?;
    }

    log::info!(
        "Saving settings — lang={} mode={}",
        settings.language,
        settings.default_mode
    );
    settings.save()?;
    state.agent.set_settings(&settings).await;

    // Update client settings
    state
        .agent
        .client
        .set_api_key(settings.api_key.clone())
        .await;
    state
        .agent
        .client
        .set_user_id(settings.user_id.clone())
        .await;
    state
        .agent
        .client
        .set_base_url(settings.base_url.clone())
        .await;
    state
        .agent
        .client
        .set_models(settings.flash_model.clone(), settings.pro_model.clone())
        .await;
    state
        .agent
        .client
        .set_thinking(
            settings.pro_thinking_enabled,
            settings.pro_reasoning_effort.clone(),
            settings.flash_thinking_enabled,
            settings.flash_reasoning_effort.clone(),
        )
        .await;
    state.agent.client.set_usage_path(&settings.data_path).await;

    // Update archives data dir
    {
        let mut archives = state.agent.archives.lock().await;
        archives.set_data_dir(settings.data_dir());
    }

    // Swift reloads both conversations and archives after a storage move.
    // Do the same here so the UI immediately reflects the destination rather
    // than continuing to display the old in-memory store until restart.
    if previous.data_path != settings.data_path {
        let moved_conversations = {
            let archives = state.agent.archives.lock().await;
            archives.load_conversations()
        };
        let first_id = moved_conversations
            .first()
            .map(|conversation| conversation.id);
        *state.agent.conversations.write().await = moved_conversations;
        *state.agent.selected_conversation_id.write().await = first_id;
    }

    Ok(())
}

#[tauri::command]
pub async fn choose_directory(app: AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog().file().pick_folder(move |path| {
        let _ = tx.send(path.map(|p| p.to_string()));
    });
    let result = rx.await.unwrap_or_default();
    Ok(result)
}

#[tauri::command]
pub async fn export_logs(app: AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let settings = Settings::load();
    let source = std::path::PathBuf::from(&settings.data_path).join("prism.log");
    if !source.is_file() {
        return Err("No log file is available yet.".to_string());
    }
    let (tx, rx) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .set_file_name("Prism-log.txt")
        .save_file(move |path| {
            let _ = tx.send(path.map(|value| value.to_string()));
        });
    let Some(destination) = rx.await.unwrap_or_default() else {
        return Ok(None);
    };
    std::fs::copy(&source, &destination)
        .map_err(|error| format!("Could not export the log: {}", error))?;
    Ok(Some(destination))
}

#[tauri::command]
pub fn get_storage_paths() -> Result<serde_json::Value, String> {
    Ok(serde_json::json!({
        "localPath": Settings::default_data_path(),
        "iCloudPath": Settings::icloud_data_path().map(|path| path.to_string_lossy().to_string()),
    }))
}

/// Copy Prism's portable data when the storage root changes. Existing files
/// at the destination are preserved, matching the Swift implementation and
/// preventing a second device's newer data from being overwritten.
fn migrate_storage_data(old_root: &Path, new_root: &Path) -> Result<(), String> {
    if old_root == new_root || !old_root.exists() {
        return Ok(());
    }

    std::fs::create_dir_all(new_root).map_err(|e| {
        format!(
            "Cannot create new Prism data directory {:?}: {}",
            new_root, e
        )
    })?;
    copy_if_missing(
        &old_root.join("conversations.json"),
        &new_root.join("conversations.json"),
    )?;
    copy_if_missing(&old_root.join("config.json"), &new_root.join("config.json"))?;
    copy_if_missing(
        &old_root.join("usage_stats.json"),
        &new_root.join("usage_stats.json"),
    )?;
    copy_directory_missing(&old_root.join("Data"), &new_root.join("Data"))?;
    log::info!(
        "Migrated Prism storage from {:?} to {:?}",
        old_root,
        new_root
    );
    Ok(())
}

fn copy_if_missing(source: &Path, destination: &Path) -> Result<(), String> {
    if !source.is_file() || destination.exists() {
        return Ok(());
    }
    if let Some(parent) = destination.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("Cannot create migration directory {:?}: {}", parent, e))?;
    }
    std::fs::copy(source, destination)
        .map(|_| ())
        .map_err(|e| format!("Cannot migrate {:?} to {:?}: {}", source, destination, e))
}

fn copy_directory_missing(source: &Path, destination: &Path) -> Result<(), String> {
    if !source.is_dir() {
        return Ok(());
    }
    std::fs::create_dir_all(destination)
        .map_err(|e| format!("Cannot create archive directory {:?}: {}", destination, e))?;
    for entry in std::fs::read_dir(source)
        .map_err(|e| format!("Cannot read archive directory {:?}: {}", source, e))?
    {
        let entry = entry.map_err(|e| format!("Cannot inspect archive entry: {}", e))?;
        let src = entry.path();
        let dst = destination.join(entry.file_name());
        if src.is_dir() {
            copy_directory_missing(&src, &dst)?;
        } else {
            copy_if_missing(&src, &dst)?;
        }
    }
    Ok(())
}

#[tauri::command]
pub async fn reset_all_settings(
    app: AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Result<(), String> {
    log::warn!("Resetting all settings and data — factory reset initiated");
    // Delete the *configured* root directory rather than only the default
    // paths. This removes conversations, Data archives, settings and logs in
    // one operation, including a user-selected storage location.
    let settings = Settings::load();
    let root = std::path::PathBuf::from(&settings.data_path);
    if root.exists() {
        std::fs::remove_dir_all(&root)
            .map_err(|e| format!("Failed to remove Prism data directory {:?}: {}", root, e))?;
    }

    // Also remove the legacy/default Prism root. Older builds could leave a
    // stale settings.json there after a user moved storage, which would make
    // a factory reset appear to succeed but still skip onboarding on restart.
    let default_root = std::path::PathBuf::from(Settings::default().data_path);
    if default_root != root && default_root.exists() {
        std::fs::remove_dir_all(&default_root).map_err(|e| {
            format!(
                "Failed to remove Prism default data directory {:?}: {}",
                default_root, e
            )
        })?;
    }

    // The bootstrap pointer is outside either data root and must be removed
    // explicitly, otherwise the next launch would follow the old directory.
    match std::fs::remove_file(Settings::bootstrap_path()) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(format!("Failed to remove Prism storage pointer: {}", error));
        }
    }

    // Reset in-memory state
    *state.agent.conversations.write().await = Vec::new();
    *state.agent.selected_conversation_id.write().await = None;
    state.agent.set_settings(&Settings::default()).await;
    state.agent.client.set_api_key(String::new()).await;
    state
        .agent
        .client
        .set_base_url(Settings::default().base_url)
        .await;

    log::info!("Factory reset complete; restarting Prism");
    app.request_restart();
    Ok(())
}

// ─── API Key Validation ──────────────────────────────────────

#[tauri::command]
pub async fn validate_api_key(api_key: String, base_url: String) -> Result<(), String> {
    use crate::deepseek_client::DeepSeekClient;
    log::info!("Validating API key against {}", base_url);
    let client = DeepSeekClient::new();
    match client.validate_key(&api_key, &base_url).await {
        Ok(()) => {
            log::info!("API key validation succeeded");
            Ok(())
        }
        Err(error) => {
            // Never write the key itself to disk; the endpoint and error are
            // enough to diagnose configuration and network failures.
            log::warn!("API key validation failed for {}: {}", base_url, error);
            Err(error)
        }
    }
}

// ─── Frontend Log Forwarding ──────────────────────────────────

#[tauri::command]
pub fn log_message(entries: Vec<LogEntry>) -> Result<(), String> {
    for entry in &entries {
        match entry.level.to_uppercase().as_str() {
            "ERROR" => log::error!(
                "[{}] {} {}",
                entry.tag,
                entry.message,
                entry.data.as_deref().unwrap_or("")
            ),
            "WARN" => log::warn!(
                "[{}] {} {}",
                entry.tag,
                entry.message,
                entry.data.as_deref().unwrap_or("")
            ),
            "INFO" => log::info!(
                "[{}] {} {}",
                entry.tag,
                entry.message,
                entry.data.as_deref().unwrap_or("")
            ),
            _ => log::debug!(
                "[{}] {} {}",
                entry.tag,
                entry.message,
                entry.data.as_deref().unwrap_or("")
            ),
        }
    }
    Ok(())
}
