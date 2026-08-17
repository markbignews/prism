use crate::deepseek_client::DeepSeekClient;
use crate::models::*;
use chrono::{DateTime, Utc};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

#[derive(Debug, Clone, Default)]
pub struct GuardPanelResult {
    pub reality_distortion: bool,
    pub emotional_spiral: bool,
    pub narrative_blindspot: bool,
    pub ingratiation: bool,
    pub action_hollow: bool,
    pub safety_crisis: bool,
    pub crisis_detail: String,
    pub crisis_hotline: String,
    pub emotions: Vec<EmotionEntry>,
    pub persons: Vec<PersonRecord>,
    pub blindspots: Vec<BlindspotRecord>,
    pub raw_warnings: Vec<String>,
}

pub struct PrePipeline {
    client: DeepSeekClient,
    active_crises: Arc<Mutex<HashSet<Uuid>>>,
    crisis_hints: Arc<Mutex<HashMap<Uuid, String>>>,
}

impl PrePipeline {
    pub fn new(client: DeepSeekClient) -> Self {
        Self {
            client,
            active_crises: Arc::new(Mutex::new(HashSet::new())),
            crisis_hints: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn run(
        &self,
        conversation_id: Uuid,
        user_text: &str,
        _mode: &ConversationMode,
        _language: &str,
        context: &str,
        request_sent_at: DateTime<Utc>,
    ) -> Result<GuardPanelResult, String> {
        let previous_safety = self
            .active_crises
            .lock()
            .ok()
            .map(|active| active.contains(&conversation_id))
            .unwrap_or(false);
        let previous_hint = self
            .crisis_hints
            .lock()
            .ok()
            .and_then(|hints| hints.get(&conversation_id).cloned())
            .unwrap_or_default();

        let system_msg = ChatMessage::new(
            ChatRole::system,
            crate::prompts::guard_panel_prompt().to_string(),
        );
        let user_content = format!(
            "当前用户请求发送时间：{}。将其作为回复时机、昼夜时段、消息间隔、作息与画像趋势的依据；除非用户明确说明，不得视为所述事件的发生时间。\n\n最近对话上下文：\n{}\n\n当前用户消息：\n{}{}",
            request_sent_at.to_rfc3339(),
            context,
            user_text,
            if previous_safety {
                format!(
                    "\n\n⚠️ 上轮已触发安全干预。上一轮建议：{}\n请判断当前是否仍处于危险中。",
                    previous_hint
                )
            } else {
                String::new()
            }
        );
        let user_msg = ChatMessage::new(ChatRole::user, user_content);

        let flash_model = self.client.flash_model().await;
        let response = self
            .client
            .complete_without_thinking(&flash_model, vec![system_msg, user_msg], 0.1, 0.8, 1024)
            .await?;

        let parsed = extract_json(&response).unwrap_or(Value::Null);
        let mut result = GuardPanelResult::default();

        if let Some(values) = parsed.get("emotions").and_then(Value::as_array) {
            for value in values {
                if let (Some(emotion), Some(intensity)) =
                    (value["emotion"].as_str(), value["intensity"].as_f64())
                {
                    result.emotions.push(EmotionEntry {
                        id: Uuid::new_v4(),
                        conversation_id,
                        segment: value["segment"]
                            .as_str()
                            .unwrap_or(user_text)
                            .chars()
                            .take(100)
                            .collect(),
                        emotion: emotion.to_string(),
                        intensity: intensity.clamp(0.0, 1.0),
                        created_at: request_sent_at,
                    });
                }
            }
        }

        if let Some(values) = parsed.get("persons").and_then(Value::as_array) {
            for value in values {
                if let (Some(name), Some(role)) = (value["name"].as_str(), value["role"].as_str()) {
                    result.persons.push(PersonRecord {
                        id: Uuid::new_v4(),
                        name: name.to_string(),
                        role: role.to_string(),
                        first_mentioned_at: request_sent_at,
                        last_mentioned_at: request_sent_at,
                        mention_count: 1,
                        emotional_arc: String::new(),
                        notes: vec![],
                    });
                }
            }
        }

        // The current Swift schema puts findings under guard.blindspots; the
        // legacy Tauri schema put them at the top level. Accept both.
        let guard_obj = parsed.get("guard").unwrap_or(&parsed);
        if let Some(values) = guard_obj
            .get("blindspots")
            .and_then(|value| value["findings"].as_array())
            .or_else(|| parsed.get("blindspots").and_then(Value::as_array))
        {
            for value in values {
                if let (Some(pattern), Some(evidence), Some(question)) = (
                    value["pattern"].as_str(),
                    value["evidence"].as_str(),
                    value["counter_question"].as_str(),
                ) {
                    result.blindspots.push(BlindspotRecord {
                        id: Uuid::new_v4(),
                        conversation_id,
                        pattern: pattern.to_string(),
                        evidence: evidence.to_string(),
                        counter_question: question.to_string(),
                        severity: value["severity"].as_str().unwrap_or("new").to_string(),
                        created_at: request_sent_at,
                    });
                }
            }
        }

        let dimensions = [
            ("reality", "reality_distortion"),
            ("spiral", "emotional_spiral"),
            ("blindspots", "narrative_blindspot"),
            ("ingratiation", "ingratiation"),
            ("action_hollow", "action_hollow"),
        ];
        for (key, legacy_key) in dimensions {
            let value = guard_obj.get(key).or_else(|| parsed.get(legacy_key));
            let warning = value.and_then(|entry| entry["flag"].as_str()) == Some("warning")
                || value
                    .and_then(|entry| entry["detected"].as_bool())
                    .unwrap_or(false);
            if warning {
                match legacy_key {
                    "reality_distortion" => result.reality_distortion = true,
                    "emotional_spiral" => result.emotional_spiral = true,
                    "narrative_blindspot" => result.narrative_blindspot = true,
                    "ingratiation" => result.ingratiation = true,
                    "action_hollow" => result.action_hollow = true,
                    _ => {}
                }
                let hint = value
                    .and_then(|entry| entry["hint"].as_str().or_else(|| entry["detail"].as_str()))
                    .unwrap_or("");
                result.raw_warnings.push(if hint.is_empty() {
                    key.to_string()
                } else {
                    format!("{}: {}", key, hint)
                });
            }
        }

        let safety = guard_obj
            .get("safety")
            .or_else(|| parsed.get("safety_crisis"));
        let safety_flag = safety.and_then(|value| value["flag"].as_str());
        let safety_detected = safety
            .and_then(|value| value["detected"].as_bool())
            .unwrap_or(false);
        if safety_flag == Some("crisis") || safety_detected {
            result.safety_crisis = true;
            result.crisis_detail = safety
                .and_then(|value| {
                    value["suggest"]
                        .as_str()
                        .or_else(|| value["detail"].as_str())
                })
                .unwrap_or("请先确认你当前是否处于安全环境。")
                .to_string();
            result.crisis_hotline = safety
                .and_then(|value| {
                    value["resources"]
                        .as_str()
                        .or_else(|| value["hotline"].as_str())
                })
                .unwrap_or("")
                .to_string();
            if let Ok(mut active) = self.active_crises.lock() {
                active.insert(conversation_id);
            }
            if let Ok(mut hints) = self.crisis_hints.lock() {
                hints.insert(
                    conversation_id,
                    format!("{} {}", result.crisis_detail, result.crisis_hotline),
                );
            }
        } else if safety_flag == Some("ok") {
            if let Ok(mut active) = self.active_crises.lock() {
                active.remove(&conversation_id);
            }
            if let Ok(mut hints) = self.crisis_hints.lock() {
                hints.remove(&conversation_id);
            }
        }

        Ok(result)
    }
}

fn extract_json(text: &str) -> Option<Value> {
    let trimmed = text.trim();
    let cleaned = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .unwrap_or(trimmed)
        .trim_end_matches("```")
        .trim();
    let start = cleaned.find('{')?;
    let end = cleaned.rfind('}')?;
    serde_json::from_str(&cleaned[start..=end]).ok()
}
