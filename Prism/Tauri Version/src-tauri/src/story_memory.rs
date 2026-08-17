use crate::models::*;
use chrono::Utc;
use uuid::Uuid;

/// Local, deterministic chapter memory. This runs before any API request so
/// the current turn is immediately available to context building, chapter
/// navigation, and the retrieval tools. The Flash summarizer later enriches
/// these lightweight entries with a narrative summary.
pub struct StoryMemory {
    pub relevant_context: Vec<String>,
}

impl StoryMemory {
    pub fn new() -> Self {
        Self {
            relevant_context: Vec::new(),
        }
    }

    pub fn ingest(user_text: &str, message_id: Uuid, conversation: &mut Conversation) {
        let paragraphs = split_paragraphs(user_text);
        if paragraphs.is_empty() {
            return;
        }

        if paragraphs.len() > 1 {
            for paragraph in paragraphs
                .iter()
                .filter(|value| value.chars().count() >= 12)
            {
                append_chapter(paragraph, message_id, conversation);
            }
            return;
        }

        let paragraph = &paragraphs[0];
        if paragraph.chars().count() >= 80 || conversation.chapters.is_empty() {
            append_chapter(paragraph, message_id, conversation);
        } else if let Some(last) = conversation.chapters.last_mut() {
            last.summary = bounded_summary(&format!("{}\n{}", last.summary, paragraph));
            last.keywords = merge_keywords(&last.keywords, &extract_keywords(paragraph));
            if !last.message_ids.contains(&message_id) {
                last.message_ids.push(message_id);
            }
            last.updated_at = Utc::now();
        }
    }

    /// Build only relevant local chapter context instead of injecting every
    /// chapter into every turn. Direct chapter references win; otherwise use
    /// keyword matches and keep a small recent tail as a safe fallback.
    pub fn build_context(
        &mut self,
        conversation: &Conversation,
        query: &str,
        language: &str,
    ) -> String {
        let lowered = query.to_lowercase();
        let mut selected: Vec<&StoryChapter> = Vec::new();

        for (index, chapter) in conversation.chapters.iter().enumerate() {
            let number = index + 1;
            let direct = lowered.contains(&format!("第{}章", number))
                || lowered.contains(&format!("第{}节", number))
                || lowered.contains(&format!("章节{}", number))
                || lowered.contains(&format!("chapter {}", number));
            let title_match = chapter.title.chars().count() >= 4
                && lowered.contains(&chapter.title.to_lowercase());
            if direct || title_match {
                selected.push(chapter);
            }
        }

        if selected.is_empty() {
            let terms: Vec<&str> = lowered
                .split_whitespace()
                .filter(|term| term.chars().count() >= 2)
                .collect();
            for chapter in &conversation.chapters {
                let score = terms
                    .iter()
                    .map(|term| {
                        let mut value = 0;
                        if chapter.summary.to_lowercase().contains(term) {
                            value += 1;
                        }
                        if chapter
                            .keywords
                            .iter()
                            .any(|keyword| keyword.to_lowercase().contains(term))
                        {
                            value += 3;
                        }
                        value
                    })
                    .sum::<i32>();
                if score > 0 {
                    selected.push(chapter);
                }
                if selected.len() >= 3 {
                    break;
                }
            }
        }

        if selected.is_empty()
            && [
                "章节",
                "那段",
                "前面",
                "之前",
                "刚才",
                "刚刚",
                "上面",
                "回到",
                "提到",
                "earlier",
                "previous",
                "before",
                "that part",
                "the part",
            ]
            .iter()
            .any(|indicator| lowered.contains(indicator))
        {
            selected.extend(conversation.chapters.iter().rev().take(2));
        }

        let context = if selected.is_empty() {
            String::new()
        } else {
            let heading = if language.starts_with("zh") {
                "[相关本地章节记忆 — 仅在确实相关时使用]"
            } else {
                "[Relevant local chapter memory — use only when genuinely relevant]"
            };
            let body = selected
                .iter()
                .enumerate()
                .map(|(index, chapter)| {
                    format!(
                        "{}. {}\nSummary: {}\nKeywords: {}",
                        index + 1,
                        chapter.title,
                        chapter.summary.chars().take(600).collect::<String>(),
                        chapter.keywords.join(", ")
                    )
                })
                .collect::<Vec<_>>()
                .join("\n\n");
            format!("{}\n{}", heading, body)
        };

        self.relevant_context = vec![context.clone()];
        context
    }

    pub fn extract_memory_entry(
        &self,
        chapter: &StoryChapter,
        conv_id: Uuid,
        messages: &[ChatMessage],
    ) -> MemoryEntry {
        let dates = messages
            .iter()
            .filter(|message| chapter.message_ids.contains(&message.id))
            .map(|message| message.created_at)
            .collect::<Vec<_>>();
        let time_span_start = dates.iter().min().copied().unwrap_or(chapter.created_at);
        let time_span_end = dates.iter().max().copied().unwrap_or(chapter.updated_at);
        MemoryEntry {
            id: Uuid::new_v4(),
            content: chapter.summary.clone(),
            keywords: chapter.keywords.clone(),
            source_conversation_id: conv_id,
            source_chapter_title: chapter.title.clone(),
            created_at: Utc::now(),
            time_span_start: Some(time_span_start),
            time_span_end: Some(time_span_end),
            last_recalled_at: None,
            recall_count: 0,
        }
    }
}

fn append_chapter(text: &str, message_id: Uuid, conversation: &mut Conversation) {
    let title = make_title(text, conversation.chapters.len() + 1);
    conversation.chapters.push(StoryChapter {
        id: Uuid::new_v4(),
        title,
        summary: bounded_summary(text),
        keywords: extract_keywords(text),
        message_ids: vec![message_id],
        created_at: Utc::now(),
        updated_at: Utc::now(),
    });
}

fn split_paragraphs(text: &str) -> Vec<String> {
    let mut paragraphs = Vec::new();
    let mut current = Vec::new();
    for line in text.lines() {
        if line.trim().is_empty() {
            if !current.is_empty() {
                paragraphs.push(current.join("\n").trim().to_string());
                current.clear();
            }
        } else {
            current.push(line.to_string());
        }
    }
    if !current.is_empty() {
        paragraphs.push(current.join("\n").trim().to_string());
    }
    paragraphs
        .into_iter()
        .filter(|part| !part.is_empty())
        .collect()
}

fn make_title(text: &str, fallback_number: usize) -> String {
    let normalized = text.replace(['#', '*'], "").trim().to_string();
    let sentence = normalized
        .split(['。', '！', '？', '.', '!', '?', '\n'])
        .next()
        .unwrap_or("")
        .trim();
    if sentence.is_empty() {
        format!("Chapter {}", fallback_number)
    } else {
        sentence.chars().take(24).collect()
    }
}

fn bounded_summary(text: &str) -> String {
    let trimmed = text.trim();
    let count = trimmed.chars().count();
    if count > 900 {
        trimmed.chars().skip(count - 900).collect()
    } else {
        trimmed.to_string()
    }
}

fn extract_keywords(text: &str) -> Vec<String> {
    let stop_words = [
        "就是", "然后", "但是", "因为", "所以", "这个", "那个", "他们", "我们", "自己", "感觉",
        "觉得", "没有", "不是", "还是", "只是", "已经", "可能", "the", "and", "that", "this",
        "with", "from", "have", "just", "feel", "because",
    ];
    let mut result = Vec::new();
    for token in text
        .split(|ch: char| {
            ch.is_whitespace() || "，。！？；：、“”‘’（）【】《》…,.!?;:".contains(ch)
        })
        .map(|token| token.trim().to_lowercase())
        .filter(|token| token.chars().count() >= 2 && !stop_words.contains(&token.as_str()))
    {
        if !result.contains(&token) {
            result.push(token);
        }
        if result.len() >= 12 {
            break;
        }
    }
    result
}

fn merge_keywords(left: &[String], right: &[String]) -> Vec<String> {
    let mut merged = left.to_vec();
    for keyword in right {
        if !merged.contains(keyword) {
            merged.push(keyword.clone());
        }
    }
    merged.truncate(16);
    merged
}

impl Default for StoryMemory {
    fn default() -> Self {
        Self::new()
    }
}
