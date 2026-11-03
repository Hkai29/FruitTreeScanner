// ScanArchiveDetail.swift
// 归档详情：一次**真实读取**的结果。
//
// 三条规矩：
//  1. 定位用存档身份（record.id，文件级），不用树号 —— 同一棵树可以有多次扫描；
//  2. 区分「文件完整」与「结果可靠」：文件在，不代表这次估产可信；读不到就明说读不到，
//     绝不用一份全零的 YieldResult 冒充读取成功；
//  3. IO、版本核验与取消归属都在这一层，不进 SwiftUI body。

import Foundation

/// 一次归档读取的结果。
struct ScanArchiveDetail: Equatable, Sendable {
    /// 存档身份（文件级）。同树的多次扫描靠它区分。
    let recordID: String
    let treeID: String
    let scanDate: Date
    let fruitType: String
    let fileURL: URL
    let fileSizeBytes: Int
    /// 文件层面的完整性：能不能核对这份档案。
    let fileIntegrity: ScanPersistenceState
    /// 算法给出的可靠性。没有就是「未提供」，不拿「文件完整」推高置信度。
    let reliability: String?
    let reading: Reading

    enum Reading: Equatable, Sendable {
        case available(fruitCount: Int, yieldKg: Float)
        case unavailable(reason: String)
    }
}

/// 读取归档详情时要说的话。
///
/// 一次读取请求：要么按存档身份自己去找那一份，要么直接用档案页已经加载好的那一条。
enum ScanArchiveDetailRequest: Equatable, Sendable {
    case recordID(String)
    case record(ScanFileRecord)
}

/// 读取归档详情。
///
/// 所有 IO 都在调用方安排的后台任务里完成；这里不做主线程假设，
/// 也不持有任何「当前选中记录」的状态 —— 那是控制器的事。
struct ScanArchiveDetailLoader: Sendable {
    let repository: ScanRepository

    enum LoadFailure: Error, Equatable, LocalizedError {
        /// 档案目录读不到（目录不可用）—— 与「这条记录不在了」是两件事。
        case archiveUnavailable
        /// 这一条确实不在档案里了。
        case recordMissing
        case resultUnavailable(reason: String)

        var errorDescription: String? {
            switch self {
            case .archiveUnavailable:
                return NSLocalizedString(
                    "history.detail.archive_unavailable",
                    value: "档案目录现在读不到，稍后再试。",
                    comment: "Archive detail: the archive directory cannot be read"
                )
            case .recordMissing:
                return NSLocalizedString(
                    "history.detail.record_missing",
                    value: "这条记录已经不在档案里了。",
                    comment: "Archive detail: the record is gone"
                )
            case .resultUnavailable(let reason):
                return reason
            }
        }
    }

    /// 按存档身份读取。树号相同但不是同一份档案时，读到的是这一份。
    func load(recordID: String) throws -> ScanArchiveDetail {
        guard case .success(let records) = repository.loadHistoryRecords() else {
            throw LoadFailure.archiveUnavailable
        }
        guard let record = records.first(where: { $0.id == recordID }) else {
            throw LoadFailure.recordMissing
        }
        return try makeDetail(for: record)
    }

    /// 用**已经加载好的**那一条读取。
    ///
    /// 档案页本来就有同一批记录；再扫一遍目录等于把每份点云都重新解析一遍，
    /// 打开一条详情不该付这个代价。
    func load(record: ScanFileRecord) throws -> ScanArchiveDetail {
        try makeDetail(for: record)
    }

    private func makeDetail(for record: ScanFileRecord) throws -> ScanArchiveDetail {
        // 列表记录只提供定位；完整性、读数和元数据必须来自同一次当前读取。
        // 与写入/删除共用事务，不能把两次读取间的缓存状态拼成一份“完整”档案。
        try repository.withScanTransaction(at: record.fileURL) {
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: record.fileURL.path)
            } catch {
                let failure = error as NSError
                if failure.domain == NSCocoaErrorDomain &&
                    (failure.code == NSFileNoSuchFileError || failure.code == NSFileReadNoSuchFileError) {
                    throw LoadFailure.recordMissing
                }
                // 权限或其他 IO 故障不是“记录已经删除”。
                throw error
            }
            let unavailableReason = NSLocalizedString(
                "history.detail.result_unavailable",
                value: "这次扫描的结果读不到。",
                comment: "Archive detail: result cannot be read"
            )
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  PLYParserHelper.hasValidPointCloudHeader(at: record.fileURL),
                  let current = PLYParserHelper.parsePLYFile(at: record.fileURL) else {
                // 旧格式 sidecar 本身不能证明源点云仍然存在且有效。
                throw LoadFailure.resultUnavailable(reason: unavailableReason)
            }

            let reading: ScanArchiveDetail.Reading
            if current.persistenceState == .complete {
                // complete 由伴随结果与清单核验产生；单独的 PLY 不会进入这里。
                reading = .available(fruitCount: current.fruitCount, yieldKg: current.yieldKg)
            } else {
                reading = .unavailable(reason: current.persistenceFailureReason ?? unavailableReason)
            }

            return ScanArchiveDetail(
                recordID: record.id,
                treeID: current.treeID,
                scanDate: current.scanDate,
                fruitType: current.fruitType,
                fileURL: record.fileURL,
                fileSizeBytes: (attributes[.size] as? NSNumber)?.intValue ?? 0,
                fileIntegrity: current.persistenceState,
                reliability: current.confidence.isEmpty ? nil : current.confidence,
                reading: reading
            )
        }
    }
}

/// 归档详情的读取状态机。
///
/// 「谁是最新的选择」由 generation 令牌管：较早发起的异步回调回来时，
/// 不得覆盖后来选中的那一条。令牌是**唯一**的裁决者 —— 取消也走令牌
/// （`cancel()` 同样把令牌往前推），所以「旧回调晚回来」这条路必须真的被挡住。
@MainActor
final class ScanArchiveDetailController: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(recordID: String)
        case loaded(ScanArchiveDetail)
        case failed(recordID: String, reason: String)
    }

    @Published private(set) var state: State = .idle

    /// 真正的读取。默认实现在后台任务里做 IO；测试可以注入一条可控时序的读。
    private let read: @Sendable (ScanArchiveDetailRequest) async throws -> ScanArchiveDetail
    private var generation = 0
    private var task: Task<Void, Never>?

    init(loader: ScanArchiveDetailLoader) {
        self.read = { request in
            try await Task.detached(priority: .userInitiated) {
                switch request {
                case .recordID(let recordID):
                    return try loader.load(recordID: recordID)
                case .record(let record):
                    return try loader.load(record: record)
                }
            }.value
        }
    }

    /// 注入一条自定义读取（用于把异步时序固定下来）。
    init(read: @escaping @Sendable (ScanArchiveDetailRequest) async throws -> ScanArchiveDetail) {
        self.read = read
    }

    func load(recordID: String) {
        start(.recordID(recordID))
    }

    func load(record: ScanFileRecord) {
        start(.record(record))
    }

    private func start(_ request: ScanArchiveDetailRequest) {
        generation += 1
        let current = generation
        task?.cancel()
        state = .loading(recordID: request.recordID)
        task = Task { [read] in
            let outcome: Outcome
            do {
                outcome = .loaded(try await read(request))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                outcome = .failed(reason)
            }
            await MainActor.run {
                // 唯一的裁决者：这一次的令牌不是最新的，旧回调就丢弃。
                // （取消也走同一条路 —— cancel() 同样把令牌往前推。）
                guard current == self.generation else { return }
                switch outcome {
                case .loaded(let detail):
                    self.state = .loaded(detail)
                case .failed(let reason):
                    self.state = .failed(recordID: request.recordID, reason: reason)
                }
            }
        }
    }

    /// 离开详情或换一条记录时调用：作废在途的读取。
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        state = .idle
    }

    private enum Outcome: @unchecked Sendable {
        case loaded(ScanArchiveDetail)
        case failed(String)
    }
}

private extension ScanArchiveDetailRequest {
    var recordID: String {
        switch self {
        case .recordID(let recordID): return recordID
        case .record(let record): return record.id
        }
    }
}
