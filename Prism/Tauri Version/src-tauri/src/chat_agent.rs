use crate::archives::Archives;
use crate::deepseek_client::DeepSeekClient;
use crate::models::*;
use crate::pre_pipeline::PrePipeline;
use crate::prompts;
use crate::story_memory::StoryMemory;
use crate::tools;
use chrono::{DateTime, Timelike, Utc};
use serde_json::Value;
use std::collections::HashSet;
use std::sync::{Arc, Mutex as StdMutex};
use tokio::sync::{Mutex, RwLock};
use uuid::Uuid;

const CONTEXT_CAPACITY_TOKENS: u64 = 1_000_000;
const CONTEXT_PREPARATION_TOKENS: u64 = 550_000;
const CONTEXT_COMPRESSION_TOKENS: u64 = 750_000;
const CONTEXT_CRITICAL_TOKENS: u64 = 850_000;
const RETAINED_RECENT_TOKENS: u64 = 200_000;
const CRITICAL_RETAINED_RECENT_TOKENS: u64 = 150_000;

fn parse_json_object(text: &str) -> Option<Value> {
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

#[cfg(test)]
mod context_window_tests {
    use super::*;

    #[test]
    fn short_conversation_keeps_every_message() {
        let mut conversation = Conversation::new("short".to_string());
        conversation.messages.push(ChatMessage::new(
            ChatRole::user,
            "这是一条短消息".to_string(),
        ));
        conversation.messages.push(ChatMessage::new(
            ChatRole::assistant,
            "这是回复".to_string(),
        ));

        let request_messages = windowed_conversation_messages(&conversation, 0);

        assert_eq!(request_messages.len(), 2);
        assert!(request_messages[0].content.contains("[sentAt="));
        assert_eq!(conversation.messages.len(), 2);
    }

    #[test]
    fn large_conversation_compacts_only_the_request() {
        let mut conversation = Conversation::new("large".to_string());
        conversation.messages.push(ChatMessage::new(
            ChatRole::assistant,
            "🙂".repeat((CONTEXT_COMPRESSION_TOKENS + 10_000) as usize),
        ));
        conversation.messages.push(ChatMessage::new(
            ChatRole::user,
            "最近的重要消息".to_string(),
        ));
        let raw_tokens = conversation
            .messages
            .iter()
            .map(estimate_message_tokens)
            .sum::<u64>();

        let request_messages = windowed_conversation_messages(&conversation, 0);
        let request_tokens = request_messages
            .iter()
            .map(estimate_prepared_message_tokens)
            .sum::<u64>();

        assert_eq!(conversation.messages.len(), 2);
        assert_eq!(request_messages.len(), 2);
        assert!(request_messages[0].content.contains("compacted"));
        assert!(request_messages[1].content.contains("最近的重要消息"));
        assert!(request_tokens < raw_tokens);
    }
}

/// Attach immutable send-time metadata to user messages without changing the
/// leading system prompt, preserving DeepSeek prefix-cache reuse across turns.
fn message_for_model(message: &ChatMessage) -> ChatMessage {
    let mut api_message = message.clone();
    if api_message.role == ChatRole::user {
        api_message.content = format!(
            "[sentAt={}]\n{}",
            api_message.created_at.to_rfc3339(),
            api_message.content
        );
    }
    api_message
}

fn estimate_tokens(text: &str) -> u64 {
    text.chars()
        .map(|character| {
            if ('\u{3400}'..='\u{9fff}').contains(&character)
                || ('\u{f900}'..='\u{faff}').contains(&character)
            {
                0.6
            } else if character.is_whitespace() {
                0.05
            } else if character as u32 >= 0x1f000 {
                1.0
            } else {
                0.3
            }
        })
        .sum::<f64>()
        .ceil() as u64
}

fn estimate_message_tokens(message: &ChatMessage) -> u64 {
    let api_message = message_for_model(message);
    estimate_prepared_message_tokens(&api_message)
}

fn estimate_prepared_message_tokens(message: &ChatMessage) -> u64 {
    let mut total = estimate_tokens(&message.content).saturating_add(8);
    if let Some(reasoning) = &message.reasoning {
        total = total.saturating_add(estimate_tokens(reasoning));
    }
    if let Some(tool_calls) = &message.tool_calls {
        if let Ok(serialized) = serde_json::to_string(tool_calls) {
            total = total.saturating_add(estimate_tokens(&serialized));
        }
    }
    total
}

fn recent_message_start(messages: &[ChatMessage], token_budget: u64) -> usize {
    let mut start = messages.len();
    let mut retained_tokens = 0_u64;
    for index in (0..messages.len()).rev() {
        let message_tokens = estimate_message_tokens(&messages[index]);
        if start < messages.len() && retained_tokens.saturating_add(message_tokens) > token_budget {
            break;
        }
        start = index;
        retained_tokens = retained_tokens.saturating_add(message_tokens);
        if retained_tokens >= token_budget {
            break;
        }
    }
    start
}

/// Build the exact conversation block sent to DeepSeek. Chapter synthesis is
/// always available as an index, but raw messages are only replaced once the
/// conversation itself reaches the 75% token threshold. Local history is
/// never mutated by this function.
fn windowed_conversation_messages(
    conversation: &Conversation,
    global_chapter_offset: usize,
) -> Vec<ChatMessage> {
    let mut messages = Vec::new();
    if !conversation.chapters.is_empty() {
        let index_lines = conversation
            .chapters
            .iter()
            .enumerate()
            .map(|(index, chapter)| {
                format!(
                    "{}. {} — {}",
                    global_chapter_offset + index + 1,
                    chapter.title,
                    chapter.summary.chars().take(160).collect::<String>()
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        messages.push(ChatMessage::new(
            ChatRole::system,
            format!(
                "[Chapter Index — use search_chapters or fetch_chapter_messages]\n{}",
                index_lines
            ),
        ));
    }

    let raw_tokens = conversation
        .messages
        .iter()
        .map(estimate_message_tokens)
        .sum::<u64>();
    if raw_tokens < CONTEXT_COMPRESSION_TOKENS {
        messages.extend(conversation.messages.iter().map(message_for_model));
        return messages;
    }

    let recent_token_budget = if raw_tokens >= CONTEXT_CRITICAL_TOKENS {
        CRITICAL_RETAINED_RECENT_TOKENS
    } else {
        RETAINED_RECENT_TOKENS
    };
    let start = recent_message_start(&conversation.messages, recent_token_budget);
    let older_ids = conversation.messages[..start]
        .iter()
        .map(|message| message.id)
        .collect::<HashSet<_>>();
    let mut summary_lines = conversation
        .chapters
        .iter()
        .filter(|chapter| {
            chapter
                .message_ids
                .iter()
                .any(|message_id| older_ids.contains(message_id))
        })
        .map(|chapter| format!("▸ {}: {}", chapter.title, chapter.summary))
        .collect::<Vec<_>>();

    if summary_lines.is_empty() {
        summary_lines = conversation.messages[..start]
            .iter()
            .rev()
            .take(24)
            .rev()
            .map(|message| {
                let role = if message.role == ChatRole::user {
                    "user"
                } else {
                    "assistant"
                };
                format!(
                    "▸ [{} {}] {}",
                    role,
                    message.created_at.to_rfc3339(),
                    message.content.chars().take(240).collect::<String>()
                )
            })
            .collect();
    }

    messages.push(ChatMessage::new(
        ChatRole::system,
        format!(
            "[Historical context compacted — the uncompressed input reached 75% of the model window. Full local history is unchanged. Use search_chapters or fetch_chapter_messages for detail.]\n{}",
            summary_lines.join("\n")
        ),
    ));
    messages.extend(conversation.messages[start..].iter().map(message_for_model));
    messages
}

fn parse_chapter_array(text: &str, messages: &[(usize, ChatMessage)]) -> Vec<StoryChapter> {
    let trimmed = text.trim();
    let cleaned = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .unwrap_or(trimmed)
        .trim_end_matches("```")
        .trim();
    let Some(start) = cleaned.find('[') else {
        return Vec::new();
    };
    let Some(end) = cleaned.rfind(']') else {
        return Vec::new();
    };
    let Ok(value) = serde_json::from_str::<Value>(&cleaned[start..=end]) else {
        return Vec::new();
    };
    let Some(array) = value.as_array() else {
        return Vec::new();
    };

    array
        .iter()
        .filter_map(|entry| {
            let title = entry["title"].as_str()?.trim();
            let summary = entry["summary"].as_str()?.trim();
            if title.is_empty() || summary.is_empty() {
                return None;
            }
            let start_index = entry["startIndex"].as_i64().unwrap_or(1).max(1) as usize - 1;
            let end_index = entry["endIndex"]
                .as_i64()
                .unwrap_or(messages.len() as i64)
                .max(1) as usize
                - 1;
            let start_index = start_index.min(messages.len().saturating_sub(1));
            let end_index = end_index
                .max(start_index)
                .min(messages.len().saturating_sub(1));
            let keywords = entry["keywords"]
                .as_array()
                .map(|values| {
                    values
                        .iter()
                        .filter_map(|value| value.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            Some(StoryChapter {
                id: Uuid::new_v4(),
                title: title.to_string(),
                summary: summary.chars().take(320).collect(),
                keywords,
                message_ids: messages[start_index..=end_index]
                    .iter()
                    .map(|(_, message)| message.id)
                    .collect(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            })
        })
        .collect()
}

fn temporal_day_part(date: DateTime<Utc>, language: &str) -> &'static str {
    let hour = date.with_timezone(&chrono::Local).hour();
    if language.starts_with("zh") {
        if hour < 6 {
            "深夜"
        } else if hour < 12 {
            "上午"
        } else if hour < 18 {
            "下午"
        } else if hour < 23 {
            "晚上"
        } else {
            "深夜"
        }
    } else if hour < 6 {
        "late night"
    } else if hour < 12 {
        "morning"
    } else if hour < 18 {
        "afternoon"
    } else if hour < 23 {
        "evening"
    } else {
        "late night"
    }
}

fn temporal_stamp(date: DateTime<Utc>) -> String {
    date.with_timezone(&chrono::Local)
        .format("%Y-%m-%d %H:%M:%S %:z")
        .to_string()
}

fn temporal_duration(seconds: i64, language: &str) -> String {
    let minutes = (seconds.max(0)) / 60;
    if language.starts_with("zh") {
        if minutes < 1 {
            return "不到1分钟".to_string();
        }
        if minutes < 60 {
            return format!("{}分钟", minutes);
        }
        let hours = minutes / 60;
        if hours < 24 {
            return format!("{}小时{}分钟", hours, minutes % 60);
        }
        return format!("{}天{}小时", hours / 24, hours % 24);
    }
    if minutes < 1 {
        return "under 1 min".to_string();
    }
    if minutes < 60 {
        return format!("{} min", minutes);
    }
    let hours = minutes / 60;
    if hours < 24 {
        format!("{} hr {} min", hours, minutes % 60)
    } else {
        format!("{}d {}h", hours / 24, hours % 24)
    }
}

fn temporal_context(
    conversation: &Conversation,
    now: DateTime<Utc>,
    language: &str,
    emotions: &[EmotionEntry],
    persons: &[PersonRecord],
) -> String {
    let elapsed = (now - conversation.created_at).num_seconds().max(0);
    let users: Vec<&ChatMessage> = conversation
        .messages
        .iter()
        .filter(|message| message.role == ChatRole::user)
        .collect();
    let recent = users.iter().rev().take(8).rev().collect::<Vec<_>>();
    let message_lines = recent
        .iter()
        .enumerate()
        .map(|(index, message)| {
            let previous = if index > 0 {
                recent[index - 1].created_at
            } else {
                conversation.created_at
            };
            let gap = (message.created_at - previous).num_seconds();
            format!(
                "- {} [{}] gap={}: {}",
                temporal_stamp(message.created_at),
                temporal_day_part(message.created_at, language),
                temporal_duration(gap, language),
                message.content.chars().take(180).collect::<String>()
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let chapter_lines = conversation
        .chapters
        .iter()
        .rev()
        .take(6)
        .enumerate()
        .map(|(index, chapter)| {
            let dates: Vec<DateTime<Utc>> = conversation
                .messages
                .iter()
                .filter(|message| chapter.message_ids.contains(&message.id))
                .map(|message| message.created_at)
                .collect();
            let start = dates.iter().min().copied().unwrap_or(chapter.created_at);
            let end = dates.iter().max().copied().unwrap_or(chapter.updated_at);
            format!(
                "- {}. {}: {} → {} ({})",
                index + 1,
                chapter.title,
                temporal_stamp(start),
                temporal_stamp(end),
                temporal_duration((end - start).num_seconds(), language)
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let emotion_lines = emotions
        .iter()
        .filter(|emotion| emotion.conversation_id == conversation.id)
        .rev()
        .take(5)
        .map(|emotion| {
            let confidence = emotion
                .confidence
                .map(|value| format!(" confidence={:.1}", value))
                .unwrap_or_default();
            format!(
                "- {} {} intensity={:.1}{}",
                temporal_stamp(emotion.created_at),
                emotion.emotion,
                emotion.intensity,
                confidence
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let relationship_lines = persons
        .iter()
        .filter(|person| {
            person.mention_count > 0
                && person
                    .conversation_ids
                    .as_ref()
                    .map(|ids| ids.contains(&conversation.id))
                    .unwrap_or(false)
        })
        .take(5)
        .map(|person| {
            format!(
                "- {} ({}): {} → {}, mentions={}",
                person.name,
                person.role,
                temporal_stamp(person.first_mentioned_at),
                temporal_stamp(person.last_mentioned_at),
                person.mention_count
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let policy = if language.starts_with("zh") {
        "判断心理状态和关系变化时必须结合时间戳、间隔和昼夜时段。如果用户补充具体事件或细节却没有绝对或相对时间，必须先二次询问大概发生在什么时候，再继续分析；不要自行编造时间。"
    } else {
        "Use timestamps, gaps, and daypart when interpreting emotional state. If the user adds a concrete event or detail without an absolute or relative time, ask a concise follow-up for an approximate time before analyzing it. Never invent the event time."
    };
    let (title, started, elapsed_label, recent_label) = if language.starts_with("zh") {
        ("时间轴", "对话发起", "已跨时长", "最近用户消息")
    } else {
        (
            "Temporal timeline",
            "Conversation started",
            "Elapsed",
            "Recent user messages",
        )
    };
    format!(
        "[{}]\n{}: {} [{}]\n{}: {}\n{}:\n{}\nChapters:\n{}\nEmotion timeline:\n{}\nRelationship timeline:\n{}\nTemporal policy: {}",
        title,
        started,
        temporal_stamp(conversation.created_at),
        temporal_day_part(conversation.created_at, language),
        elapsed_label,
        temporal_duration(elapsed, language),
        recent_label,
        if message_lines.is_empty() {
            "(none)"
        } else {
            message_lines.as_str()
        },
        if chapter_lines.is_empty() {
            "(none)"
        } else {
            chapter_lines.as_str()
        },
        if emotion_lines.is_empty() {
            "(none)"
        } else {
            emotion_lines.as_str()
        },
        if relationship_lines.is_empty() {
            "(none)"
        } else {
            relationship_lines.as_str()
        },
        policy
    )
}

#[derive(Clone)]
pub enum StreamEvent {
    Reasoning(String),
    Text(String),
    ToolCall(String, String, String),
    ToolResult(String, String),
    Error(String),
    Done { conv_id: Uuid, title: String },
    Processing(bool),
    Summarizing { conv_id: Uuid },
    ChaptersUpdated { conv_id: Uuid },
    SummarizeFailed { conv_id: Uuid, error: String },
}

pub type StreamCallback = Arc<dyn Fn(StreamEvent) + Send + Sync + 'static>;

pub struct ChatAgent {
    pub conversations: Arc<RwLock<Vec<Conversation>>>,
    pub selected_conversation_id: Arc<RwLock<Option<Uuid>>>,
    pub is_sending: Arc<RwLock<bool>>,
    pub is_summarizing: Arc<RwLock<bool>>,
    pub cancel_flag: Arc<RwLock<bool>>,
    pub language: Arc<RwLock<String>>,
    pub summary_interval: Arc<RwLock<i32>>,
    pub context_window: Arc<RwLock<i32>>,
    pub response_length: Arc<RwLock<String>>,
    pub conversation_model: Arc<RwLock<String>>,
    pub client: DeepSeekClient,
    pub pipeline: PrePipeline,
    pub archives: Arc<Mutex<Archives>>,
    pub story_memory: Arc<Mutex<StoryMemory>>,
}

impl ChatAgent {
    pub fn new(client: DeepSeekClient, archives: Archives) -> Self {
        let pipeline = PrePipeline::new(client.clone());
        let archives = Arc::new(Mutex::new(archives));

        Self {
            conversations: Arc::new(RwLock::new(Vec::new())),
            selected_conversation_id: Arc::new(RwLock::new(None)),
            is_sending: Arc::new(RwLock::new(false)),
            is_summarizing: Arc::new(RwLock::new(false)),
            cancel_flag: Arc::new(RwLock::new(false)),
            language: Arc::new(RwLock::new("en".to_string())),
            summary_interval: Arc::new(RwLock::new(5)),
            context_window: Arc::new(RwLock::new(60)),
            response_length: Arc::new(RwLock::new("standard".to_string())),
            conversation_model: Arc::new(RwLock::new("flash".to_string())),
            client,
            pipeline,
            archives,
            story_memory: Arc::new(Mutex::new(StoryMemory::new())),
        }
    }

    /// Snapshot state only after callers have released their write guards.
    /// Using Tokio's blocking locks from command futures caused UI commands to
    /// deadlock while saving conversations.
    pub async fn persist_conversations(&self) {
        let convs = self.conversations.read().await.clone();
        let a = self.archives.lock().await;
        a.save_conversations(&convs);
    }

    pub async fn create_conversation(&self, language: &str, mode: &str) -> Uuid {
        let title = if language.starts_with("zh") {
            "新对话"
        } else {
            "New Conversation"
        };
        let mut conv = Conversation::new(title.to_string());
        conv.mode = ConversationMode::from_str(mode);
        let id = conv.id;
        self.conversations.write().await.insert(0, conv);
        *self.selected_conversation_id.write().await = Some(id);
        self.persist_conversations().await;
        id
    }

    pub async fn delete_conversation(&self, id: Uuid) {
        let remaining: Vec<Conversation> = {
            let mut convs = self.conversations.write().await;
            convs.retain(|c| c.id != id);
            let mut selected = self.selected_conversation_id.write().await;
            if *selected == Some(id) {
                *selected = convs.first().map(|c| c.id);
            }
            convs.clone()
        };
        self.persist_conversations().await;
        // Purge archives referencing the deleted conversation (memory,
        // emotions, blindspots, narrative events, orphaned persons) so the
        // retrieval tools cannot surface deleted content.
        self.archives
            .lock()
            .await
            .purge_conversation(id, &remaining);
    }

    /// Remove the intermediate tool-round scaffolding (empty assistant
    /// tool-call entries + role:"tool" results) that the API loop persists
    /// for the next round. The final assistant message carries the complete
    /// answer; leaving the scaffolding in history would render phantom empty
    /// bubbles in the UI and break pair deletion.
    async fn prune_tool_scaffolding(&self, conv_id: Uuid, user_msg_id: Uuid) {
        let mut convs_write = self.conversations.write().await;
        let pruned = if let Some(conv) = convs_write.iter_mut().find(|c| c.id == conv_id) {
            // Nothing to prune when the turn's user message is missing.
            let Some(up) = conv.messages.iter().position(|m| m.id == user_msg_id) else {
                return;
            };
            let tail_start = up + 1;
            if tail_start >= conv.messages.len() {
                return;
            }
            // The final answer is the first assistant message after the user
            // turn with real content and no tool calls.
            let final_pos = (tail_start..conv.messages.len()).find(|&i| {
                let m = &conv.messages[i];
                m.role == ChatRole::assistant
                    && m.tool_calls.is_none()
                    && !m.content.trim().is_empty()
            });
            let end = final_pos.unwrap_or(conv.messages.len());
            // Prune the contiguous run of scaffolding right after the user
            // message (stops at the final answer or at the next user turn).
            let mut prune_end = tail_start;
            while prune_end < end {
                let m = &conv.messages[prune_end];
                let is_scaffold = m.role == ChatRole::tool
                    || (m.role == ChatRole::assistant && m.tool_calls.is_some());
                if !is_scaffold {
                    break;
                }
                prune_end += 1;
            }
            if prune_end > tail_start {
                conv.messages.drain(tail_start..prune_end);
                true
            } else {
                false
            }
        } else {
            false
        };
        drop(convs_write);
        if pruned {
            self.persist_conversations().await;
        }
    }

    pub async fn delete_message_pair(&self, conv_id: Uuid, msg_id: Uuid) {
        let mut convs = self.conversations.write().await;
        if let Some(conv) = convs.iter_mut().find(|c| c.id == conv_id) {
            if let Some(pos) = conv.messages.iter().position(|m| m.id == msg_id) {
                // Pair assistant actions with the preceding user message. The
                // old implementation deleted the *next* user message instead.
                let start = if conv.messages[pos].role == ChatRole::assistant {
                    (0..pos)
                        .rev()
                        .find(|&i| conv.messages[i].role == ChatRole::user)
                        .unwrap_or(pos)
                } else {
                    pos
                };
                // Remove the whole turn: the user message plus every message
                // up to (but not including) the next user message. This also
                // cleans up legacy tool-round scaffolding (empty assistant
                // tool-call entries and role:"tool" results) that older builds
                // persisted — deleting only two messages used to leave the
                // orphaned scaffolding behind ("删不干净").
                let end = (start + 1..conv.messages.len())
                    .find(|&i| conv.messages[i].role == ChatRole::user)
                    .unwrap_or(conv.messages.len());
                let removed_ids: Vec<Uuid> =
                    conv.messages[start..end].iter().map(|m| m.id).collect();
                conv.messages.drain(start..end);
                conv.chapters.retain(|chapter| {
                    !chapter
                        .message_ids
                        .iter()
                        .any(|id| removed_ids.contains(id))
                });
                conv.last_summary_message_index = conv.last_summary_message_index.min(start);
                conv.completed_dialog_count = 0;
                conv.updated_at = chrono::Utc::now();
            }
        }
        drop(convs);
        self.persist_conversations().await;
    }

    pub async fn truncate_conversation(&self, conv_id: Uuid, msg_id: Uuid) -> Result<(), String> {
        let mut convs = self.conversations.write().await;
        let conv = convs
            .iter_mut()
            .find(|c| c.id == conv_id)
            .ok_or("Conversation not found")?;
        let start = conv
            .messages
            .iter()
            .position(|m| m.id == msg_id)
            .ok_or("Message not found")?;
        conv.messages.truncate(start);
        conv.chapters.retain(|chapter| {
            chapter
                .message_ids
                .iter()
                .all(|id| conv.messages.iter().any(|m| m.id == *id))
        });
        conv.last_summary_message_index = conv.last_summary_message_index.min(start);
        conv.completed_dialog_count = 0;
        conv.updated_at = chrono::Utc::now();
        drop(convs);
        self.persist_conversations().await;
        Ok(())
    }

    pub async fn set_mode(&self, conv_id: Uuid, mode: ConversationMode) {
        let mut convs = self.conversations.write().await;
        if let Some(conv) = convs.iter_mut().find(|c| c.id == conv_id) {
            conv.mode = mode;
            conv.updated_at = chrono::Utc::now();
        }
        drop(convs);
        self.persist_conversations().await;
    }

    pub async fn context_usage(&self, conv_id: Uuid) -> Option<ContextUsageSnapshot> {
        let conversation = self
            .conversations
            .read()
            .await
            .iter()
            .find(|conversation| conversation.id == conv_id)
            .cloned()?;
        let language = self.language.read().await.clone();
        let response_length = self.response_length.read().await.clone();
        let reserved_output = ResponseLength::from_str(&response_length).max_tokens() as u64;
        let summary_interval = *self.summary_interval.read().await;

        let mut fixed_tokens = estimate_tokens(&prompts::system_prompt(
            if conversation.mode == ConversationMode::rational {
                "rational"
            } else if conversation.mode == ConversationMode::warm {
                "warm"
            } else {
                "balanced"
            },
            &language,
        ));

        if let Ok(tool_text) = serde_json::to_string(&tools::tool_definitions_json()) {
            fixed_tokens = fixed_tokens.saturating_add(estimate_tokens(&tool_text));
        }
        // Reserve for temporal, story-memory, cross-chat memory and supervisor
        // blocks whose exact size depends on the next draft.
        fixed_tokens = fixed_tokens.saturating_add(512);

        let raw = conversation
            .messages
            .iter()
            .map(estimate_message_tokens)
            .sum::<u64>();
        let uncompressed_messages = if conversation.chapters.is_empty() {
            conversation
                .messages
                .iter()
                .map(message_for_model)
                .collect::<Vec<_>>()
        } else {
            let mut messages = windowed_conversation_messages(&conversation, 0);
            if raw >= CONTEXT_COMPRESSION_TOKENS {
                // Reconstruct the uncompressed side of the comparison while
                // preserving the same chapter-index overhead.
                messages.truncate(1);
                messages.extend(conversation.messages.iter().map(message_for_model));
            }
            messages
        };
        let uncompressed = fixed_tokens.saturating_add(
            uncompressed_messages
                .iter()
                .map(estimate_prepared_message_tokens)
                .sum::<u64>(),
        );
        let estimated = fixed_tokens.saturating_add(
            windowed_conversation_messages(&conversation, 0)
                .iter()
                .map(estimate_prepared_message_tokens)
                .sum::<u64>(),
        );
        let dialogs_until_summary = if summary_interval <= 0 {
            0
        } else {
            (summary_interval - conversation.completed_dialog_count).max(0)
        };

        Some(ContextUsageSnapshot {
            estimated_tokens: estimated,
            uncompressed_estimated_tokens: uncompressed,
            raw_conversation_tokens: raw,
            capacity_tokens: CONTEXT_CAPACITY_TOKENS,
            reserved_output_tokens: reserved_output,
            message_count: conversation.messages.len(),
            preparation_threshold_tokens: CONTEXT_PREPARATION_TOKENS,
            compression_threshold_tokens: CONTEXT_COMPRESSION_TOKENS,
            critical_threshold_tokens: CONTEXT_CRITICAL_TOKENS,
            retained_recent_tokens: if raw >= CONTEXT_CRITICAL_TOKENS {
                CRITICAL_RETAINED_RECENT_TOKENS
            } else {
                RETAINED_RECENT_TOKENS
            },
            tokens_until_preparation: CONTEXT_PREPARATION_TOKENS.saturating_sub(raw),
            tokens_until_compression: CONTEXT_COMPRESSION_TOKENS.saturating_sub(raw),
            preparation_active: raw >= CONTEXT_PREPARATION_TOKENS,
            compression_active: raw >= CONTEXT_COMPRESSION_TOKENS,
            critical: raw >= CONTEXT_CRITICAL_TOKENS,
            summary_interval,
            dialogs_until_summary,
        })
    }

    pub fn selected_conversation(&self) -> Option<Conversation> {
        let id = *self.selected_conversation_id.blocking_read();
        let convs = self.conversations.blocking_read();
        id.and_then(|id| convs.iter().find(|c| c.id == id).cloned())
    }

    pub async fn send_message(
        &self,
        conv_id: Uuid,
        text: &str,
        attachments: Vec<ChatAttachment>,
        callback: StreamCallback,
    ) -> Result<(), String> {
        *self.is_sending.write().await = true;
        *self.cancel_flag.write().await = false;
        callback(StreamEvent::Processing(true));

        let result = self
            .send_message_inner(conv_id, text, attachments, callback.clone())
            .await;

        *self.is_sending.write().await = false;
        callback(StreamEvent::Processing(false));
        result
    }

    async fn send_message_inner(
        &self,
        conv_id: Uuid,
        text: &str,
        attachments: Vec<ChatAttachment>,
        callback: StreamCallback,
    ) -> Result<(), String> {
        let effective_text = if text.trim().is_empty() && !attachments.is_empty() {
            "请分析我上传的附件。"
        } else {
            text
        };
        let (mode, lang, has_completed_turn) = {
            let convs = self.conversations.read().await;
            let conv = convs
                .iter()
                .find(|c| c.id == conv_id)
                .ok_or("Conversation not found")?;
            (
                conv.mode.clone(),
                self.language.read().await.clone(),
                conv.messages.iter().any(|message| {
                    message.role == ChatRole::assistant && !message.content.trim().is_empty()
                }),
            )
        };

        // Match the Swift pipeline: ingest the user turn into local chapter
        // memory before any model call. This makes chapters useful immediately
        // and gives the current request a deterministic memory context even
        // when API summarization is delayed or unavailable.
        let request_sent_at = Utc::now();
        let attachment_note = if attachments.is_empty() {
            String::new()
        } else {
            format!(
                "\n\n{}",
                attachments
                    .iter()
                    .map(|attachment| format!("[附件：{}]", attachment.file_name))
                    .collect::<Vec<_>>()
                    .join("\n")
            )
        };
        let mut user_msg = ChatMessage::new(ChatRole::user, format!("{}{}", effective_text, attachment_note));
        user_msg.attachments = attachments;
        user_msg.created_at = request_sent_at;
        let user_msg_id = user_msg.id;
        {
            let mut convs = self.conversations.write().await;
            if let Some(conv) = convs.iter_mut().find(|c| c.id == conv_id) {
                let msg_id = user_msg.id;
                conv.messages.push(user_msg);
                StoryMemory::ingest(effective_text, msg_id, conv);
                if conv.title == "新对话" || conv.title == "New Conversation" {
                    let compact = effective_text
                        .replace('\n', " ")
                        .split_whitespace()
                        .collect::<Vec<_>>()
                        .join(" ");
                    let title = compact.chars().take(22).collect::<String>();
                    if !title.is_empty() {
                        conv.title = if compact.chars().count() > 22 {
                            format!("{}...", title)
                        } else {
                            title
                        };
                    }
                }
                conv.updated_at = request_sent_at;
            }
        }
        self.persist_conversations().await;

        // Step 1: Pre-pipeline (guard + emotion/person extraction). Run this
        // even on the first and shortest turns: urgent messages can be only a
        // few characters long, so skipping the safety pass is not acceptable.
        let pre_context = self.pre_pipeline_context(conv_id).await;
        let guard = self
            .pipeline
            .run(conv_id, effective_text, &mode, &lang, &pre_context, request_sent_at)
            .await?;

        // Safety check must fail closed into an explicit confirmation rather
        // than silently continuing with relationship analysis.
        if guard.safety_uncertain {
            let uncertainty_response = if lang.starts_with("zh") {
                "我暂时无法可靠完成安全判断，所以先不做关系分析。如果你现在有自伤、伤人、暴力、胁迫或无法离开的风险，请先联系当地急救服务、可信任的人或最近的急诊。你现在是否处于安全环境？"
            } else {
                "I could not reliably complete the safety check, so I will pause relationship analysis for now. If there is any risk of self-harm, harm to others, violence, coercion, or being unable to leave, contact local emergency services, someone you trust, or the nearest emergency department. Are you currently in a safe place?"
            };
            callback(StreamEvent::Text(uncertainty_response.to_string()));
            callback(StreamEvent::Done {
                conv_id,
                title: String::new(),
            });
            return Ok(());
        }

        // Safety crisis check
        if guard.safety_crisis {
            let immediate_help = if guard.crisis_hotline.trim().is_empty() {
                if lang.starts_with("zh") {
                    "当地急救服务、可信任的人或最近的急诊"
                } else {
                    "local emergency services, someone you trust, or the nearest emergency department"
                }
            } else {
                guard.crisis_hotline.as_str()
            };
            let crisis_response = if lang.starts_with("zh") {
                format!(
                    "我注意到你正在经历一些非常困难的时刻。\n\n{}\n\n如果你需要立即帮助，请联系：{}",
                    guard.crisis_detail, immediate_help
                )
            } else {
                format!(
                    "I notice you're going through a very difficult time.\n\n{}\n\nIf you need immediate help, please contact: {}",
                    guard.crisis_detail, immediate_help
                )
            };

            callback(StreamEvent::Text(crisis_response));
            callback(StreamEvent::Done {
                conv_id,
                title: String::new(),
            });
            return Ok(());
        }

        // Store extracted emotion/person/blindspot archives. These records are
        // fed back only to the current conversation; cross-conversation recall
        // remains an explicit search_memory tool call.
        {
            let archives = self.archives.lock().await;
            for emotion in &guard.emotions {
                archives.add_emotion(emotion);
            }
            for person in &guard.persons {
                archives.save_person(person);
            }
            for spot in &guard.blindspots {
                archives.add_blindspot(spot);
            }
        }

        // Step 2: Build context and system prompt
        let context = {
            let convs = self.conversations.read().await;
            let conv = convs.iter().find(|c| c.id == conv_id).unwrap();
            let mut memory = self.story_memory.lock().await;
            memory.build_context(conv, effective_text, &lang)
        };
        let temporal_archives = {
            let archives = self.archives.lock().await;
            (
                archives.get_recent_emotions_for_conversation(conv_id, 5),
                archives.all_persons(),
            )
        };
        let temporal = {
            let convs = self.conversations.read().await;
            let conv = convs.iter().find(|c| c.id == conv_id).unwrap();
            temporal_context(
                conv,
                request_sent_at,
                &lang,
                &temporal_archives.0,
                &temporal_archives.1,
            )
        };
        let supervisor_hint = if guard.raw_warnings.is_empty() {
            String::new()
        } else {
            format!(
                "\n\n[Supervisor Note]\nThe following patterns were detected in the user's message. Consider them in your response:\n- {}",
                guard.raw_warnings.join("\n- ")
            )
        };

        // Keep the system prefix stable for DeepSeek's prefix cache. The
        // per-turn context is appended to the current user message below;
        // putting it before the transcript would invalidate the cache prefix
        // on every request.
        let system_prompt = prompts::system_prompt(
            if mode == ConversationMode::rational {
                "rational"
            } else if mode == ConversationMode::warm {
                "warm"
            } else {
                "balanced"
            },
            &lang,
        );
        let dynamic_context = format!(
            "{}\n\n## Current conversation context\n{}\n{}",
            temporal, context, supervisor_hint,
        );

        // Step 3: Main model loop with tool calls (up to 3 rounds)
        // DeepSeek supports parallel function calls in one response. Keep a
        // second round for dependent fetches, but cap the loop before tool
        // calls can multiply reasoning and completion tokens.
        // The loop below is inclusive, so 1 means at most two API rounds.
        let max_tool_rounds = 1;

        for round in 0..=max_tool_rounds {
            if *self.cancel_flag.read().await {
                return Err("Cancelled".to_string());
            }

            let mut messages = vec![ChatMessage::new(ChatRole::system, system_prompt.clone())];

            // Build conversation history with context windowing
            {
                let convs = self.conversations.read().await;
                if let Some(conv) = convs.iter().find(|c| c.id == conv_id) {
                    let global_offset = convs
                        .iter()
                        .take_while(|candidate| candidate.id != conv_id)
                        .map(|candidate| candidate.chapters.len())
                        .sum::<usize>();
                    messages.extend(windowed_conversation_messages(conv, global_offset));
                }
            }

            if let Some(user_message) = messages
                .iter_mut()
                .rev()
                .find(|message| message.role == ChatRole::user)
            {
                user_message.content.push_str("\n\n[Prism context]\n");
                user_message.content.push_str(&dynamic_context);
            }

            let response_length = self.response_length.read().await.clone();
            let max_tokens = ResponseLength::from_str(&response_length).max_tokens();

            // Stream the response
            let mode_clone = mode.clone();
            // Accumulate reasoning and content for tool checking
            // Stream callbacks are synchronous closures invoked from the
            // async HTTP task. Use a short-lived std mutex here; Tokio's
            // blocking_lock() is forbidden inside a runtime worker and was
            // preventing streamed responses from reaching the UI.
            let accumulated_reasoning = Arc::new(StdMutex::new(String::new()));
            let accumulated_content = Arc::new(StdMutex::new(String::new()));
            let tool_calls_received =
                Arc::new(StdMutex::new(Vec::<(String, String, String)>::new()));

            let acc_reason = accumulated_reasoning.clone();
            let acc_content = accumulated_content.clone();
            let tc_received = tool_calls_received.clone();
            let acc_reason2 = accumulated_reasoning.clone();
            let acc_content2 = accumulated_content.clone();
            let cb2 = callback.clone();
            let cb3 = callback.clone();
            let tool_defs = if round == 0 && !has_completed_turn {
                // A first turn has no useful retrieval context, but may still
                // establish a narrated period that belongs on the timeline.
                Some(tools::narrative_timeline_tool_json())
            } else {
                Some(tools::tool_definitions_json())
            };
            let selected_model = self.conversation_model.read().await.clone();
            let model_name = if selected_model.eq_ignore_ascii_case("pro") {
                self.client.pro_model().await
            } else {
                self.client.flash_model().await
            };

            let stream_result = self
                .client
                .stream_complete(
                    // Flash is the default conversation model, while Settings
                    // can opt into Pro for normal turns without changing the
                    // auxiliary memory/chapter calls.
                    &model_name,
                    messages,
                    mode_clone.temperature(),
                    mode_clone.top_p(),
                    max_tokens,
                    None,
                    tool_defs,
                    move |reasoning| {
                        if let Ok(mut value) = acc_reason.lock() {
                            *value += &reasoning;
                        }
                        cb2(StreamEvent::Reasoning(reasoning));
                    },
                    move |content| {
                        if let Ok(mut value) = acc_content.lock() {
                            *value += &content;
                        }
                        cb3(StreamEvent::Text(content));
                    },
                    move |id, name, args| {
                        if let Ok(mut calls) = tc_received.lock() {
                            // Tool-call arguments arrive as multiple SSE
                            // deltas. Coalesce by id (and use the most recent
                            // active call for id-less continuation chunks)
                            // before parsing/executing the call.
                            if let Some(existing) =
                                calls.iter_mut().find(|call| call.0 == id && !id.is_empty())
                            {
                                if !name.is_empty() {
                                    existing.1 = name;
                                }
                                existing.2.push_str(&args);
                            } else if id.is_empty() {
                                if let Some(existing) = calls.last_mut() {
                                    if !name.is_empty() {
                                        existing.1 = name;
                                    }
                                    existing.2.push_str(&args);
                                }
                            } else {
                                calls.push((id, name, args));
                            }
                        }
                    },
                    // A stream can be an intermediate tool-call round. The
                    // agent emits Done only after the final answer is saved.
                    || {},
                )
                .await;

            match stream_result {
                Ok(()) => {
                    // Check if tool calls were received
                    let tcs = tool_calls_received
                        .lock()
                        .map(|calls| calls.clone())
                        .unwrap_or_default();
                    if tcs.is_empty() {
                        // No tool calls - we're done; save final assistant message
                        let final_reasoning = acc_reason2
                            .lock()
                            .map(|value| value.clone())
                            .unwrap_or_default();
                        let final_content = acc_content2
                            .lock()
                            .map(|value| value.clone())
                            .unwrap_or_default();
                        let mut convs_write = self.conversations.write().await;
                        if let Some(conv) = convs_write.iter_mut().find(|c| c.id == conv_id) {
                            conv.messages.push(ChatMessage {
                                id: Uuid::new_v4(),
                                role: ChatRole::assistant,
                                content: final_content,
                                reasoning: Some(final_reasoning),
                                tool_calls: None,
                                tool_call_id: None,
                                created_at: chrono::Utc::now(),
                                suggestions: Vec::new(),
                                attachments: Vec::new(),
                            });
                            conv.completed_dialog_count += 1;
                            conv.updated_at = chrono::Utc::now();
                            if conv
                                .messages
                                .iter()
                                .filter(|message| message.role == ChatRole::user)
                                .count()
                                == 1
                            {
                                let title: String = effective_text.chars().take(25).collect();
                                conv.title = if title.len() > 22 {
                                    format!("{}...", &title[..22])
                                } else {
                                    title
                                };
                            }
                        }
                        drop(convs_write);
                        self.persist_conversations().await;
                        callback(StreamEvent::Done {
                            conv_id,
                            title: String::new(),
                        });
                        break;
                    }

                    if round >= max_tool_rounds {
                        // Let the common completion path below emit exactly
                        // one Done event after the final tool round.
                        break;
                    }

                    // Execute tool calls
                    for (tool_id, tool_name, tool_args_str) in &tcs {
                        if *self.cancel_flag.read().await {
                            self.prune_tool_scaffolding(conv_id, user_msg_id).await;
                            return Err("Cancelled".to_string());
                        }

                        callback(StreamEvent::ToolCall(
                            tool_name.clone(),
                            tool_args_str.clone(),
                            tool_id.clone(),
                        ));

                        let args: Value =
                            serde_json::from_str(tool_args_str).unwrap_or(Value::Null);
                        let conversation_snapshot = self.conversations.read().await.clone();
                        let archives_lock = self.archives.lock().await;
                        let result = tools::execute_tool(
                            tool_name,
                            &args,
                            &archives_lock,
                            &conversation_snapshot,
                            conv_id,
                        )
                        .await
                        .unwrap_or(serde_json::json!({"error": "Tool execution failed"}));
                        drop(archives_lock);

                        let result_str = serde_json::to_string(&result).unwrap_or_default();
                        callback(StreamEvent::ToolResult(
                            tool_name.clone(),
                            result_str.clone(),
                        ));

                        // Add tool call and result to the conversation
                        let mut convs_write = self.conversations.write().await;
                        if let Some(conv) = convs_write.iter_mut().find(|c| c.id == conv_id) {
                            conv.messages.push(ChatMessage {
                                id: Uuid::new_v4(),
                                role: ChatRole::assistant,
                                content: String::new(),
                                reasoning: Some(
                                    accumulated_reasoning
                                        .lock()
                                        .map(|value| value.clone())
                                        .unwrap_or_default(),
                                ),
                                tool_calls: Some(vec![ToolCall {
                                    id: tool_id.clone(),
                                    name: tool_name.clone(),
                                    arguments: tool_args_str.clone(),
                                }]),
                                tool_call_id: None,
                                created_at: chrono::Utc::now(),
                                suggestions: Vec::new(),
                                attachments: Vec::new(),
                            });
                            conv.messages.push(ChatMessage {
                                id: Uuid::new_v4(),
                                role: ChatRole::tool,
                                content: format!("Tool result for {}: {}", tool_name, result_str),
                                reasoning: None,
                                tool_calls: None,
                                tool_call_id: Some(tool_id.clone()),
                                created_at: chrono::Utc::now(),
                                suggestions: Vec::new(),
                                attachments: Vec::new(),
                            });
                        }
                    }
                }
                Err(e) => {
                    callback(StreamEvent::Error(e.clone()));
                    self.prune_tool_scaffolding(conv_id, user_msg_id).await;
                    return Err(e);
                }
            }
        }

        // Prune tool-round scaffolding from history so the UI shows exactly
        // one assistant reply per user turn and pair deletion removes the
        // whole turn cleanly (the Swift version never persists scaffolding).
        self.prune_tool_scaffolding(conv_id, user_msg_id).await;

        // Step 5: Trigger summarization if needed
        let summary_interval = *self.summary_interval.read().await;
        let should_summarize = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|c| c.id == conv_id)
                .map(|c| c.completed_dialog_count >= summary_interval && summary_interval > 0)
                .unwrap_or(false)
        };

        if should_summarize {
            callback(StreamEvent::Summarizing { conv_id });
            let should_full_rescan = {
                let convs = self.conversations.read().await;
                convs
                    .iter()
                    .find(|conversation| conversation.id == conv_id)
                    .map(|conversation| conversation.incremental_chapter_count >= 3)
                    .unwrap_or(false)
            };
            let summary_result = if should_full_rescan {
                self.full_re_summarize(conv_id, &lang).await
            } else {
                self.summarize_conversation(conv_id, &lang).await
            };
            match summary_result {
                Ok(()) => callback(StreamEvent::ChaptersUpdated { conv_id }),
                Err(error) => {
                    log::error!("Automatic chapter summarization failed: {}", error);
                    callback(StreamEvent::SummarizeFailed { conv_id, error });
                }
            }
        }

        // Done
        let title = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|c| c.id == conv_id)
                .map(|c| c.title.clone())
                .unwrap_or_default()
        };
        callback(StreamEvent::Done { conv_id, title });

        Ok(())
    }

    #[allow(dead_code)]
    async fn rerank_tool_result(
        &self,
        tool_name: &str,
        query: &str,
        limit: usize,
        result: Value,
        language: &str,
    ) -> Value {
        let (candidates, wrap_object) = if tool_name == "search_chapters" {
            (
                result["results"].as_array().cloned().unwrap_or_default(),
                true,
            )
        } else {
            (result.as_array().cloned().unwrap_or_default(), false)
        };
        if candidates.len() <= 2 {
            return result;
        }

        let candidate_lines = candidates
            .iter()
            .enumerate()
            .map(|(index, candidate)| {
                let title = candidate["title"]
                    .as_str()
                    .or_else(|| candidate["sourceChapter"].as_str())
                    .unwrap_or("");
                let summary = candidate["summary"]
                    .as_str()
                    .or_else(|| candidate["content"].as_str())
                    .unwrap_or("");
                format!(
                    "[{}] {} — {}",
                    index,
                    title,
                    summary.chars().take(160).collect::<String>()
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        let messages = vec![
            ChatMessage::new(ChatRole::system, prompts::search_reranker_prompt(language)),
            ChatMessage::new(
                ChatRole::user,
                format!("查询: {}\n\n候选项:\n{}", query, candidate_lines),
            ),
        ];
        let raw = match self
            .client
            .complete_without_thinking(&self.client.flash_model().await, messages, 0.0, 0.8, 256)
            .await
        {
            Ok(raw) => raw,
            Err(error) => {
                log::warn!("semantic reranker unavailable: {}", error);
                return result;
            }
        };
        let cleaned = raw
            .trim()
            .strip_prefix("```json")
            .or_else(|| raw.trim().strip_prefix("```"))
            .unwrap_or(raw.trim())
            .trim_end_matches("```")
            .trim();
        let Some(start) = cleaned.find('[') else {
            return result;
        };
        let Some(end) = cleaned.rfind(']') else {
            return result;
        };
        let Ok(indices) = serde_json::from_str::<Vec<usize>>(&cleaned[start..=end]) else {
            return result;
        };
        let reordered = indices
            .into_iter()
            .filter_map(|index| candidates.get(index).cloned())
            .take(limit.max(1))
            .collect::<Vec<_>>();
        if wrap_object {
            let mut object = result;
            object["results"] = Value::Array(reordered);
            object
        } else {
            Value::Array(reordered)
        }
    }

    async fn pre_pipeline_context(&self, conv_id: Uuid) -> String {
        let history = {
            let conversations = self.conversations.read().await;
            conversations
                .iter()
                .find(|conversation| conversation.id == conv_id)
                .map(|conversation| {
                    conversation
                        .messages
                        .iter()
                        .filter(|message| {
                            message.role == ChatRole::user || message.role == ChatRole::assistant
                        })
                        .rev()
                        .take(10)
                        .collect::<Vec<_>>()
                        .into_iter()
                        .rev()
                        .map(|message| {
                            let role = if message.role == ChatRole::user {
                                "用户"
                            } else {
                                "助手"
                            };
                            format!(
                                "[{}][sentAt={}] {}",
                                role,
                                message.created_at.to_rfc3339(),
                                message.content.chars().take(500).collect::<String>()
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("\n")
                })
                .unwrap_or_default()
        };
        let archives = self.archives.lock().await;
        let known_persons = archives
            .all_persons()
            .into_iter()
            .filter(|person| {
                person
                    .conversation_ids
                    .as_ref()
                    .map(|ids| ids.contains(&conv_id))
                    .unwrap_or(false)
            })
            .take(20)
            .map(|person| format!("{}({})", person.name, person.role))
            .collect::<Vec<_>>()
            .join(", ");
        let historical_blindspots = archives
            .recent_blindspots(20)
            .into_iter()
            .filter(|spot| spot.conversation_id == conv_id)
            .map(|spot| {
                format!(
                    "- [暂定-{}] {}: {}",
                    spot.severity, spot.pattern, spot.evidence
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        format!(
            "{}\n\n当前对话人物：{}\n\n待验证的叙事模式假设（不是事实或人格标签）：\n{}",
            history,
            if known_persons.is_empty() {
                "（无）"
            } else {
                &known_persons
            },
            if historical_blindspots.is_empty() {
                "（无）"
            } else {
                &historical_blindspots
            }
        )
    }

    pub async fn summarize_conversation(
        &self,
        conv_id: Uuid,
        language: &str,
    ) -> Result<(), String> {
        *self.is_summarizing.write().await = true;

        let messages = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|c| c.id == conv_id)
                .map(|c| c.messages.clone())
                .unwrap_or_default()
        };

        let last_idx = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|c| c.id == conv_id)
                .map(|c| c.last_summary_message_index)
                .unwrap_or(0)
        };

        let new_messages: Vec<ChatMessage> = messages
            .iter()
            .skip(last_idx)
            .filter(|m| m.role == ChatRole::user || m.role == ChatRole::assistant)
            .cloned()
            .collect();

        if new_messages.is_empty() {
            *self.is_summarizing.write().await = false;
            return Ok(());
        }

        let previous_chapters = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|conversation| conversation.id == conv_id)
                .map(|conversation| {
                    conversation
                        .chapters
                        .iter()
                        .rev()
                        .take(3)
                        .map(|chapter| {
                            format!(
                                "- {}: {}",
                                chapter.title,
                                chapter.summary.chars().take(160).collect::<String>()
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("\n")
                })
                .unwrap_or_default()
        };
        let summary_prompt = if previous_chapters.is_empty() {
            prompts::summarization_prompt(language).to_string()
        } else {
            format!(
                "{}\n\n前序章节（不要重复这些内容）：\n{}",
                prompts::summarization_prompt(language),
                previous_chapters
            )
        };
        let transcript = new_messages
            .iter()
            .map(|message| {
                let role = if message.role == ChatRole::user {
                    "User"
                } else {
                    "Assistant"
                };
                format!(
                    "[{}][sentAt={}]: {}",
                    role,
                    message.created_at.to_rfc3339(),
                    message.content
                )
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        let api_msgs = vec![
            ChatMessage::new(ChatRole::system, summary_prompt),
            ChatMessage::new(ChatRole::user, format!("对话片段：\n\n{}", transcript)),
        ];

        let result = self
            .client
            .complete_without_thinking(&self.client.flash_model().await, api_msgs, 0.3, 0.9, 512)
            .await;
        let result = match result {
            Ok(result) => result,
            Err(error) => {
                *self.is_summarizing.write().await = false;
                return Err(error);
            }
        };

        let parsed = parse_json_object(&result);
        if parsed.is_none() {
            // A response that starts with a JSON opening brace/bracket is a
            // truncated or malformed JSON attempt — NOT a plain-text summary.
            // Refuse to create a garbage chapter; fail this run so the next
            // auto-trigger retries cleanly (previously a truncated provider
            // response produced a permanent "Chapter" entry with raw JSON as
            // its summary, which made the sidebar look broken).
            let trimmed = result.trim_start();
            if trimmed.starts_with('{') || trimmed.starts_with('[') {
                *self.is_summarizing.write().await = false;
                return Err(
                    "Chapter summarizer returned truncated/invalid JSON; will retry next trigger"
                        .to_string(),
                );
            }
            // Models occasionally return a plain-text summary despite the
            // JSON instruction. Preserve that useful output instead of
            // silently dropping the chapter and making the sidebar appear
            // broken.
            log::warn!("Chapter summarizer returned non-JSON; using text fallback");
        }
        let title = parsed
            .as_ref()
            .and_then(|value| value["title"].as_str())
            .unwrap_or("Chapter")
            .trim()
            .to_string();
        let summary = parsed
            .as_ref()
            .and_then(|value| value["summary"].as_str())
            .map(str::to_string)
            .map(|value| value.chars().take(320).collect())
            .unwrap_or_else(|| result.trim().chars().take(320).collect());
        let keywords = parsed
            .as_ref()
            .and_then(|value| value["keywords"].as_array())
            .map(|values| {
                values
                    .iter()
                    .filter_map(|value| value.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        let chapter = StoryChapter {
            id: Uuid::new_v4(),
            title: if title.is_empty() {
                "Chapter".to_string()
            } else {
                title
            },
            summary,
            keywords,
            message_ids: messages[last_idx..].iter().map(|m| m.id).collect(),
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };

        let memory_entry = {
            let convs = self.conversations.read().await;
            let messages = convs
                .iter()
                .find(|conversation| conversation.id == conv_id)
                .map(|conversation| conversation.messages.clone())
                .unwrap_or_default();
            self.story_memory
                .lock()
                .await
                .extract_memory_entry(&chapter, conv_id, &messages)
        };
        let mut convs = self.conversations.write().await;
        if let Some(conv) = convs.iter_mut().find(|c| c.id == conv_id) {
            conv.chapters.push(chapter);
            conv.last_summary_message_index = messages.len();
            conv.completed_dialog_count = 0;
            conv.incremental_chapter_count += 1;
            conv.last_summarized_at = Some(chrono::Utc::now());
        }
        drop(convs);
        self.archives.lock().await.add_memory(&memory_entry);
        self.persist_conversations().await;
        self.update_conversation_title(conv_id, language).await;

        *self.is_summarizing.write().await = false;
        Ok(())
    }

    pub async fn full_re_summarize(&self, conv_id: Uuid, language: &str) -> Result<(), String> {
        *self.is_summarizing.write().await = true;

        let messages = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|c| c.id == conv_id)
                .map(|c| c.messages.clone())
                .unwrap_or_default()
        };

        let indexed_messages: Vec<(usize, ChatMessage)> = messages
            .iter()
            .filter(|message| message.role == ChatRole::user || message.role == ChatRole::assistant)
            .cloned()
            .enumerate()
            .map(|(index, message)| (index, message))
            .collect();
        if indexed_messages.is_empty() {
            *self.is_summarizing.write().await = false;
            return Ok(());
        }

        let transcript = indexed_messages
            .iter()
            .map(|(index, message)| {
                let role = if message.role == ChatRole::user {
                    "User"
                } else {
                    "Assistant"
                };
                format!(
                    "[{}][{}][sentAt={}]: {}",
                    index + 1,
                    role,
                    message.created_at.to_rfc3339(),
                    message.content
                )
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        let archive_context = self.build_archive_context(conv_id).await;
        let system_msg = ChatMessage::new(
            ChatRole::system,
            prompts::full_summarization_prompt(language),
        );
        let user_msg = ChatMessage::new(
            ChatRole::user,
            format!("{}完整对话记录：\n\n{}", archive_context, transcript),
        );

        let result = self
            .client
            .complete_without_thinking(
                &self.client.flash_model().await,
                vec![system_msg, user_msg],
                0.3,
                0.9,
                8192,
            )
            .await;
        let result = match result {
            Ok(result) => result,
            Err(error) => {
                *self.is_summarizing.write().await = false;
                return Err(error);
            }
        };

        let mut chapters = parse_chapter_array(&result, &indexed_messages);
        if chapters.is_empty() {
            // Same guard as the incremental path: a response that opens with
            // `[` or `{` but fails to parse is a truncated JSON attempt.
            // Fail instead of storing the raw fragment as a single chapter.
            let trimmed = result.trim_start();
            if trimmed.starts_with('[') || trimmed.starts_with('{') {
                *self.is_summarizing.write().await = false;
                return Err(
                    "Full re-summarizer returned truncated/invalid JSON; will retry next trigger"
                        .to_string(),
                );
            }
            // Preserve a usable chapter when a provider returns plain text or
            // a single object despite the full-scan JSON-array instruction.
            let fallback = parse_json_object(&result);
            let title = fallback
                .as_ref()
                .and_then(|value| value["title"].as_str())
                .unwrap_or("Chapter")
                .to_string();
            let summary = fallback
                .as_ref()
                .and_then(|value| value["summary"].as_str())
                .unwrap_or(result.trim())
                .chars()
                .take(320)
                .collect::<String>();
            let keywords = fallback
                .as_ref()
                .and_then(|value| value["keywords"].as_array())
                .map(|values| {
                    values
                        .iter()
                        .filter_map(|value| value.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            chapters.push(StoryChapter {
                id: Uuid::new_v4(),
                title,
                summary,
                keywords,
                message_ids: indexed_messages
                    .iter()
                    .map(|(_, message)| message.id)
                    .collect(),
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            });
        }

        let memory_entries = {
            let messages = messages.clone();
            let memory = self.story_memory.lock().await;
            chapters
                .iter()
                .map(|chapter| memory.extract_memory_entry(chapter, conv_id, &messages))
                .collect::<Vec<_>>()
        };
        {
            let mut convs = self.conversations.write().await;
            if let Some(conv) = convs.iter_mut().find(|c| c.id == conv_id) {
                conv.chapters = chapters;
                conv.last_summary_message_index = messages.len();
                conv.completed_dialog_count = 0;
                conv.incremental_chapter_count = 0;
                conv.last_summarized_at = Some(chrono::Utc::now());
            }
        }
        {
            let archives = self.archives.lock().await;
            for entry in &memory_entries {
                archives.add_memory(entry);
            }
        }
        self.persist_conversations().await;
        self.update_conversation_title(conv_id, language).await;

        *self.is_summarizing.write().await = false;
        Ok(())
    }

    async fn build_archive_context(&self, conv_id: Uuid) -> String {
        let archives = self.archives.lock().await;
        let emotions = archives.get_recent_emotions_for_conversation(conv_id, 5);
        let mut persons = archives
            .all_persons()
            .into_iter()
            .filter(|person| {
                person.mention_count > 0
                    && person
                        .conversation_ids
                        .as_ref()
                        .map(|ids| ids.contains(&conv_id))
                        .unwrap_or(false)
            })
            .collect::<Vec<_>>();
        persons.sort_by(|left, right| right.mention_count.cmp(&left.mention_count));
        persons.truncate(5);
        let blindspots = archives.recent_blindspots(5);
        let mut parts = Vec::new();
        if !emotions.is_empty() {
            parts.push(format!(
                "近期情绪轨迹: {}",
                emotions
                    .iter()
                    .map(|emotion| {
                        let confidence = emotion
                            .confidence
                            .map(|value| format!(",c={:.1}", value))
                            .unwrap_or_default();
                        format!(
                            "{}({:.1}{})",
                            emotion.emotion, emotion.intensity, confidence
                        )
                    })
                    .collect::<Vec<_>>()
                    .join(" → ")
            ));
        }
        if !persons.is_empty() {
            parts.push(format!(
                "关键人物: {}",
                persons
                    .iter()
                    .map(|person| format!("{}({})", person.name, person.role))
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
        let relevant_blindspots = blindspots
            .iter()
            .filter(|blindspot| blindspot.conversation_id == conv_id)
            .map(|blindspot| {
                format!(
                    "- [暂定-{}] {}: {}",
                    blindspot.severity, blindspot.pattern, blindspot.evidence
                )
            })
            .collect::<Vec<_>>();
        if !relevant_blindspots.is_empty() {
            parts.push(format!(
                "待验证的叙事模式假设（不是事实或人格标签）:\n{}",
                relevant_blindspots.join("\n")
            ));
        }
        if parts.is_empty() {
            String::new()
        } else {
            format!(
                "[对话分析上下文 — 来自质量守护系统的洞察]\n{}\n\n",
                parts.join("\n\n")
            )
        }
    }

    async fn update_conversation_title(&self, conv_id: Uuid, language: &str) {
        let chapter_summaries = {
            let convs = self.conversations.read().await;
            convs
                .iter()
                .find(|conversation| conversation.id == conv_id)
                .map(|conversation| {
                    conversation
                        .chapters
                        .iter()
                        .enumerate()
                        .map(|(index, chapter)| {
                            format!(
                                "第{}章「{}」：{}",
                                index + 1,
                                chapter.title,
                                chapter.summary.chars().take(240).collect::<String>()
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("\n\n")
                })
                .unwrap_or_default()
        };
        if chapter_summaries.is_empty() {
            return;
        }
        let response = self
            .client
            .complete_without_thinking(
                &self.client.flash_model().await,
                vec![
                    ChatMessage::new(ChatRole::system, prompts::title_update_prompt(language)),
                    ChatMessage::new(
                        ChatRole::user,
                        format!("以下是全部章节摘要：\n\n{}", chapter_summaries),
                    ),
                ],
                0.2,
                0.8,
                128,
            )
            .await;
        let Ok(title) = response else {
            return;
        };
        let title = title
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .chars()
            .take(40)
            .collect::<String>();
        if title.is_empty() {
            return;
        }
        let mut convs = self.conversations.write().await;
        if let Some(conv) = convs
            .iter_mut()
            .find(|conversation| conversation.id == conv_id)
        {
            conv.title = title;
            conv.updated_at = chrono::Utc::now();
        }
        drop(convs);
        self.persist_conversations().await;
    }

    pub async fn cancel(&self) {
        *self.cancel_flag.write().await = true;
    }

    pub async fn list_conversations(&self) -> Vec<Conversation> {
        self.conversations.read().await.clone()
    }

    pub async fn get_conversation(&self, id: Uuid) -> Option<Conversation> {
        self.conversations
            .read()
            .await
            .iter()
            .find(|c| c.id == id)
            .cloned()
    }

    pub async fn get_chapter_messages(
        &self,
        conv_id: Uuid,
        chapter_index: usize,
    ) -> Vec<ChatMessage> {
        let convs = self.conversations.read().await;
        if let Some(conv) = convs.iter().find(|c| c.id == conv_id) {
            if let Some(chapter) = conv.chapters.get(chapter_index) {
                return conv
                    .messages
                    .iter()
                    .filter(|m| chapter.message_ids.contains(&m.id))
                    .cloned()
                    .collect();
            }
        }
        vec![]
    }

    pub async fn search_chapters(&self, conv_id: Uuid, query: &str) -> Vec<StoryChapter> {
        let convs = self.conversations.read().await;
        let q = query.to_lowercase();
        let terms = crate::search_expander::SearchExpander::default().terms(&q);
        if let Some(conv) = convs.iter().find(|c| c.id == conv_id) {
            let mut scored = conv
                .chapters
                .iter()
                .filter_map(|ch| {
                    let title = ch.title.to_lowercase();
                    let summary = ch.summary.to_lowercase();
                    let keywords = ch
                        .keywords
                        .iter()
                        .map(|keyword| keyword.to_lowercase())
                        .collect::<Vec<_>>();
                    let mut score = 0;
                    for term in &terms {
                        if title.contains(term) {
                            score += 3;
                        }
                        if keywords.iter().any(|keyword| keyword.contains(term)) {
                            score += 2;
                        }
                        if summary.contains(term) {
                            score += 1;
                        }
                    }
                    if !q.trim().is_empty() && title.contains(&q) {
                        score += 10;
                    }
                    if !q.trim().is_empty() && summary.contains(&q) {
                        score += 3;
                    }
                    (q.trim().is_empty() || score > 0).then_some((score, ch.clone()))
                })
                .collect::<Vec<_>>();
            scored.sort_by(|left, right| right.0.cmp(&left.0));
            return scored.into_iter().map(|(_, chapter)| chapter).collect();
        }
        vec![]
    }

    pub async fn set_settings(&self, settings: &crate::settings::Settings) {
        *self.language.write().await = settings.language.clone();
        *self.summary_interval.write().await = settings.summary_interval;
        *self.context_window.write().await = settings.context_window;
        *self.response_length.write().await = settings.response_length.clone();
        let model = if settings.conversation_model.eq_ignore_ascii_case("pro") {
            "pro"
        } else {
            "flash"
        };
        *self.conversation_model.write().await = model.to_string();
    }
}
