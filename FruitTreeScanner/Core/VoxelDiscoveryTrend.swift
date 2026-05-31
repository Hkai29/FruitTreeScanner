enum VoxelDiscoveryTrend: Equatable {
    case collecting
    case increasing
    case decreasing
    case stable

    var description: String {
        switch self {
        case .collecting:
            return "收集中..."
        case .increasing:
            return "持续发现新区域"
        case .decreasing:
            return "趋于稳定"
        case .stable:
            return "覆盖完成"
        }
    }
}
