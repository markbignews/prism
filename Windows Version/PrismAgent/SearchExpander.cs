namespace PrismAgent;

public static class SearchExpander
{
    private static readonly string[][] Groups = {
        new[]{"悲伤","难过","伤心","心痛","沮丧","低落","抑郁","sad","depressed"},
        new[]{"愤怒","生气","恼火","烦躁","不爽","火大","angry","furious"},
        new[]{"恐惧","害怕","担心","焦虑","紧张","不安","fear","anxiety","anxious"},
        new[]{"羞耻","丢脸","尴尬","难堪","shame","embarrassed"},
        new[]{"孤独","寂寞","孤单","lonely","alone"},
        new[]{"嫉妒","羡慕","眼红","jealous","envy"},
        new[]{"内疚","愧疚","亏欠","自责","后悔","遗憾","guilt","regret"},
        new[]{"挣扎","煎熬","痛苦","折磨","崩溃","绝望","pain","suffering"},
        new[]{"倦怠","疲倦","疲惫","累","失眠","噩梦","exhausted"},
        new[]{"释然","放下","接受","想开","放手","let go","acceptance"},
        new[]{"希望","期待","盼望","憧憬","hope","hopeful"},
        new[]{"困惑","迷茫","不清楚","不明白","confused","lost"},
        new[]{"妈妈","母亲","妈","mom","mother"}, new[]{"爸爸","父亲","爸","爹","dad","father"},
        new[]{"家庭","父母","爸妈","家长","family","parents"},
        new[]{"前任","前女友","前男友","ex","前妻","前夫"},
        new[]{"分手","分开","结束","breakup","离婚"},
        new[]{"暧昧","暗恋","追求","拒绝","复合","crush","reject"},
        new[]{"背叛","出轨","劈腿","cheat","betray"},
        new[]{"朋友","闺蜜","兄弟","好友","死党","friend"},
        new[]{"同事","老板","上司","领导","职场","工作","work","boss"},
        new[]{"辞职","裁员","失业","创业","压力","stress","laid off"},
        new[]{"搬家","离开","回去","回来","move","leave"},
        new[]{"走出来","move on","释怀","忘记","放下"},
        new[]{"自信","自卑","自尊","怀疑","内耗","insecure"},
        new[]{"吵架","争吵","冷战","冲突","矛盾","fight","argue"},
        new[]{"道歉","对不起","原谅","sorry","apologize"},
        new[]{"欺骗","撒谎","说谎","隐瞒","lie","deceive"},
        new[]{"控制","操纵","掌控","control","manipulate"},
    };

    public static string[] Expand(string[] terms)
    {
        var set = new HashSet<string>(terms);
        foreach (var t in terms)
        {
            var lower = t.ToLowerInvariant();
            foreach (var g in Groups)
                if (g.Any(x => x.ToLowerInvariant() == lower))
                    foreach (var s in g) set.Add(s);
        }
        return set.ToArray();
    }
}
