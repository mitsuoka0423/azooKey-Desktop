/// 候補ごとの意味の手がかり（同音異義語を選び分けるための短い説明）の出典
public protocol LiveConversionHintProvider: Sendable {
    /// 手がかりがなければ `nil`
    func hint(for candidate: String, reading: String) -> String?
}

public extension LiveConversionHintProvider {
    /// ひらがな・カタカナの表示と、送り仮名や助詞を除いた語での引き当てをまとめたもの
    func displayHint(for candidate: String, reading: String) -> String {
        if candidate == reading {
            return "ひらがな"
        }
        if candidate == LiveConversionPanelModel.katakana(reading) {
            return "カタカナ"
        }
        if candidate.contains(where: \.isLetter), candidate.allSatisfy(\.isASCII) {
            return "英字"
        }
        if let hint = self.hint(for: candidate, reading: reading) {
            return hint
        }
        let core = Self.stem(candidate)
        if core != candidate, let hint = self.hint(for: core, reading: reading) {
            return hint
        }
        if !core.isEmpty, core.unicodeScalars.allSatisfy({ (0x30A0...0x30FF).contains($0.value) }) {
            return "カタカナ"
        }
        return ""
    }

    /// 末尾のひらがな（送り仮名・助詞）と句読点を除いた語。「橋を」→「橋」
    static func stem(_ text: String) -> String {
        var scalars = Array(text.unicodeScalars)
        while let last = scalars.last, (0x3041...0x3096).contains(last.value) || "、。".unicodeScalars.contains(last) {
            scalars.removeLast()
        }
        // 全部ひらがなだったときは元のまま（「渡る」は「渡」にしない、などの調整は表の側で持つ）
        return scalars.isEmpty ? text : String(String.UnicodeScalarView(scalars))
    }
}

/// 同梱の小さな対応表による手がかり
public struct BundledLiveConversionHintProvider: LiveConversionHintProvider {
    public init() {}

    public func hint(for candidate: String, reading: String) -> String? {
        Self.table[candidate]
    }

    static let table: [String: String] = [
        // はし
        "橋": "川などに架ける", "箸": "食事の道具", "端": "物のへり・すみ", "嘴": "鳥のくちばし", "梯": "はしご",
        // あし・あした
        "明日": "今日の次の日", "足": "体のあし", "脚": "机などのあし", "葦": "水辺の植物",
        // わたる
        "渡る": "向こう側へ行く", "亘る": "期間・範囲に及ぶ", "亙る": "「亘る」の異体字", "渉る": "広く関わる",
        // し
        "市": "まち・市町村", "子": "こども", "死": "死ぬこと", "氏": "姓・〜さん", "紙": "書く・包むもの", "詩": "ポエム",
        // は・した ほか
        "葉": "植物の葉", "歯": "口の中の歯", "下": "下のほう", "舌": "口の中の舌", "綿": "もめんわた",
        // きしゃ
        "記者": "取材して書く人", "汽車": "蒸気機関車", "帰社": "会社に戻る", "貴社": "相手の会社",
        // こうさつ・かいぎ ほか
        "考察": "よく考える", "絞殺": "首を絞めて殺す", "高札": "立て札",
        "会議": "集まって話し合う", "懐疑": "疑いを持つ",
        "開催": "催しを開く", "皆済": "すべて返す",
        "天気": "空のようす", "転機": "変わり目", "転記": "書き写す",
        "学生": "学校で学ぶ人", "学制": "学校の制度",
        // よく迷う同音異義語
        "機会": "チャンス", "機械": "動力で動く装置",
        "意外": "思いがけない", "以外": "それを除いたほか",
        "関心": "興味", "感心": "感じ入る", "歓心": "喜ぶ気持ち",
        "保証": "請け合う", "保障": "守る", "補償": "償う",
        "回答": "問いに答える", "解答": "問題を解く",
        "追求": "求め続ける", "追及": "問い詰める", "追究": "究める",
        "異動": "職場が変わる", "移動": "場所を変える", "異同": "違い",
        "対象": "向ける相手", "対称": "つり合い", "対照": "比べる",
        "講演": "人前で話す", "公演": "舞台で演じる", "公園": "遊び・憩いの場",
        "作成": "書類などを作る", "作製": "物を作る",
        "暑い": "気温が高い", "熱い": "温度が高い", "厚い": "厚みがある",
        "早い": "時期・時刻", "速い": "スピード",
        "会う": "人と会う", "合う": "一致する", "遭う": "災難にあう",
        "聞く": "耳で聞く", "効く": "効果がある", "利く": "機能する",
        "変える": "別のものにする", "代える": "代わりにする", "替える": "取り替える", "換える": "交換する",
        "測る": "長さ・深さ", "計る": "時間・数", "量る": "重さ・容積", "図る": "企てる"
    ]
}
