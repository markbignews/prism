use crate::archives::Archives;
use crate::models::{ChatRole, Conversation, NarrativeEvent};
use crate::search_expander::SearchExpander;
use serde_json::Value;
use uuid::Uuid;

pub struct ToolDef {
    pub name: &'static str,
    pub description: &'static str,
    pub parameters: Value,
}

pub fn tool_definitions() -> Vec<ToolDef> {
    vec![
        ToolDef {
            name: "track_person",
            description: "Look up person records across conversations",
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Person name to look up"}
                },
                "required": ["name"]
            }),
        },
        ToolDef {
            name: "emotion_timeline",
            description: "Return recent emotional trajectory",
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "count": {"type": "integer", "description": "Number of recent entries", "default": 5}
                },
                "required": []
            }),
        },
        ToolDef {
            name: "search_chapters",
            description: "Search historical chapter summaries by keywords",
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query; empty returns recent chapters"},
                    "count": {"type": "integer", "description": "Maximum results", "default": 10}
                },
                "required": ["query"]
            }),
        },
        ToolDef {
            name: "fetch_chapter_messages",
            description: "Get full messages for a specific chapter",
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "index": {"type": "integer", "description": "Global chapter index (1-based)"}
                },
                "required": ["index"]
            }),
        },
        ToolDef {
            name: "search_memory",
            description: "Long-term cross-conversation memory search",
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "count": {"type": "integer", "description": "Maximum results", "default": 10}
                },
                "required": ["query"]
            }),
        },
        narrative_timeline_tool(),
    ]
}

fn narrative_timeline_tool() -> ToolDef {
    ToolDef {
        name: "manage_narrative_timeline",
        description: "List or upsert events using the time stated in the user's story, never the chat send time. Use list before updating an earlier event. If the intended period is ambiguous, ask the user instead of calling upsert.",
        parameters: serde_json::json!({
            "type": "object",
            "properties": {
                "action": {"type": "string", "enum": ["list", "upsert"]},
                "eventId": {"type": "string", "description": "Existing event UUID when supplementing or correcting a past event"},
                "title": {"type": "string", "description": "Short event title"},
                "summary": {"type": "string", "description": "One concise non-repetitive sentence, at most 80 Chinese characters or 45 English words"},
                "startLabel": {"type": "string", "description": "User-stated start point or period, e.g. 高二期间 or 2024-03-12"},
                "endLabel": {"type": "string", "description": "Optional user-stated end point"},
                "timeKind": {"type": "string", "enum": ["period", "date", "mixed"]},
                "sortIndex": {"type": "integer", "description": "Chronological order; use gaps such as 10, 20, 30"}
            },
            "required": ["action"]
        }),
    }
}

pub fn narrative_timeline_tool_json() -> Vec<Value> {
    let tool = narrative_timeline_tool();
    vec![serde_json::json!({
        "type": "function",
        "function": {
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.parameters
        }
    })]
}

pub fn tool_definitions_json() -> Vec<Value> {
    tool_definitions()
        .into_iter()
        .map(|t| {
            serde_json::json!({
                "type": "function",
                "function": {
                    "name": t.name,
                    "description": t.description,
                    "parameters": t.parameters
                }
            })
        })
        .collect()
}

pub async fn execute_tool(
    name: &str,
    args: &Value,
    archives: &Archives,
    conversations: &[Conversation],
    current_conversation_id: Uuid,
) -> Result<Value, String> {
    match name {
        "track_person" => {
            let name = args["name"].as_str().unwrap_or("");
            let person = archives.find_person(name);
            Ok(serde_json::json!(person))
        }
        "emotion_timeline" => {
            let limit = args["count"].as_u64().unwrap_or(5).clamp(1, 50) as usize;
            let emotions = archives.get_recent_emotions(limit);
            Ok(serde_json::json!({"entries": emotions}))
        }
        "search_chapters" => {
            let query = args["query"].as_str().unwrap_or("");
            let limit = args["count"].as_u64().unwrap_or(10).clamp(1, 20) as usize;
            let q = query.to_lowercase();
            let terms = SearchExpander::default().terms(&q);
            let mut scored = Vec::new();

            for (conversation_index, conversation) in conversations.iter().enumerate() {
                for (chapter_index, chapter) in conversation.chapters.iter().enumerate() {
                    let title = chapter.title.to_lowercase();
                    let summary = chapter.summary.to_lowercase();
                    let keywords = chapter
                        .keywords
                        .iter()
                        .map(|keyword| keyword.to_lowercase())
                        .collect::<Vec<_>>();
                    let mut score = if q.trim().is_empty() { 1 } else { 0 };
                    for term in terms.iter().filter(|term| !term.is_empty()) {
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
                    if score > 0 {
                        scored.push((
                            score,
                            conversation_index,
                            chapter_index,
                            serde_json::json!({
                                "conversationId": conversation.id,
                                "conversationTitle": conversation.title,
                                "chapter": chapter_index + 1,
                                "title": chapter.title,
                                "summary": chapter.summary.chars().take(240).collect::<String>(),
                                "keywords": chapter.keywords,
                            }),
                        ));
                    }
                }
            }

            scored.sort_by(|left, right| {
                right
                    .0
                    .cmp(&left.0)
                    .then_with(|| left.1.cmp(&right.1).then_with(|| left.2.cmp(&right.2)))
            });
            Ok(serde_json::json!({
                "query": q,
                "results": scored
                    .into_iter()
                    .take(limit)
                    .map(|entry| entry.3)
                    .collect::<Vec<_>>()
            }))
        }
        "fetch_chapter_messages" => {
            let index = args["index"].as_i64().unwrap_or(0);
            if index < 1 {
                return Ok(serde_json::json!({"error": "invalid index"}));
            }

            let mut current = 0_i64;
            for conversation in conversations {
                for chapter in &conversation.chapters {
                    current += 1;
                    if current != index {
                        continue;
                    }
                    let messages = conversation
                        .messages
                        .iter()
                        .filter(|message| {
                            message.role != ChatRole::system
                                && chapter.message_ids.contains(&message.id)
                        })
                        .take(12)
                        .map(|message| {
                            serde_json::json!({
                                "role": message.role,
                                "content": message.content,
                            })
                        })
                        .collect::<Vec<_>>();
                    return Ok(serde_json::json!({
                        "chapter": index,
                        "title": chapter.title,
                        "summary": chapter.summary,
                        "keywords": chapter.keywords,
                        "messages": messages,
                    }));
                }
            }
            Ok(serde_json::json!({
                "error": "chapter not found",
                "max": current,
                "currentConversationId": current_conversation_id,
            }))
        }
        "search_memory" => {
            let query = args["query"].as_str().unwrap_or("");
            let limit = args["count"].as_u64().unwrap_or(10).clamp(1, 20) as usize;
            let results = archives
                .search_memory(&[query.to_string()])
                .into_iter()
                .take(limit)
                .map(|entry| {
                    serde_json::json!({
                        "content": entry.content,
                        "keywords": entry.keywords,
                        "sourceChapter": entry.source_chapter_title,
                        "timeSpanStart": entry.time_span_start.map(|value| value.to_rfc3339()),
                        "timeSpanEnd": entry.time_span_end.map(|value| value.to_rfc3339()),
                        "recallCount": entry.recall_count,
                    })
                })
                .collect::<Vec<_>>();
            Ok(serde_json::json!(results))
        }
        "manage_narrative_timeline" => {
            let action = args["action"].as_str().unwrap_or("list");
            let current_events = || {
                archives
                    .all_narrative_events()
                    .into_iter()
                    .filter(|event| event.conversation_id == current_conversation_id)
                    .collect::<Vec<_>>()
            };
            if action == "list" {
                return Ok(serde_json::json!({"events": current_events()}));
            }
            if action != "upsert" {
                return Err("action must be list or upsert".to_string());
            }

            let title = args["title"].as_str().unwrap_or("").trim();
            let start_label = args["startLabel"].as_str().unwrap_or("").trim();
            if title.is_empty() || start_label.is_empty() {
                return Err("title and startLabel are required; ask the user when the story time is unclear".to_string());
            }
            let requested_id = args["eventId"]
                .as_str()
                .and_then(|value| Uuid::parse_str(value).ok());
            let existing = requested_id
                .and_then(|id| current_events().into_iter().find(|event| event.id == id));
            let source_message_id = conversations
                .iter()
                .find(|conversation| conversation.id == current_conversation_id)
                .and_then(|conversation| {
                    conversation
                        .messages
                        .iter()
                        .rev()
                        .find(|message| message.role == ChatRole::user)
                        .map(|message| message.id)
                });
            let mut source_message_ids = existing
                .as_ref()
                .map(|event| event.source_message_ids.clone())
                .unwrap_or_default();
            if let Some(message_id) = source_message_id {
                if !source_message_ids.contains(&message_id) {
                    source_message_ids.push(message_id);
                }
            }
            let summary = args["summary"]
                .as_str()
                .unwrap_or("")
                .trim()
                .chars()
                .take(160)
                .collect::<String>();
            let event = NarrativeEvent {
                id: existing
                    .as_ref()
                    .map(|event| event.id)
                    .unwrap_or_else(Uuid::new_v4),
                conversation_id: current_conversation_id,
                title: title.chars().take(40).collect(),
                summary,
                start_label: start_label.chars().take(60).collect(),
                end_label: args["endLabel"]
                    .as_str()
                    .unwrap_or("")
                    .trim()
                    .chars()
                    .take(60)
                    .collect(),
                time_kind: args["timeKind"]
                    .as_str()
                    .filter(|value| matches!(*value, "period" | "date" | "mixed"))
                    .unwrap_or("period")
                    .to_string(),
                sort_index: args["sortIndex"]
                    .as_i64()
                    .map(|value| value.clamp(-100_000, 100_000) as i32)
                    .or_else(|| existing.as_ref().map(|event| event.sort_index))
                    .unwrap_or_else(|| {
                        current_events()
                            .iter()
                            .map(|event| event.sort_index)
                            .max()
                            .unwrap_or(0)
                            + 10
                    }),
                source_message_ids,
                updated_at: chrono::Utc::now(),
            };
            archives.upsert_narrative_event(event.clone());
            Ok(serde_json::json!({"saved": true, "event": event}))
        }
        _ => Err(format!("Unknown tool: {}", name)),
    }
}
