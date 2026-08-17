use crate::models::*;
use reqwest::Client;
use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex;

/// Convert our persisted tool-call representation to the OpenAI-compatible
/// message shape required by DeepSeek. In particular, every assistant tool
/// call needs `type: "function"` and a nested `function` object.
fn api_message(message: &ChatMessage) -> Value {
    let role = match message.role {
        ChatRole::user => "user",
        ChatRole::assistant => "assistant",
        ChatRole::system => "system",
        ChatRole::tool => "tool",
    };
    let mut api_message = serde_json::json!({
        "role": role,
        "content": message.content,
    });

    if let Some(ref tool_calls) = message.tool_calls {
        let calls = tool_calls
            .iter()
            .map(|tool_call| {
                serde_json::json!({
                    "id": tool_call.id,
                    "type": "function",
                    "function": {
                        "name": tool_call.name,
                        "arguments": tool_call.arguments,
                    }
                })
            })
            .collect::<Vec<_>>();
        api_message["tool_calls"] = Value::Array(calls);
    }
    if let Some(ref tool_call_id) = message.tool_call_id {
        api_message["tool_call_id"] = serde_json::json!(tool_call_id);
    }
    // DeepSeek thinking mode requires the model's private reasoning to be
    // round-tripped on assistant messages, especially assistant tool-call
    // messages. It is stored as `reasoning` in our local model, but the wire
    // name is `reasoning_content`.
    if role == "assistant" && (message.reasoning.is_some() || message.tool_calls.is_some()) {
        api_message["reasoning_content"] =
            serde_json::json!(message.reasoning.clone().unwrap_or_default());
    }
    api_message
}

/// Normalize persisted history before sending it. Older Tauri builds stored
/// tool rounds as ordinary user messages and did not persist the tool-call id;
/// repair those records when their id can be recovered from a preceding
/// assistant message. Keep all valid historical tool calls: removing an older
/// assistant call while retaining its tool result creates a new orphaned tool
/// message, which the API rejects.
fn api_messages(messages: &[ChatMessage]) -> Vec<Value> {
    messages
        .iter()
        .enumerate()
        .map(|(index, message)| {
            let mut normalized = message.clone();

            // Legacy files used `Tool result for ...` as a user message and
            // did not persist the tool call id. Recover the first id from the
            // preceding assistant tool call so the API sees a valid tool turn.
            if normalized.role == ChatRole::user
                && normalized.tool_call_id.is_none()
                && normalized.content.starts_with("Tool result for ")
            {
                let legacy_tool_name = normalized
                    .content
                    .strip_prefix("Tool result for ")
                    .and_then(|value| value.split_once(':'))
                    .map(|(name, _)| name.trim());
                if let Some(tool_call_id) = messages[..index].iter().rev().find_map(|candidate| {
                    if candidate.role == ChatRole::assistant {
                        candidate
                            .tool_calls
                            .as_ref()
                            .and_then(|calls| {
                                calls
                                    .iter()
                                    .find(|call| {
                                        legacy_tool_name.is_none()
                                            || Some(call.name.as_str()) == legacy_tool_name
                                    })
                                    .or_else(|| calls.first())
                            })
                            .map(|call| call.id.clone())
                    } else {
                        None
                    }
                }) {
                    normalized.role = ChatRole::tool;
                    normalized.tool_call_id = Some(tool_call_id);
                }
            }

            api_message(&normalized)
        })
        .collect()
}

pub struct DeepSeekClient {
    api_key: Arc<Mutex<String>>,
    user_id: Arc<Mutex<String>>,
    base_url: Arc<Mutex<String>>,
    flash_model: Arc<Mutex<String>>,
    pro_model: Arc<Mutex<String>>,
    pro_thinking_enabled: Arc<Mutex<bool>>,
    pro_reasoning_effort: Arc<Mutex<String>>,
    flash_thinking_enabled: Arc<Mutex<bool>>,
    flash_reasoning_effort: Arc<Mutex<String>>,
    usage_path: Arc<Mutex<PathBuf>>,
    usage_write_lock: Arc<Mutex<()>>,
    http: Client,
}

impl Clone for DeepSeekClient {
    fn clone(&self) -> Self {
        Self {
            api_key: self.api_key.clone(),
            user_id: self.user_id.clone(),
            base_url: self.base_url.clone(),
            flash_model: self.flash_model.clone(),
            pro_model: self.pro_model.clone(),
            pro_thinking_enabled: self.pro_thinking_enabled.clone(),
            pro_reasoning_effort: self.pro_reasoning_effort.clone(),
            flash_thinking_enabled: self.flash_thinking_enabled.clone(),
            flash_reasoning_effort: self.flash_reasoning_effort.clone(),
            usage_path: self.usage_path.clone(),
            usage_write_lock: self.usage_write_lock.clone(),
            http: self.http.clone(),
        }
    }
}

impl DeepSeekClient {
    pub fn new() -> Self {
        Self {
            api_key: Arc::new(Mutex::new(String::new())),
            user_id: Arc::new(Mutex::new(String::new())),
            base_url: Arc::new(Mutex::new("https://api.deepseek.com".to_string())),
            flash_model: Arc::new(Mutex::new("deepseek-v4-flash".to_string())),
            pro_model: Arc::new(Mutex::new("deepseek-v4-pro".to_string())),
            pro_thinking_enabled: Arc::new(Mutex::new(true)),
            pro_reasoning_effort: Arc::new(Mutex::new("high".to_string())),
            flash_thinking_enabled: Arc::new(Mutex::new(true)),
            flash_reasoning_effort: Arc::new(Mutex::new("high".to_string())),
            usage_path: Arc::new(Mutex::new(PathBuf::new())),
            usage_write_lock: Arc::new(Mutex::new(())),
            http: Client::builder()
                .timeout(std::time::Duration::from_secs(120))
                .build()
                .unwrap(),
        }
    }

    pub fn clone_with_key(&self, api_key: String, base_url: String) -> Self {
        let c = self.clone();
        *c.api_key.blocking_lock() = api_key;
        *c.base_url.blocking_lock() = base_url;
        c
    }

    pub async fn api_key(&self) -> String {
        self.api_key.lock().await.clone()
    }

    pub async fn set_api_key(&self, key: String) {
        *self.api_key.lock().await = key;
    }

    pub async fn set_user_id(&self, user_id: String) {
        *self.user_id.lock().await = user_id;
    }

    pub async fn set_base_url(&self, url: String) {
        *self.base_url.lock().await = url;
    }

    pub async fn set_usage_path(&self, data_path: &str) {
        *self.usage_path.lock().await = PathBuf::from(data_path).join("usage_stats.json");
    }

    pub async fn usage_stats(&self) -> UsageStats {
        let path = self.usage_path.lock().await.clone();
        std::fs::read_to_string(path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default()
    }

    async fn record_usage(&self, usage: TokenUsage) {
        let _guard = self.usage_write_lock.lock().await;
        let path = self.usage_path.lock().await.clone();
        if path.as_os_str().is_empty() {
            return;
        }
        let mut stats: UsageStats = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        stats.input_tokens = stats.input_tokens.saturating_add(usage.prompt_tokens);
        stats.output_tokens = stats.output_tokens.saturating_add(usage.completion_tokens);
        stats.cache_hit_tokens = stats
            .cache_hit_tokens
            .saturating_add(usage.prompt_cache_hit_tokens);
        stats.cache_miss_tokens = stats
            .cache_miss_tokens
            .saturating_add(usage.prompt_cache_miss_tokens);
        stats.request_count = stats.request_count.saturating_add(1);
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(text) = serde_json::to_string_pretty(&stats) {
            let temporary = path.with_extension("json.tmp");
            if std::fs::write(&temporary, text).is_ok() {
                let _ = std::fs::rename(temporary, path);
            }
        }
    }

    pub async fn set_models(&self, flash: String, pro: String) {
        *self.flash_model.lock().await = flash;
        *self.pro_model.lock().await = pro;
    }

    pub async fn flash_model(&self) -> String {
        self.flash_model.lock().await.clone()
    }

    pub async fn pro_model(&self) -> String {
        self.pro_model.lock().await.clone()
    }

    pub async fn set_thinking(
        &self,
        pro_enabled: bool,
        pro_effort: String,
        flash_enabled: bool,
        flash_effort: String,
    ) {
        *self.pro_thinking_enabled.lock().await = pro_enabled;
        *self.pro_reasoning_effort.lock().await = pro_effort;
        *self.flash_thinking_enabled.lock().await = flash_enabled;
        *self.flash_reasoning_effort.lock().await = flash_effort;
    }

    /// Non-streaming completion for Flash model (pre-pipeline, summarization, search)
    pub async fn complete(
        &self,
        model: &str,
        messages: Vec<ChatMessage>,
        temperature: f64,
        top_p: f64,
        max_tokens: u32,
    ) -> Result<String, String> {
        self.complete_inner(model, messages, temperature, top_p, max_tokens, None)
            .await
    }

    /// Fast auxiliary completion. The Swift implementation disables thinking
    /// for guard-panel and chapter-summary calls; doing the same here avoids
    /// spending the maximum reasoning budget before the visible reply starts.
    pub async fn complete_without_thinking(
        &self,
        model: &str,
        messages: Vec<ChatMessage>,
        temperature: f64,
        top_p: f64,
        max_tokens: u32,
    ) -> Result<String, String> {
        self.complete_inner(model, messages, temperature, top_p, max_tokens, Some(false))
            .await
    }

    async fn complete_inner(
        &self,
        model: &str,
        messages: Vec<ChatMessage>,
        temperature: f64,
        top_p: f64,
        max_tokens: u32,
        thinking_override: Option<bool>,
    ) -> Result<String, String> {
        let api_key = self.api_key.lock().await.clone();
        let user_id = self.user_id.lock().await.clone();
        let base_url = self.base_url.lock().await.clone();
        let is_flash = model.to_ascii_lowercase().contains("flash");
        let thinking_enabled = if let Some(override_value) = thinking_override {
            override_value
        } else if is_flash {
            *self.flash_thinking_enabled.lock().await
        } else {
            *self.pro_thinking_enabled.lock().await
        };
        let reasoning_effort = if is_flash {
            self.flash_reasoning_effort.lock().await.clone()
        } else {
            self.pro_reasoning_effort.lock().await.clone()
        };

        let api_msgs = api_messages(&messages);

        let mut body = serde_json::json!({
            "model": model,
            "user_id": user_id,
            "messages": api_msgs,
            "temperature": temperature,
            "top_p": top_p,
            "max_tokens": max_tokens,
            "stream": false,
        });

        if thinking_enabled {
            body["thinking"] = serde_json::json!({"type": "enabled"});
            body["reasoning_effort"] = serde_json::json!(reasoning_effort);
        }

        let resp = self
            .http
            .post(format!("{}/chat/completions", base_url))
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Read body failed: {}", e))?;

        if !status.is_success() {
            return Err(format!("API error {}: {}", status, text));
        }

        let v: Value = serde_json::from_str(&text).map_err(|e| format!("Parse failed: {}", e))?;
        if let Ok(usage) = serde_json::from_value::<TokenUsage>(v["usage"].clone()) {
            self.record_usage(usage).await;
        }
        let content = v["choices"][0]["message"]["content"]
            .as_str()
            .unwrap_or("")
            .to_string();
        Ok(content)
    }

    /// Streaming completion for the active conversation model.
    pub async fn stream_complete(
        &self,
        model: &str,
        messages: Vec<ChatMessage>,
        temperature: f64,
        top_p: f64,
        max_tokens: u32,
        reasoning_effort: Option<String>,
        tools: Option<Vec<Value>>,
        on_reasoning: impl Fn(String),
        on_text: impl Fn(String),
        on_tool_call: impl Fn(String, String, String),
        on_done: impl Fn(),
    ) -> Result<(), String> {
        let api_key = self.api_key.lock().await.clone();
        let user_id = self.user_id.lock().await.clone();
        let base_url = self.base_url.lock().await.clone();
        // Streaming is used by the main chat. Read the parameter set that
        // belongs to the actual model instead of always using Pro's values.
        let is_flash = model.to_ascii_lowercase().contains("flash");
        let thinking_enabled = if is_flash {
            *self.flash_thinking_enabled.lock().await
        } else {
            *self.pro_thinking_enabled.lock().await
        };
        let effort = if let Some(e) = reasoning_effort {
            e
        } else if is_flash {
            self.flash_reasoning_effort.lock().await.clone()
        } else {
            self.pro_reasoning_effort.lock().await.clone()
        };

        let api_msgs = api_messages(&messages);

        let mut body = serde_json::json!({
            "model": model,
            "user_id": user_id,
            "messages": api_msgs,
            "temperature": temperature,
            "top_p": top_p,
            "max_tokens": max_tokens,
            "stream": true,
            "stream_options": {"include_usage": true},
        });

        if thinking_enabled {
            body["thinking"] = serde_json::json!({"type": "enabled"});
            body["reasoning_effort"] = serde_json::json!(effort);
        }
        if let Some(tools) = tools {
            body["tools"] = Value::Array(tools);
        }

        log::info!(
            "DeepSeek stream request — model={} thinking={} effort={} messages={}",
            model,
            thinking_enabled,
            effort,
            api_msgs.len()
        );

        let resp = self
            .http
            .post(format!("{}/chat/completions", base_url))
            .header("Authorization", format!("Bearer {}", api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        if !status.is_success() {
            let text = resp.text().await.unwrap_or_default();
            log::error!(
                "DeepSeek stream response failed — model={} status={} body={}",
                model,
                status,
                text
            );
            return Err(format!("API error {}: {}", status, text));
        }

        let mut stream = resp.bytes_stream();
        let mut buffer = String::new();
        let mut saw_payload = false;
        let final_usage = Arc::new(StdMutex::new(None::<TokenUsage>));
        let final_usage_for_line = final_usage.clone();
        let mut process_line = |line: &str| -> bool {
            let line = line.trim();
            if line.is_empty() || line.starts_with(':') {
                return false;
            }

            let Some(data) = line.strip_prefix("data:").map(|value| value.trim_start()) else {
                return false;
            };

            if data == "[DONE]" {
                return true;
            }

            if let Ok(v) = serde_json::from_str::<Value>(data) {
                saw_payload = true;
                if let Ok(usage) = serde_json::from_value::<TokenUsage>(v["usage"].clone()) {
                    if let Ok(mut slot) = final_usage_for_line.lock() {
                        *slot = Some(usage);
                    }
                }
                if let Some(choices) = v["choices"].as_array() {
                    for choice in choices {
                        let delta = &choice["delta"];
                        if let Some(content) = delta["content"].as_str() {
                            if !content.is_empty() {
                                on_text(content.to_string());
                            }
                        }
                        if let Some(reasoning) = delta["reasoning_content"].as_str() {
                            if !reasoning.is_empty() {
                                on_reasoning(reasoning.to_string());
                            }
                        }
                        if let Some(tc) = delta["tool_calls"].as_array() {
                            for tc_entry in tc {
                                let id = tc_entry["id"].as_str().unwrap_or("").to_string();
                                let name = tc_entry["function"]["name"]
                                    .as_str()
                                    .unwrap_or("")
                                    .to_string();
                                let args = tc_entry["function"]["arguments"]
                                    .as_str()
                                    .unwrap_or("")
                                    .to_string();
                                on_tool_call(id, name, args);
                            }
                        }
                    }
                }
            }
            false
        };

        while let Some(chunk) = futures_util::StreamExt::next(&mut stream).await {
            let chunk = chunk.map_err(|e| format!("Stream error: {}", e))?;
            buffer.push_str(&String::from_utf8_lossy(&chunk));

            while let Some(line_end) = buffer.find('\n') {
                let line = buffer[..line_end].to_string();
                buffer = buffer[line_end + 1..].to_string();

                if process_line(&line) {
                    let usage = final_usage.lock().ok().and_then(|slot| slot.clone());
                    if let Some(usage) = usage {
                        self.record_usage(usage).await;
                    }
                    on_done();
                    return Ok(());
                }
            }
        }

        // Some compatible OpenAI endpoints close the SSE stream without a
        // final newline or [DONE] marker. Process that last frame instead of
        // silently dropping it, then always notify the UI that streaming has
        // ended.
        if !buffer.trim().is_empty() && process_line(&buffer) {
            let usage = final_usage.lock().ok().and_then(|slot| slot.clone());
            if let Some(usage) = usage {
                self.record_usage(usage).await;
            }
            on_done();
            return Ok(());
        }
        if !saw_payload {
            return Err("Streaming response ended without data".to_string());
        }
        let usage = final_usage.lock().ok().and_then(|slot| slot.clone());
        if let Some(usage) = usage {
            self.record_usage(usage).await;
        }
        on_done();
        Ok(())
    }

    /// Validate an API key by making a lightweight models-list request.
    pub async fn validate_key(&self, api_key: &str, base_url: &str) -> Result<(), String> {
        let url = format!("{}/models", base_url.trim_end_matches('/'));
        let resp = self
            .http
            .get(&url)
            .header("Authorization", format!("Bearer {}", api_key))
            .timeout(std::time::Duration::from_secs(10))
            .send()
            .await
            .map_err(|e| format!("Network error: {}", e))?;

        let status = resp.status();
        if status.is_success() {
            Ok(())
        } else if status.as_u16() == 401 {
            Err("Invalid API key (HTTP 401)".to_string())
        } else {
            let body = resp.text().await.unwrap_or_default();
            Err(format!("API error (HTTP {}): {}", status.as_u16(), body))
        }
    }
}

impl Default for DeepSeekClient {
    fn default() -> Self {
        Self::new()
    }
}
