// KDTree.swift
// Spatial range queries for point-cloud processing.

import simd

struct KDTree {
    private var nodes: [KDNode]
    private var rootNodeIndex: Int?

    struct KDNode {
        var point: SIMD3<Float>
        var index: Int
        var left: Int?
        var right: Int?
        var axis: Int
    }

    init(points: [SIMD3<Float>]) {
        nodes = []
        rootNodeIndex = nil
        guard !points.isEmpty else {
            return
        }

        var indices = Array(points.indices)
        rootNodeIndex = buildTree(points: points, indices: &indices, depth: 0, range: 0..<points.count)
    }

    private mutating func buildTree(points: [SIMD3<Float>], indices: inout [Int], depth: Int, range: Range<Int>) -> Int? {
        guard range.lowerBound < range.upperBound else { return nil }

        let axis = depth % 3
        let mid = (range.lowerBound + range.upperBound) / 2

        indices[range].sort { a, b in
            let posA = points[a]
            let posB = points[b]
            if axis == 0 {
                return posA.x < posB.x
            } else if axis == 1 {
                return posA.y < posB.y
            } else {
                return posA.z < posB.z
            }
        }
        let pivotIndex = indices[mid]

        let leftRange: Range<Int>? = range.lowerBound < mid ? range.lowerBound..<mid : nil
        let rightRange: Range<Int>? = mid + 1 < range.upperBound ? mid + 1..<range.upperBound : nil

        let leftChildId: Int? = leftRange != nil ? buildTree(points: points, indices: &indices, depth: depth + 1, range: leftRange!) : nil
        let rightChildId: Int? = rightRange != nil ? buildTree(points: points, indices: &indices, depth: depth + 1, range: rightRange!) : nil

        let node = KDNode(
            point: points[pivotIndex],
            index: pivotIndex,
            left: leftChildId,
            right: rightChildId,
            axis: axis
        )
        nodes.append(node)

        return nodes.count - 1
    }

    func rangeQuery(center: SIMD3<Float>, radius: Float) -> [Int] {
        guard let rootNodeIndex else { return [] }
        var result: [Int] = []
        let radiusSq = radius * radius
        rangeSearch(nodeIndex: rootNodeIndex, center: center, radiusSq: radiusSq, result: &result)
        return result
    }

    func kNearest(center: SIMD3<Float>, k: Int) -> [Int] {
        guard let rootNodeIndex, k > 0 else { return [] }
        var heap = BoundedMaxHeap(capacity: k)
        nearestSearch(nodeIndex: rootNodeIndex, center: center, heap: &heap)
        return heap.indices()
    }

    private func rangeSearch(nodeIndex: Int, center: SIMD3<Float>, radiusSq: Float, result: inout [Int]) {
        guard nodeIndex < nodes.count else { return }

        let node = nodes[nodeIndex]
        let distSq = simd_distance_squared(node.point, center)

        if distSq <= radiusSq {
            result.append(node.index)
        }

        let diff = center[node.axis] - node.point[node.axis]
        let diffSq = diff * diff

        if diff <= 0 || diffSq <= radiusSq, let left = node.left {
            rangeSearch(nodeIndex: left, center: center, radiusSq: radiusSq, result: &result)
        }
        if diff >= 0 || diffSq <= radiusSq, let right = node.right {
            rangeSearch(nodeIndex: right, center: center, radiusSq: radiusSq, result: &result)
        }
    }

    private func nearestSearch(nodeIndex: Int, center: SIMD3<Float>, heap: inout BoundedMaxHeap) {
        guard nodeIndex < nodes.count else { return }

        let node = nodes[nodeIndex]
        let dist = simd_distance_squared(node.point, center)
        heap.insert(index: node.index, distSq: dist)

        let diff = center[node.axis] - node.point[node.axis]
        let nearChild = diff < 0 ? node.left : node.right
        let farChild = diff < 0 ? node.right : node.left

        if let near = nearChild {
            nearestSearch(nodeIndex: near, center: center, heap: &heap)
        }
        if let far = farChild, diff * diff < heap.worstDistSq {
            nearestSearch(nodeIndex: far, center: center, heap: &heap)
        }
    }
}

private struct BoundedMaxHeap {
    private var entries: [(index: Int, distSq: Float)] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        entries.reserveCapacity(capacity + 1)
    }

    var worstDistSq: Float {
        entries.count < capacity ? .greatestFiniteMagnitude : entries[0].distSq
    }

    mutating func insert(index: Int, distSq: Float) {
        if entries.count < capacity {
            entries.append((index, distSq))
            if entries.count == capacity { buildHeap() }
        } else if distSq < entries[0].distSq {
            entries[0] = (index, distSq)
            siftDown(0)
        }
    }

    func indices() -> [Int] {
        entries.map { $0.index }
    }

    private mutating func buildHeap() {
        for i in stride(from: entries.count / 2 - 1, through: 0, by: -1) {
            siftDown(i)
        }
    }

    private mutating func siftDown(_ i: Int) {
        var parent = i
        while true {
            var largest = parent
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            if left < entries.count && entries[left].distSq > entries[largest].distSq { largest = left }
            if right < entries.count && entries[right].distSq > entries[largest].distSq { largest = right }
            if largest == parent { break }
            entries.swapAt(parent, largest)
            parent = largest
        }
    }
}
