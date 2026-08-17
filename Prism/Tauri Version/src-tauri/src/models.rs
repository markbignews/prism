use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

fn default_summary_interval_minutes() -> i32 {
    5
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ChatRole {
    user,
    assistant,
    system,
    tool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolCallDelta {
    pub index: Option<i32>,
    pub id: Option<String>,
    pub function: Option<ToolFnDelta>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolFnDelta {
    pub name: Option<String>,
    pub arguments: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolResult {
    pub tool_call_id: String,
    pub name: String,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ChatMessage {
    pub id: Uuid,
    pub role: ChatRole,
    pub content: String,
    pub reasoning: Option<String>,
    pub tool_calls: Option<Vec<ToolCall>>,
    #[serde(default)]
    pub tool_call_id: Option<String>,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub suggestions: Vec<String>,
}

impl ChatMessage {
    pub fn new(role: ChatRole, content: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            role,
            content,
            reasoning: None,
            tool_calls: None,
            tool_call_id: None,
            created_at: Utc::now(),
            suggestions: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StoryChapter {
    pub id: Uuid,
    pub title: String,
    pub summary: String,
    pub keywords: Vec<String>,
    // Swift Codable writes `messageIDs`; early Tauri builds wrote
    // `messageIds`. Read both and keep the Swift-compatible spelling on save.
    #[serde(rename = "messageIDs", alias = "messageIds", alias = "message_ids")]
    pub message_ids: Vec<Uuid>,
    pub created_at: DateTime<Utc>,
    #[serde(default = "chrono::Utc::now")]
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Conversation {
    pub id: Uuid,
    pub title: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub messages: Vec<ChatMessage>,
    pub chapters: Vec<StoryChapter>,
    pub mode: ConversationMode,
    #[serde(default = "default_summary_interval_minutes")]
    pub summary_interval_minutes: i32,
    #[serde(default)]
    pub last_summarized_at: Option<DateTime<Utc>>,
    pub completed_dialog_count: i32,
    pub last_summary_message_index: usize,
    pub incremental_chapter_count: i32,
}

impl Conversation {
    pub fn new(title: String) -> Self {
        Self {
            id: Uuid::new_v4(),
            title,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            messages: Vec::new(),
            chapters: Vec::new(),
            mode: ConversationMode::balanced,
            summary_interval_minutes: 5,
            last_summarized_at: None,
            completed_dialog_count: 0,
            last_summary_message_index: 0,
            incremental_chapter_count: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ConversationMode {
    rational,
    balanced,
    warm,
}

impl ConversationMode {
    pub fn temperature(&self) -> f64 {
        match self {
            Self::rational => 0.1,
            Self::balanced => 0.35,
            Self::warm => 0.6,
        }
    }

    pub fn top_p(&self) -> f64 {
        match self {
            Self::rational => 0.8,
            Self::balanced => 0.9,
            Self::warm => 0.95,
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "rational" => Self::rational,
            "warm" => Self::warm,
            _ => Self::balanced,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum ResponseLength {
    brief,
    standard,
    detailed,
}

impl ResponseLength {
    pub fn max_tokens(&self) -> u32 {
        match self {
            Self::brief => 1024,
            Self::standard => 4096,
            Self::detailed => 8192,
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "brief" => Self::brief,
            "detailed" => Self::detailed,
            _ => Self::standard,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum AppLanguage {
    zh,
    zh_hant,
    en,
}

impl AppLanguage {
    pub fn from_str(s: &str) -> Self {
        match s {
            "zh" | "zh-CN" | "zh-Hans" => Self::zh,
            "zh-hant" | "zh-TW" | "zh-HK" | "zh-Hant" => Self::zh_hant,
            _ => Self::en,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct EmotionEntry {
    pub id: Uuid,
    #[serde(
        rename = "conversationID",
        alias = "conversationId",
        alias = "conversation_id"
    )]
    pub conversation_id: Uuid,
    pub segment: String,
    pub emotion: String,
    pub intensity: f64,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PersonRecord {
    pub id: Uuid,
    pub name: String,
    pub role: String,
    pub first_mentioned_at: DateTime<Utc>,
    pub last_mentioned_at: DateTime<Utc>,
    pub mention_count: i32,
    pub emotional_arc: String,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BlindspotRecord {
    pub id: Uuid,
    #[serde(
        rename = "conversationID",
        alias = "conversationId",
        alias = "conversation_id"
    )]
    pub conversation_id: Uuid,
    pub pattern: String,
    pub evidence: String,
    pub counter_question: String,
    pub severity: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogEntry {
    pub timestamp: String,
    pub level: String,
    pub tag: String,
    pub message: String,
    pub data: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MemoryEntry {
    pub id: Uuid,
    pub content: String,
    pub keywords: Vec<String>,
    #[serde(
        rename = "sourceConversationID",
        alias = "sourceConversationId",
        alias = "source_conversation_id"
    )]
    pub source_conversation_id: Uuid,
    pub source_chapter_title: String,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub time_span_start: Option<DateTime<Utc>>,
    #[serde(default)]
    pub time_span_end: Option<DateTime<Utc>>,
    pub last_recalled_at: Option<DateTime<Utc>>,
    pub recall_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeEvent {
    pub id: Uuid,
    #[serde(
        rename = "conversationID",
        alias = "conversationId",
        alias = "conversation_id"
    )]
    pub conversation_id: Uuid,
    pub title: String,
    pub summary: String,
    pub start_label: String,
    #[serde(default)]
    pub end_label: String,
    #[serde(default = "default_narrative_time_kind")]
    pub time_kind: String,
    #[serde(default = "default_narrative_sort_index")]
    pub sort_index: i32,
    #[serde(
        default,
        rename = "sourceMessageIDs",
        alias = "sourceMessageIds",
        alias = "source_message_ids"
    )]
    pub source_message_ids: Vec<Uuid>,
    pub updated_at: DateTime<Utc>,
}

fn default_narrative_time_kind() -> String {
    "period".to_string()
}

fn default_narrative_sort_index() -> i32 {
    10
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageStats {
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub output_tokens: u64,
    #[serde(default)]
    pub cache_hit_tokens: u64,
    #[serde(default)]
    pub cache_miss_tokens: u64,
    #[serde(default)]
    pub request_count: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ContextUsageSnapshot {
    pub estimated_tokens: u64,
    pub uncompressed_estimated_tokens: u64,
    pub raw_conversation_tokens: u64,
    pub capacity_tokens: u64,
    pub reserved_output_tokens: u64,
    pub message_count: usize,
    pub preparation_threshold_tokens: u64,
    pub compression_threshold_tokens: u64,
    pub critical_threshold_tokens: u64,
    pub retained_recent_tokens: u64,
    pub tokens_until_preparation: u64,
    pub tokens_until_compression: u64,
    pub preparation_active: bool,
    pub compression_active: bool,
    pub critical: bool,
    pub summary_interval: i32,
    pub dialogs_until_summary: i32,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TokenUsage {
    #[serde(default)]
    pub prompt_tokens: u64,
    #[serde(default)]
    pub completion_tokens: u64,
    #[serde(default)]
    pub prompt_cache_hit_tokens: u64,
    #[serde(default)]
    pub prompt_cache_miss_tokens: u64,
}
