enum VoxelDiscoveryTrend: Equatable {
    case collecting
    case increasing
    case decreasing
    case stable

    var description: String {
        switch self {
        case .collecting:
            return L10n.VoxelTrend.collecting
        case .increasing:
            return L10n.VoxelTrend.discovering
        case .decreasing:
            return L10n.VoxelTrend.stabilizing
        case .stable:
            return L10n.VoxelTrend.complete
        }
    }
}
