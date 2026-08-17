use crate::models::*;
use crate::search_expander::SearchExpander;
use serde_json::Value;
use std::path::PathBuf;
use uuid::Uuid;

pub struct Archives {
    data_dir: PathBuf,
}

impl Archives {
    pub fn new(data_dir: PathBuf) -> Self {
        std::fs::create_dir_all(&data_dir).ok();
        Self { data_dir }
    }

    pub fn set_data_dir(&mut self, dir: PathBuf) {
        self.data_dir = dir;
        std::fs::create_dir_all(&self.data_dir).ok();
    }

    fn path(&self, name: &str) -> PathBuf {
        self.data_dir.join(name)
    }

    /// Swift stores conversations next to the Data directory while auxiliary
    /// archives live inside it. Keep that layout so Tauri can open existing
    /// Prism data without a migration step.
    fn conversations_path(&self) -> PathBuf {
        self.data_dir
            .parent()
            .unwrap_or(&self.data_dir)
            .join("conversations.json")
    }

    fn read_json(&self, name: &str) -> Value {
        let path = self.path(name);
        match std::fs::read_to_string(&path) {
            Ok(s) => serde_json::from_str(&s).unwrap_or(serde_json::json!({})),
            Err(_) => serde_json::json!({}),
        }
    }

    fn write_json(&self, name: &str, value: &Value) {
        let path = self.path(name);
        self.write_value(&path, value);
    }

    fn write_value(&self, path: &std::path::Path, value: &Value) {
        std::fs::create_dir_all(path.parent().unwrap()).ok();
        let tmp = path.with_extension("json.tmp");
        if let Ok(s) = serde_json::to_string_pretty(value) {
            let _ = std::fs::write(&tmp, &s);
            let _ = std::fs::rename(&tmp, &path);
        }
    }

    // ─── Conversations ───

    pub fn load_conversations(&self) -> Vec<Conversation> {
        let primary = self.conversations_path();
        let read = |path: &std::path::Path| {
            std::fs::read_to_string(path)
                .ok()
                .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        };
        let value = read(&primary).or_else(|| read(&self.path("conversations.json")));
        value
            .and_then(|v| {
                // Swift writes a bare array; early Tauri builds wrote it under
                // a `conversations` key. Accept both formats on import.
                if v.is_array() {
                    serde_json::from_value(v).ok()
                } else {
                    serde_json::from_value(v["conversations"].clone()).ok()
                }
            })
            .unwrap_or_default()
    }

    pub fn save_conversations(&self, convs: &[Conversation]) {
        // Match Swift's semantic compaction on disk. The live in-memory
        // conversation remains complete for the current window; only older
        // persisted messages are replaced by chapter references or bounded
        // excerpts so reopening a very long chat stays lightweight.
        let compacted = convs.iter().map(trim_conversation).collect::<Vec<_>>();
        let v = serde_json::to_value(compacted).unwrap_or(Value::Array(Vec::new()));
        self.write_value(&self.conversations_path(), &v);
    }

    // ─── Emotion Timeline ───

    pub fn add_emotion(&self, entry: &EmotionEntry) {
        let v = self.read_json("emotion_timeline.json");
        let mut arr = archive_array(&v, "entries");
        if let Ok(val) = serde_json::to_value(entry) {
            arr.push(val);
        }
        while arr.len() > 200 {
            arr.remove(0);
        }
        self.write_json("emotion_timeline.json", &Value::Array(arr));
    }

    pub fn get_recent_emotions(&self, limit: usize) -> Vec<EmotionEntry> {
        let v = self.read_json("emotion_timeline.json");
        let arr = archive_array(&v, "entries");
        let start = arr.len().saturating_sub(limit);
        arr[start..]
            .iter()
            .filter_map(|x| serde_json::from_value(x.clone()).ok())
            .collect()
    }

    // ─── Person Records ───

    pub fn all_persons(&self) -> Vec<PersonRecord> {
        let v = self.read_json("person_archive.json");
        serde_json::from_value(Value::Array(archive_array(&v, "persons"))).unwrap_or_default()
    }

    pub fn find_person(&self, name: &str) -> Option<PersonRecord> {
        if name.trim().is_empty() {
            return None;
        }
        let name_lower = name.to_lowercase();
        self.all_persons()
            .into_iter()
            .find(|p| p.name.to_lowercase().contains(&name_lower))
    }

    pub fn save_person(&self, person: &PersonRecord) {
        let v = self.read_json("person_archive.json");
        let mut persons: Vec<PersonRecord> =
            serde_json::from_value(Value::Array(archive_array(&v, "persons"))).unwrap_or_default();
        if let Some(existing) = persons
            .iter_mut()
            .find(|p| p.name.eq_ignore_ascii_case(&person.name))
        {
            existing.last_mentioned_at = person.last_mentioned_at;
            existing.mention_count += person.mention_count.max(1);
            if existing.role.is_empty() {
                existing.role = person.role.clone();
            }
            if !person.emotional_arc.is_empty() {
                existing.emotional_arc = person.emotional_arc.clone();
            }
            existing.notes.extend(person.notes.iter().cloned());
            existing.notes.truncate(20);
        } else {
            persons.push(person.clone());
        }
        persons.sort_by(|left, right| right.last_mentioned_at.cmp(&left.last_mentioned_at));
        persons.truncate(200);
        self.write_json(
            "person_archive.json",
            &serde_json::to_value(persons).unwrap_or(Value::Array(Vec::new())),
        );
    }

    // ─── Blindspots ───

    pub fn recent_blindspots(&self, limit: usize) -> Vec<BlindspotRecord> {
        let v = self.read_json("blindspots.json");
        let arr = archive_array(&v, "entries");
        let start = arr.len().saturating_sub(limit);
        arr[start..]
            .iter()
            .filter_map(|x| serde_json::from_value(x.clone()).ok())
            .collect()
    }

    pub fn add_blindspot(&self, entry: &BlindspotRecord) {
        let v = self.read_json("blindspots.json");
        let mut arr = archive_array(&v, "entries");
        if let Ok(val) = serde_json::to_value(entry) {
            arr.push(val);
        }
        while arr.len() > 300 {
            arr.remove(0);
        }
        self.write_json("blindspots.json", &Value::Array(arr));
    }

    // ─── Memory ───

    pub fn search_memory(&self, queries: &[String]) -> Vec<MemoryEntry> {
        let v = self.read_json("memory.json");
        let entries: Vec<MemoryEntry> =
            serde_json::from_value(Value::Array(archive_array(&v, "entries"))).unwrap_or_default();
        if queries.is_empty() {
            return entries;
        }
        let expander = SearchExpander::default();
        let q_lower: Vec<String> = queries
            .iter()
            .flat_map(|query| expander.terms(query))
            .filter(|term| term.chars().count() >= 1)
            .collect();
        let full_queries = queries
            .iter()
            .map(|query| query.to_lowercase())
            .filter(|query| !query.trim().is_empty())
            .collect::<Vec<_>>();
        let mut scored = entries
            .into_iter()
            .filter_map(|entry| {
                let content = entry.content.to_lowercase();
                let keywords = entry
                    .keywords
                    .iter()
                    .map(|keyword| keyword.to_lowercase())
                    .collect::<Vec<_>>();
                let mut score = 0;
                for term in &q_lower {
                    if keywords.iter().any(|keyword| keyword == term) {
                        score += 3;
                    } else if keywords.iter().any(|keyword| keyword.contains(term)) {
                        score += 2;
                    }
                    score += count_occurrences(&content, term);
                }
                if full_queries.iter().any(|query| content.contains(query)) {
                    score += 2;
                }
                (score > 0).then_some((score, entry))
            })
            .collect::<Vec<_>>();
        scored.sort_by(|left, right| right.0.cmp(&left.0));

        let result = scored
            .into_iter()
            .map(|(_, mut entry)| {
                entry.last_recalled_at = Some(chrono::Utc::now());
                entry.recall_count += 1;
                entry
            })
            .collect::<Vec<_>>();
        if !result.is_empty() {
            let mut value = self.read_json("memory.json");
            if let Some(array) = archive_array_mut(&mut value, "entries") {
                for updated in &result {
                    if let Some(stored) = array
                        .iter_mut()
                        .find(|candidate| candidate["id"] == serde_json::json!(updated.id))
                    {
                        if let Ok(encoded) = serde_json::to_value(updated) {
                            *stored = encoded;
                        }
                    }
                }
                self.write_json("memory.json", &Value::Array(array.clone()));
            }
        }
        result
    }

    pub fn add_memory(&self, entry: &MemoryEntry) {
        let v = self.read_json("memory.json");
        let mut arr = archive_array(&v, "entries");
        if let Some(existing) = arr.iter_mut().find(|value| {
            (value["sourceConversationID"] == serde_json::json!(entry.source_conversation_id)
                || value["sourceConversationId"] == serde_json::json!(entry.source_conversation_id))
                && value["sourceChapterTitle"] == serde_json::json!(entry.source_chapter_title)
        }) {
            if let Ok(value) = serde_json::to_value(entry) {
                *existing = value;
            }
        } else if let Ok(value) = serde_json::to_value(entry) {
            arr.push(value);
        }
        if arr.len() > 500 {
            arr = arr.into_iter().rev().take(300).collect::<Vec<_>>();
            arr.reverse();
        }
        self.write_json("memory.json", &Value::Array(arr));
    }

    // ─── Narrative Timeline ───

    /// Events here describe when the user's narrated experience happened,
    /// rather than when a chat message happened to be sent.
    pub fn all_narrative_events(&self) -> Vec<NarrativeEvent> {
        let value = self.read_json("narrative_timeline.json");
        let mut events: Vec<NarrativeEvent> =
            serde_json::from_value(Value::Array(archive_array(&value, "events")))
                .unwrap_or_default();
        events.sort_by(|left, right| {
            left.sort_index
                .cmp(&right.sort_index)
                .then_with(|| left.updated_at.cmp(&right.updated_at))
        });
        events
    }

    pub fn upsert_narrative_event(&self, event: NarrativeEvent) {
        let mut events = self.all_narrative_events();
        if let Some(existing) = events.iter_mut().find(|candidate| candidate.id == event.id) {
            *existing = event;
        } else {
            events.push(event);
        }
        events.sort_by(|left, right| {
            left.sort_index
                .cmp(&right.sort_index)
                .then_with(|| left.updated_at.cmp(&right.updated_at))
        });
        if events.len() > 500 {
            events.drain(0..events.len() - 500);
        }
        self.write_json(
            "narrative_timeline.json",
            &serde_json::to_value(events).unwrap_or(Value::Array(Vec::new())),
        );
    }

    // ─── Conversation Deletion Purge ───

    /// Remove every archive record that references a deleted conversation
    /// (memory entries, emotion timeline, blindspots, narrative timeline
    /// events) and drop person records that are no longer mentioned in any
    /// remaining conversation. Without this, the retrieval tools and the
    /// per-send cross-conversation memory injection would keep surfacing the
    /// deleted conversation's content ("删掉对话后提示词里还能找到").
    pub fn purge_conversation(&self, conv_id: Uuid, remaining_conversations: &[Conversation]) {
        let id_json = serde_json::json!(conv_id);

        // Memory entries keyed by sourceConversationID (multi-alias).
        self.purge_array("memory.json", "entries", |entry| {
            entry["sourceConversationID"] != id_json
                && entry["sourceConversationId"] != id_json
                && entry["source_conversation_id"] != id_json
        });
        // Emotion timeline / blindspots keyed by conversationID (multi-alias).
        for file in ["emotion_timeline.json", "blindspots.json"] {
            self.purge_array(file, "entries", |entry| {
                entry["conversationID"] != id_json
                    && entry["conversationId"] != id_json
                    && entry["conversation_id"] != id_json
            });
        }
        // Narrative timeline events keyed by conversationID (multi-alias).
        self.purge_array("narrative_timeline.json", "events", |entry| {
            entry["conversationID"] != id_json
                && entry["conversationId"] != id_json
                && entry["conversation_id"] != id_json
        });
        // Person records are cross-conversation: keep only names that still
        // appear in a remaining conversation's messages (Swift parity).
        self.purge_array("person_archive.json", "persons", |entry| {
            let name = entry["name"].as_str().unwrap_or("").to_lowercase();
            !name.is_empty()
                && remaining_conversations.iter().any(|conv| {
                    conv.messages
                        .iter()
                        .any(|message| message.content.to_lowercase().contains(&name))
                })
        });
    }

    /// Keep only entries for which `keep` returns true; writes the file back
    /// only when something was actually removed.
    fn purge_array(&self, name: &str, key: &str, keep: impl Fn(&Value) -> bool) {
        let value = self.read_json(name);
        let array = archive_array(&value, key);
        let original_len = array.len();
        let kept: Vec<Value> = array.into_iter().filter(|entry| keep(entry)).collect();
        if kept.len() != original_len {
            self.write_json(name, &Value::Array(kept));
        }
    }
}

fn count_occurrences(text: &str, term: &str) -> i32 {
    if term.is_empty() {
        return 0;
    }
    text.match_indices(term).count() as i32
}

fn archive_array(value: &Value, key: &str) -> Vec<Value> {
    value
        .as_array()
        .cloned()
        .or_else(|| value[key].as_array().cloned())
        .unwrap_or_default()
}

fn archive_array_mut<'a>(value: &'a mut Value, key: &str) -> Option<&'a mut Vec<Value>> {
    if value.is_array() {
        value.as_array_mut()
    } else {
        value[key].as_array_mut()
    }
}

fn trim_conversation(conversation: &Conversation) -> Conversation {
    let mut result = conversation.clone();
    let keep_full = 40;
    if result.messages.len() > keep_full {
        let mut covered = std::collections::HashMap::new();
        for (index, chapter) in result.chapters.iter().enumerate() {
            for message_id in &chapter.message_ids {
                covered.insert(*message_id, (index + 1, chapter.title.clone()));
            }
        }
        let cutoff = result.messages.len() - keep_full;
        for message in result.messages.iter_mut().take(cutoff) {
            if let Some((chapter, title)) = covered.get(&message.id) {
                message.content = format!("[已归纳: 第{}章「{}」]", chapter, title);
                message.reasoning = None;
            } else {
                if message.content.chars().count() > 200 {
                    message.content = message.content.chars().take(200).collect::<String>() + "…";
                }
                if let Some(reasoning) = message.reasoning.as_mut() {
                    if reasoning.chars().count() > 200 {
                        *reasoning = reasoning.chars().take(200).collect::<String>() + "…";
                    }
                }
            }
        }
    }
    for chapter in &mut result.chapters {
        if chapter.summary.chars().count() > 320 {
            chapter.summary = chapter.summary.chars().take(320).collect::<String>() + "…";
        }
    }
    result
}
