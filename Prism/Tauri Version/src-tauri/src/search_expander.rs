pub struct SearchExpander {
    groups: Vec<Vec<&'static str>>,
}

impl SearchExpander {
    pub fn new() -> Self {
        // Keep this table local and deterministic. It mirrors the Swift
        // implementation and is intentionally used before any network
        // reranking so search remains useful when Flash is unavailable.
        let groups = vec![
            vec![
                "悲伤",
                "难过",
                "伤心",
                "心痛",
                "沮丧",
                "低落",
                "抑郁",
                "sad",
                "depressed",
            ],
            vec![
                "愤怒", "生气", "恼火", "烦躁", "不爽", "火大", "angry", "furious",
            ],
            vec![
                "恐惧", "害怕", "担心", "焦虑", "紧张", "不安", "fear", "anxiety", "anxious",
            ],
            vec!["羞耻", "丢脸", "尴尬", "难堪", "shame", "embarrassed"],
            vec!["孤独", "寂寞", "孤单", "lonely", "alone"],
            vec!["嫉妒", "羡慕", "眼红", "jealous", "envy"],
            vec![
                "内疚", "愧疚", "亏欠", "自责", "后悔", "遗憾", "guilt", "regret",
            ],
            vec![
                "挣扎",
                "煎熬",
                "痛苦",
                "折磨",
                "崩溃",
                "绝望",
                "pain",
                "suffering",
            ],
            vec!["倦怠", "疲倦", "疲惫", "累", "失眠", "噩梦", "exhausted"],
            vec![
                "释然",
                "放下",
                "接受",
                "想开",
                "放手",
                "let go",
                "acceptance",
            ],
            vec!["希望", "期待", "盼望", "憧憬", "hope", "hopeful"],
            vec!["困惑", "迷茫", "不清楚", "不明白", "confused", "lost"],
            vec!["妈妈", "母亲", "妈", "mom", "mother"],
            vec!["爸爸", "父亲", "爸", "爹", "dad", "father"],
            vec!["家庭", "父母", "爸妈", "家长", "family", "parents"],
            vec!["前任", "前女友", "前男友", "ex", "前妻", "前夫"],
            vec!["分手", "分开", "结束", "breakup", "离婚"],
            vec!["暧昧", "暗恋", "追求", "拒绝", "复合", "crush", "reject"],
            vec!["背叛", "出轨", "劈腿", "cheat", "betray"],
            vec!["朋友", "闺蜜", "兄弟", "好友", "死党", "friend"],
            vec![
                "同事", "老板", "上司", "领导", "职场", "工作", "work", "boss",
            ],
            vec!["辞职", "裁员", "失业", "创业", "压力", "stress", "laid off"],
            vec!["搬家", "离开", "回去", "回来", "move", "leave"],
            vec!["走出来", "move on", "释怀", "忘记", "放下"],
            vec!["自信", "自卑", "自尊", "怀疑", "内耗", "insecure"],
            vec!["吵架", "争吵", "冷战", "冲突", "矛盾", "fight", "argue"],
            vec!["道歉", "对不起", "原谅", "sorry", "apologize"],
            vec!["欺骗", "撒谎", "说谎", "隐瞒", "lie", "deceive"],
            vec!["控制", "操纵", "掌控", "control", "manipulate"],
        ];
        Self { groups }
    }

    /// Return the original query's terms plus all members of a synonym group
    /// touched by any term. Chinese queries need substring matching because
    /// they are commonly entered without whitespace.
    pub fn terms(&self, query: &str) -> Vec<String> {
        let lower = query.to_lowercase();
        let mut terms = Vec::new();
        for token in lower.split_whitespace().filter(|token| !token.is_empty()) {
            terms.push(token.to_string());
        }
        if terms.is_empty() && !lower.trim().is_empty() {
            terms.push(lower.clone());
        }
        for group in &self.groups {
            if group
                .iter()
                .any(|word| lower.contains(&word.to_lowercase()))
            {
                for word in group {
                    let word = word.to_lowercase();
                    if !terms.contains(&word) {
                        terms.push(word);
                    }
                }
            }
        }
        terms
    }
}

impl Default for SearchExpander {
    fn default() -> Self {
        Self::new()
    }
}
