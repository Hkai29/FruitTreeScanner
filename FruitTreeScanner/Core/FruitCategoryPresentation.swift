// Display labels live outside the numerical fusion domain.
extension FruitCategory {
    var displayName: String {
        switch self {
        case .apple: return "苹果"
        case .orange: return "橙子"
        case .mandarin: return "柑橘"
        case .pomelo: return "柚子"
        case .pear: return "梨"
        case .peach: return "桃子"
        case .cherry: return "樱桃"
        case .grape: return "葡萄"
        case .persimmon: return "柿子"
        case .mango: return "芒果"
        case .kiwi: return "猕猴桃"
        case .plum: return "李子"
        case .pomegranate: return "石榴"
        case .loquat: return "枇杷"
        case .lychee: return "荔枝"
        case .longan: return "龙眼"
        case .bayberry: return "杨梅"
        case .jujube: return "枣"
        case .hawthorn: return "山楂"
        case .fig: return "无花果"
        case .papaya: return "木瓜"
        case .chestnut: return "板栗"
        case .mulberry: return "桑葚"
        case .blueberry: return "蓝莓"
        case .strawberry: return "草莓"
        case .coconut: return "椰子"
        }
    }
}

extension FruitVarietyParams {
    var displayName: String {
        fruitCategory?.displayName ?? category
    }
}
