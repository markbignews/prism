#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use prism::archives::Archives;
use prism::chat_agent::ChatAgent;
use prism::commands::AppState;
use prism::deepseek_client::DeepSeekClient;
use prism::settings::Settings;
use simplelog::*;
use std::fs;
use std::sync::Arc;

fn main() {
    let settings = Settings::load();

    // ── Log file in user's data directory ─────────────────────
    let log_path = std::path::PathBuf::from(&settings.data_path).join("prism.log");
    if let Some(parent) = log_path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    // ── Logging: console + optional file ─────────────────────
    let mut log_config_builder = ConfigBuilder::new();
    log_config_builder.set_time_format_rfc3339();
    let _ = log_config_builder.set_time_offset_to_local();
    let log_config = log_config_builder.build();

    if settings.enable_logging {
        let mut loggers: Vec<Box<dyn SharedLogger>> = vec![TermLogger::new(
            if cfg!(debug_assertions) {
                LevelFilter::Debug
            } else {
                LevelFilter::Info
            },
            log_config.clone(),
            TerminalMode::Stderr,
            ColorChoice::Auto,
        )];

        // Keep the primary log beside Prism's data. If that location is not
        // writable, use the platform temporary directory rather than the
        // Unix-only `/tmp` path (which does not exist on a normal Windows
        // installation). Logging should never prevent the app from starting.
        let log_file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .or_else(|_| {
                fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(std::env::temp_dir().join("prism.log"))
            });
        if let Ok(log_file) = log_file {
            loggers.push(WriteLogger::new(LevelFilter::Debug, log_config, log_file));
        }
        let _ = CombinedLogger::init(loggers);
    } else {
        let _ = CombinedLogger::init(vec![TermLogger::new(
            LevelFilter::Error,
            log_config,
            TerminalMode::Stderr,
            ColorChoice::Auto,
        )]);
    }

    log::info!("══════ Prism starting ══════");
    log::info!("Data dir: {:?}", settings.data_dir());
    log::info!("Log file: {:?}", log_path);
    log::info!("Logging enabled: {}", settings.enable_logging);
    log::info!("Language: {}", settings.language);

    let client = DeepSeekClient::new();
    let archives = Archives::new(settings.data_dir());
    let saved_conversations = archives.load_conversations();

    let agent = ChatAgent::new(client.clone(), archives);
    tauri::async_runtime::block_on(async {
        agent.set_settings(&settings).await;
        client.set_api_key(settings.api_key.clone()).await;
        client.set_user_id(settings.user_id.clone()).await;
        client.set_base_url(settings.base_url.clone()).await;
        client
            .set_models(settings.flash_model.clone(), settings.pro_model.clone())
            .await;
        client
            .set_thinking(
                settings.pro_thinking_enabled,
                settings.pro_reasoning_effort.clone(),
                settings.flash_thinking_enabled,
                settings.flash_reasoning_effort.clone(),
            )
            .await;
        client.set_usage_path(&settings.data_path).await;
    });
    {
        let mut conversations = agent.conversations.blocking_write();
        *conversations = saved_conversations;
    }
    if let Some(first) = agent.conversations.blocking_read().first() {
        *agent.selected_conversation_id.blocking_write() = Some(first.id);
    }

    let state = Arc::new(AppState { agent });

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            prism::commands::start_window_dragging,
            prism::commands::get_platform,
            prism::commands::create_conversation,
            prism::commands::delete_conversation,
            prism::commands::delete_message_pair,
            prism::commands::truncate_conversation,
            prism::commands::list_conversations,
            prism::commands::get_conversation,
            prism::commands::get_context_usage,
            prism::commands::set_mode,
            prism::commands::set_title,
            prism::commands::send_message,
            prism::commands::cancel_message,
            prism::commands::summarize_deselect,
            prism::commands::re_summarize,
            prism::commands::query_emotions,
            prism::commands::query_persons,
            prism::commands::query_person,
            prism::commands::query_memory,
            prism::commands::query_narrative_events,
            prism::commands::get_usage_stats,
            prism::commands::get_user_balance,
            prism::commands::query_blindspots,
            prism::commands::get_chapters,
            prism::commands::get_chapter_messages,
            prism::commands::search_chapters,
            prism::commands::get_settings,
            prism::commands::save_settings,
            prism::commands::choose_directory,
            prism::commands::export_logs,
            prism::commands::get_storage_paths,
            prism::commands::reset_all_settings,
            prism::commands::log_message,
            prism::commands::validate_api_key,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
