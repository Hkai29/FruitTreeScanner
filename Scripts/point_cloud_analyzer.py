"""
point_cloud_analyzer.py
点云质量分析工具 —— 从 iPad 导出 PLY 后在电脑上验证扫描质量

用法:
    python point_cloud_analyzer.py <ply_file_or_folder> [--mode quality|cluster|full]

模式:
    quality  - 点云质量指标 + 3D 可视化
    cluster  - 复刻 iOS 端 DBSCAN 聚类 + 果实检测
    full     - 以上全部 + 端到端产量估算
"""

import sys
import os
import struct
import argparse
import numpy as np
from pathlib import Path

try:
    import open3d as o3d
    HAS_O3D = True
except ImportError:
    HAS_O3D = False

try:
    import matplotlib.pyplot as plt
    HAS_PLT = True
except ImportError:
    HAS_PLT = False


# ============================================================
# PLY 读取
# ============================================================

def read_ply(filepath: str):
    """读取 ASCII PLY 文件，返回 (positions, colors) numpy 数组"""
    positions = []
    colors = []

    with open(filepath, 'r') as f:
        line = f.readline().strip()
        if line != 'ply':
            raise ValueError(f"不是 PLY 文件: {filepath}")

        format_type = 'ascii'
        vertex_count = 0
        header_end = False

        while not header_end:
            line = f.readline().strip()
            if line.startswith('format'):
                format_type = line.split()[1]
            elif line.startswith('element vertex'):
                vertex_count = int(line.split()[2])
            elif line == 'end_header':
                header_end = True

        if format_type != 'ascii':
            raise ValueError(f"只支持 ASCII 格式 PLY，当前: {format_type}")

        for _ in range(vertex_count):
            parts = f.readline().strip().split()
            if len(parts) >= 6:
                x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                r, g, b = int(parts[3]), int(parts[4]), int(parts[5])
                positions.append([x, y, z])
                colors.append([r / 255.0, g / 255.0, b / 255.0])

    return np.array(positions), np.array(colors)


def read_ply_binary(filepath: str):
    """读取二进制 PLY（如果 iPad 导出的是 binary 格式）"""
    positions = []
    colors = []

    with open(filepath, 'rb') as f:
        line = f.readline().decode().strip()
        if line != 'ply':
            raise ValueError(f"不是 PLY 文件: {filepath}")

        format_type = 'ascii'
        vertex_count = 0
        header_end = False

        while not header_end:
            line = f.readline().decode().strip()
            if line.startswith('format'):
                format_type = line.split()[1]
            elif line.startswith('element vertex'):
                vertex_count = int(line.split()[2])
            elif line == 'end_header':
                header_end = True

        if format_type == 'binary_little_endian':
            for _ in range(vertex_count):
                data = f.read(6 * 4)
                vals = struct.unpack('<6f', data)
                positions.append([vals[0], vals[1], vals[2]])
                colors.append([min(vals[3], 1.0), min(vals[4], 1.0), min(vals[5], 1.0)])
        else:
            for _ in range(vertex_count):
                line = f.readline().decode().strip()
                parts = line.split()
                x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                r, g, b = int(parts[3]), int(parts[4]), int(parts[5])
                positions.append([x, y, z])
                colors.append([r / 255.0, g / 255.0, b / 255.0])

    return np.array(positions), np.array(colors)


def load_ply(filepath: str):
    """自动检测格式并加载 PLY"""
    try:
        return read_ply(filepath)
    except (ValueError, UnicodeDecodeError):
        return read_ply_binary(filepath)


# ============================================================
# 颜色工具（复刻 iOS 端 FruitCategory.isFruitColor）
# ============================================================

def rgb_to_hsv(rgb):
    """RGB [0-1] → HSV [0-360, 0-1, 0-1]"""
    r, g, b = rgb
    cmax = max(r, g, b)
    cmin = min(r, g, b)
    delta = cmax - cmin

    if delta < 1e-6:
        h = 0
    elif cmax == r:
        h = 60 * (((g - b) / delta) % 6)
    elif cmax == g:
        h = 60 * (((b - r) / delta) + 2)
    else:
        h = 60 * (((r - g) / delta) + 4)

    s = 0 if cmax < 1e-6 else delta / cmax
    v = cmax

    return h, s, v


def is_fruit_color(rgb):
    """复刻 iOS 端 FruitCategory.isFruitColor()"""
    h, s, v = rgb_to_hsv(rgb)

    if v < 0.10 or v > 0.98:
        return False
    if s < 0.06:
        return False

    if (0 <= h <= 25) or (335 <= h <= 360):
        if s >= 0.18 and v >= 0.18:
            return True
    if 15 <= h <= 50:
        if s >= 0.25 and v >= 0.25:
            return True
    if 45 <= h <= 95:
        if s >= 0.10 and v >= 0.25:
            return True
    if 80 <= h <= 150:
        if s >= 0.12 and 0.12 <= v <= 0.70:
            return True
    if 240 <= h <= 300:
        if s >= 0.12 and v >= 0.12:
            return True
    if 300 <= h <= 340:
        if s >= 0.12 and v >= 0.12:
            return True
    if 10 <= h <= 50:
        if 0.10 <= s <= 0.55 and 0.15 <= v <= 0.55:
            return True
    if (0 <= h <= 20) or (340 <= h <= 360):
        if s >= 0.30 and 0.12 <= v <= 0.50:
            return True

    return False


# ============================================================
# 质量分析
# ============================================================

def analyze_quality(positions, colors, filepath=""):
    """分析点云质量，打印报告"""
    n = len(positions)
    print(f"\n{'='*60}")
    print(f"  点云质量报告: {os.path.basename(filepath)}")
    print(f"{'='*60}")

    if n == 0:
        print("  ❌ 点云为空！")
        return

    centroid = positions.mean(axis=0)
    dists = np.linalg.norm(positions - centroid, axis=1)

    print(f"  总点数:       {n:,}")
    print(f"  质心:         ({centroid[0]:.3f}, {centroid[1]:.3f}, {centroid[2]:.3f})")
    print(f"  半径范围:     {dists.min():.3f} ~ {dists.max():.3f} m")
    print(f"  半径中位数:   {np.median(dists):.3f} m")

    bbox_min = positions.min(axis=0)
    bbox_max = positions.max(axis=0)
    bbox_size = bbox_max - bbox_min
    print(f"  包围盒尺寸:   {bbox_size[0]:.2f} × {bbox_size[1]:.2f} × {bbox_size[2]:.2f} m")

    depth = positions[:, 2]
    print(f"  深度范围:     {depth.min():.2f} ~ {depth.max():.2f} m")

    fruit_mask = np.array([is_fruit_color(c) for c in colors])
    fruit_count = fruit_mask.sum()
    fruit_ratio = fruit_count / n * 100
    print(f"  果实颜色点:   {fruit_count:,} ({fruit_ratio:.1f}%)")

    if fruit_count > 0:
        fruit_positions = positions[fruit_mask]
        fruit_centroid = fruit_positions.mean(axis=0)
        fruit_dists = np.linalg.norm(fruit_positions - fruit_centroid, axis=1)
        print(f"  果实点半径:   {fruit_dists.min():.3f} ~ {fruit_dists.max():.3f} m")

    voxel_size = 0.01
    voxel_indices = np.floor(positions / voxel_size).astype(int)
    unique_voxels = len(set(map(tuple, voxel_indices)))
    volume = bbox_size[0] * bbox_size[1] * bbox_size[2]
    density = n / max(volume, 0.001)
    print(f"  体素数(1cm):  {unique_voxels:,}")
    print(f"  点密度:       {density:.0f} pts/m³")

    nn_dists = []
    sample_size = min(n, 5000)
    sample_idx = np.random.choice(n, sample_size, replace=False)
    for i in sample_idx:
        d = np.linalg.norm(positions - positions[i], axis=1)
        d[i] = np.inf
        nn_dists.append(d.min())
    nn_dists = np.array(nn_dists)
    print(f"  最近邻距离:   mean={nn_dists.mean():.4f}m, median={np.median(nn_dists):.4f}m, p90={np.percentile(nn_dists, 90):.4f}m")

    print(f"\n  质量评估:")
    if n < 1000:
        print(f"    ❌ 点数过少 ({n})，扫描不充分")
    elif n < 10000:
        print(f"    ⚠️  点数偏少 ({n})，建议多扫几圈")
    elif n < 50000:
        print(f"    ✅ 点数尚可 ({n})，基本够用")
    else:
        print(f"    ✅ 点数充足 ({n})，扫描质量好")

    if fruit_ratio < 1:
        print(f"    ❌ 果实颜色点太少 ({fruit_ratio:.1f}%)，可能没有果实或颜色过滤有误")
    elif fruit_ratio < 5:
        print(f"    ⚠️  果实颜色点偏少 ({fruit_ratio:.1f}%)")
    elif fruit_ratio < 30:
        print(f"    ✅ 果实颜色点正常 ({fruit_ratio:.1f}%)")
    else:
        print(f"    ⚠️  果实颜色点过多 ({fruit_ratio:.1f}%)，可能有误检")

    if nn_dists.mean() > 0.05:
        print(f"    ⚠️  点间距偏大 ({nn_dists.mean():.4f}m)，建议近距离扫描")
    else:
        print(f"    ✅ 点间距合理 ({nn_dists.mean():.4f}m)")

    return {
        'n_points': n,
        'fruit_ratio': fruit_ratio,
        'density': density,
        'nn_mean': nn_dists.mean(),
        'bbox_size': bbox_size,
    }


# ============================================================
# DBSCAN 聚类（复刻 iOS 端 PointCloudCluster）
# ============================================================

def dbscan_clustering(positions, colors, eps=0.05, min_points=3,
                      min_diameter=0.015, max_diameter=0.20,
                      sphericity_threshold=0.3):
    """复刻 iOS 端 DBSCAN 聚类 + 球形度过滤"""

    from scipy.spatial import cKDTree

    fruit_mask = np.array([is_fruit_color(c) for c in colors])
    fruit_positions = positions[fruit_mask]

    if len(fruit_positions) < min_points:
        print(f"  ❌ 果实颜色点不足 ({len(fruit_positions)} < {min_points})")
        return []

    tree = cKDTree(fruit_positions)
    n = len(fruit_positions)

    labels = np.full(n, -1, dtype=int)
    cluster_id = 0

    for i in range(n):
        if labels[i] != -1:
            continue

        neighbors = tree.query_ball_point(fruit_positions[i], eps)

        if len(neighbors) < min_points:
            continue

        labels[i] = cluster_id
        seed_set = list(neighbors)
        seed_set = [s for s in seed_set if s != i]

        j = 0
        while j < len(seed_set):
            q = seed_set[j]
            if labels[q] == -1:
                labels[q] = cluster_id
            elif labels[q] != -1 and labels[q] != cluster_id:
                j += 1
                continue
            else:
                j += 1
                continue

            labels[q] = cluster_id
            q_neighbors = tree.query_ball_point(fruit_positions[q], eps)

            if len(q_neighbors) >= min_points:
                for n_idx in q_neighbors:
                    if labels[n_idx] <= 0:
                        if n_idx not in seed_set:
                            seed_set.append(n_idx)

            j += 1

        cluster_id += 1

    candidates = []
    for cid in range(cluster_id):
        cluster_mask = labels == cid
        cluster_pts = fruit_positions[cluster_mask]

        if len(cluster_pts) < min_points:
            continue

        center = cluster_pts.mean(axis=0)
        dists = np.linalg.norm(cluster_pts - center, axis=1)
        sorted_dists = np.sort(dists)
        idx90 = max(0, int(len(sorted_dists) * 0.90) - 1)
        diameter = sorted_dists[idx90] * 2.0

        if diameter < min_diameter or diameter > max_diameter:
            continue

        cov = np.cov(cluster_pts.T)
        eigenvalues = np.sort(np.linalg.eigvalsh(cov))[::-1]

        if eigenvalues[0] < 1e-8:
            continue

        sphericity = (eigenvalues[2] / eigenvalues[0]) ** 0.5

        if sphericity < sphericity_threshold:
            continue

        candidates.append({
            'center': center,
            'diameter': diameter,
            'sphericity': sphericity,
            'point_count': len(cluster_pts),
            'cluster_id': cid,
        })

    return candidates


def analyze_clusters(positions, colors, filepath=""):
    """聚类分析 + 打印报告"""
    print(f"\n{'='*60}")
    print(f"  果实聚类分析: {os.path.basename(filepath)}")
    print(f"{'='*60}")

    candidates = dbscan_clustering(positions, colors)

    if not candidates:
        print("  ❌ 未检测到果实候选")
        return []

    print(f"  检测到 {len(candidates)} 个果实候选:\n")
    print(f"  {'#':>3}  {'直径(cm)':>8}  {'球形度':>6}  {'点数':>5}  {'位置(x,y,z)':>24}  {'体积(cm³)':>10}  {'估算重量(g)':>10}")
    print(f"  {'---':>3}  {'--------':>8}  {'------':>6}  {'-----':>5}  {'------------------------':>24}  {'----------':>10}  {'----------':>10}")

    total_weight = 0
    for i, c in enumerate(candidates):
        radius_cm = c['diameter'] * 100 / 2
        volume_cm3 = (4.0 / 3.0) * np.pi * radius_cm ** 3
        density = 0.85
        weight_g = volume_cm3 * density
        total_weight += weight_g

        print(f"  {i+1:>3}  {c['diameter']*100:>8.2f}  {c['sphericity']:>6.3f}  {c['point_count']:>5}  "
              f"({c['center'][0]:>7.3f},{c['center'][1]:>7.3f},{c['center'][2]:>7.3f})  "
              f"{volume_cm3:>10.1f}  {weight_g:>10.1f}")

    print(f"\n  📊 合计: {len(candidates)} 个果实, 估算总重 {total_weight:.0f}g ({total_weight/1000:.2f}kg)")

    return candidates


# ============================================================
# 3D 可视化
# ============================================================

def visualize(positions, colors, candidates=None):
    """3D 可视化点云 + 检测到的果实"""
    if not HAS_O3D:
        print("  ⚠️  未安装 open3d，跳过 3D 可视化")
        print("  安装: pip install open3d")
        return

    pcd = o3d.geometry.PointCloud()
    pcd.points = o3d.utility.Vector3dVector(positions)
    pcd.colors = o3d.utility.Vector3dVector(colors)

    geometries = [pcd]

    if candidates:
        for c in candidates:
            sphere = o3d.geometry.TriangleMesh.create_sphere(
                radius=c['diameter'] / 2, resolution=20
            )
            sphere.translate(c['center'])
            sphere.paint_uniform_color([1.0, 0.3, 0.0])
            sphere.compute_vertex_normals()
            geometries.append(sphere)

    o3d.draw_geometries(geometries, window_name="点云分析 (橙色球=检测到的果实)")


def plot_color_histogram(colors):
    """绘制颜色分布直方图"""
    if not HAS_PLT:
        print("  ⚠️  未安装 matplotlib，跳过颜色直方图")
        print("  安装: pip install matplotlib")
        return

    hsv = np.array([rgb_to_hsv(c) for c in colors])

    fig, axes = plt.subplots(1, 3, figsize=(15, 4))

    axes[0].hist(hsv[:, 0], bins=36, range=(0, 360), color='steelblue', edgecolor='black')
    axes[0].set_title('Hue Distribution')
    axes[0].set_xlabel('Hue (degrees)')

    axes[1].hist(hsv[:, 1], bins=50, range=(0, 1), color='seagreen', edgecolor='black')
    axes[1].set_title('Saturation Distribution')
    axes[1].set_xlabel('Saturation')

    axes[2].hist(hsv[:, 2], bins=50, range=(0, 1), color='salmon', edgecolor='black')
    axes[2].set_title('Value Distribution')
    axes[2].set_xlabel('Value')

    fruit_mask = np.array([is_fruit_color(c) for c in colors])
    if fruit_mask.any():
        fig.suptitle(f'Color Distribution (fruit points: {fruit_mask.sum()}/{len(colors)} = {fruit_mask.mean()*100:.1f}%)')
    else:
        fig.suptitle('Color Distribution (no fruit points detected)')

    plt.tight_layout()
    plt.savefig('color_histogram.png', dpi=150)
    print(f"  📊 颜色直方图已保存: color_histogram.png")
    plt.close()


def plot_depth_distribution(positions):
    """绘制深度分布图"""
    if not HAS_PLT:
        return

    dists = np.linalg.norm(positions, axis=1)

    fig, ax = plt.subplots(1, 1, figsize=(10, 4))
    ax.hist(dists, bins=100, color='steelblue', edgecolor='black')
    ax.set_title('Depth Distribution (distance from origin)')
    ax.set_xlabel('Distance (m)')
    ax.set_ylabel('Point count')
    ax.axvline(x=0.5, color='red', linestyle='--', label='min depth (0.5m)')
    ax.axvline(x=5.0, color='red', linestyle='--', label='max depth (5.0m)')
    ax.legend()
    plt.tight_layout()
    plt.savefig('depth_distribution.png', dpi=150)
    print(f"  📊 深度分布图已保存: depth_distribution.png")
    plt.close()


# ============================================================
# 端到端验证
# ============================================================

def full_pipeline(filepath, ground_truth_count=None, ground_truth_weight_kg=None):
    """端到端验证：质量 → 聚类 → 产量估算 → 对比真实值"""
    positions, colors = load_ply(filepath)

    quality = analyze_quality(positions, colors, filepath)
    candidates = analyze_clusters(positions, colors, filepath)

    if candidates and HAS_PLT:
        plot_color_histogram(colors)
        plot_depth_distribution(positions)

    if ground_truth_count is not None:
        detected = len(candidates)
        error = abs(detected - ground_truth_count) / ground_truth_count * 100
        print(f"\n  🎯 计数验证:")
        print(f"     检测: {detected}, 真实: {ground_truth_count}, 误差: {error:.1f}%")
        if error <= 15:
            print(f"     ✅ 在 15% 误差范围内")
        else:
            print(f"     ❌ 超出 15% 误差范围")

    if ground_truth_weight_kg is not None and candidates:
        total_weight = sum(
            (4.0/3.0) * np.pi * (c['diameter']*100/2)**3 * 0.85 / 1000
            for c in candidates
        )
        error = abs(total_weight - ground_truth_weight_kg) / ground_truth_weight_kg * 100
        print(f"\n  🎯 产量验证:")
        print(f"     估算: {total_weight:.2f}kg, 真实: {ground_truth_weight_kg:.2f}kg, 误差: {error:.1f}%")
        if error <= 15:
            print(f"     ✅ 在 15% 误差范围内")
        else:
            print(f"     ❌ 超出 15% 误差范围")

    visualize(positions, colors, candidates)

    return quality, candidates


# ============================================================
# 主入口
# ============================================================

def main():
    parser = argparse.ArgumentParser(description='点云质量分析工具')
    parser.add_argument('input', help='PLY 文件或包含 PLY 文件的文件夹')
    parser.add_argument('--mode', choices=['quality', 'cluster', 'full'], default='full',
                        help='分析模式: quality=质量, cluster=聚类, full=全部')
    parser.add_argument('--gt-count', type=int, default=None, help='真实果实数量（用于验证）')
    parser.add_argument('--gt-weight', type=float, default=None, help='真实产量(kg)（用于验证）')
    parser.add_argument('--eps', type=float, default=0.05, help='DBSCAN eps 参数(m)')
    parser.add_argument('--min-points', type=int, default=3, help='DBSCAN minPoints')
    parser.add_argument('--no-viz', action='store_true', help='跳过 3D 可视化')

    args = parser.parse_args()

    input_path = Path(args.input)

    if input_path.is_dir():
        ply_files = sorted(input_path.glob('**/*.ply'))
        if not ply_files:
            print(f"❌ 在 {input_path} 中未找到 PLY 文件")
            sys.exit(1)
        print(f"找到 {len(ply_files)} 个 PLY 文件")
    else:
        ply_files = [input_path]

    for ply_file in ply_files:
        print(f"\n{'#'*60}")
        print(f"  处理: {ply_file}")
        print(f"{'#'*60}")

        try:
            positions, colors = load_ply(str(ply_file))
        except Exception as e:
            print(f"  ❌ 读取失败: {e}")
            continue

        if args.mode == 'quality':
            analyze_quality(positions, colors, str(ply_file))
            if HAS_PLT:
                plot_color_histogram(colors)
                plot_depth_distribution(positions)
            if not args.no_viz:
                visualize(positions, colors)

        elif args.mode == 'cluster':
            candidates = analyze_clusters(positions, colors, str(ply_file))
            if not args.no_viz:
                visualize(positions, colors, candidates)

        elif args.mode == 'full':
            full_pipeline(
                str(ply_file),
                ground_truth_count=args.gt_count,
                ground_truth_weight_kg=args.gt_weight,
            )


if __name__ == '__main__':
    main()
