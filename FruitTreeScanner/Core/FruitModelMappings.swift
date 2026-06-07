// FruitModelMappings.swift
// YOLO 模型类别 ID 到果实类别的映射

enum COCOFruit: Int, CaseIterable {
    case apple = 77
    case orange = 78
    case banana = 52

    var fruitCategory: FruitCategory? {
        switch self {
        case .apple: return .apple
        case .orange: return .orange
        case .banana: return .pear
        }
    }
}

enum CustomFruitID: Int, CaseIterable {
    case apple = 0
    case orange = 1
    case mandarin = 2
    case pomelo = 3
    case pear = 4
    case peach = 5
    case cherry = 6
    case grape = 7
    case persimmon = 8
    case mango = 9
    case kiwi = 10
    case plum = 11
    case pomegranate = 12
    case loquat = 13
    case lychee = 14
    case longan = 15
    case bayberry = 16
    case jujube = 17
    case hawthorn = 18
    case fig = 19
    case papaya = 20
    case chestnut = 21
    case mulberry = 22
    case blueberry = 23
    case strawberry = 24
    case coconut = 25

    var fruitCategory: FruitCategory {
        FruitCategory.allCases[rawValue]
    }
}

extension FruitCategory {
    static func fromCOCO(_ cocoID: Int) -> FruitCategory? {
        COCOFruit(rawValue: cocoID)?.fruitCategory
    }

    static func fromCustomModel(_ id: Int) -> FruitCategory? {
        CustomFruitID(rawValue: id)?.fruitCategory
    }
}
