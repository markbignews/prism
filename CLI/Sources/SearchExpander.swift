import Foundation

// MARK: - Semantic Query Expansion

/// Chinese synonym groups for common narrative/emotion domains.
/// Expands search queries so "难过" also matches "悲伤", "心痛" etc.
private let synonymGroups: [[String]] = [
    // ── Emotions ──
    ["悲伤", "难过", "伤心", "心痛", "沮丧", "低落", "抑郁", "sad", "depressed"],
    ["愤怒", "生气", "恼火", "烦躁", "不爽", "火大", "angry", "furious"],
    ["恐惧", "害怕", "担心", "焦虑", "紧张", "不安", "fear", "anxiety", "anxious"],
    ["羞耻", "丢脸", "尴尬", "难堪", "shame", "embarrassed"],
    ["孤独", "寂寞", "孤单", "lonely", "alone"],
    ["嫉妒", "羡慕", "眼红", "jealous", "envy"],
    ["内疚", "愧疚", "亏欠", "自责", "后悔", "遗憾", "guilt", "regret"],
    ["挣扎", "煎熬", "痛苦", "折磨", "崩溃", "绝望", "pain", "suffering"],
    ["倦怠", "疲倦", "疲惫", "累", "失眠", "噩梦", "exhausted"],
    ["释然", "放下", "接受", "想开", "放手", "let go", "acceptance"],
    ["希望", "期待", "盼望", "憧憬", "hope", "hopeful"],
    ["困惑", "迷茫", "不清楚", "不明白", "confused", "lost"],
    // ── Family ──
    ["妈妈", "母亲", "妈", "mom", "mother"],
    ["爸爸", "父亲", "爸", "爹", "dad", "father"],
    ["家庭", "父母", "爸妈", "家长", "family", "parents"],
    // ── Romance & Friendship ──
    ["前任", "前女友", "前男友", "ex", "前妻", "前夫"],
    ["分手", "分开", "结束", "breakup", "离婚"],
    ["暧昧", "暗恋", "追求", "拒绝", "复合", "crush", "reject"],
    ["背叛", "出轨", "劈腿", "cheat", "betray"],
    ["朋友", "闺蜜", "兄弟", "好友", "死党", "friend"],
    // ── Work & Life ──
    ["同事", "老板", "上司", "领导", "职场", "工作", "work", "boss"],
    ["辞职", "裁员", "失业", "创业", "压力", "stress", "laid off"],
    ["搬家", "离开", "回去", "回来", "move", "leave"],
    // ── Internal patterns ──
    ["走出来", "move on", "释怀", "忘记", "放下"],
    ["自信", "自卑", "自尊", "怀疑", "内耗", "insecure"],
    ["吵架", "争吵", "冷战", "冲突", "矛盾", "fight", "argue"],
    ["道歉", "对不起", "原谅", "sorry", "apologize"],
    ["欺骗", "撒谎", "说谎", "隐瞒", "lie", "deceive"],
    ["控制", "操纵", "掌控", "control", "manipulate"],
]

/// Expand query terms with synonyms from the group map.
func expandQuery(_ terms: [String]) -> [String] {
    var expanded = Set(terms)
    for term in terms {
        let lower = term.lowercased()
        for group in synonymGroups {
            let groupLower = group.map { $0.lowercased() }
            if groupLower.contains(lower) {
                expanded.formUnion(group)
            }
        }
    }
    return Array(expanded)
}
