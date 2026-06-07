// Log.swift
// 统一日志系统 - 基于 os.Logger，按子系统分类

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.fruittreescanner"

    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let detection = Logger(subsystem: subsystem, category: "detection")
    static let fusion = Logger(subsystem: subsystem, category: "fusion")
    static let pointCloud = Logger(subsystem: subsystem, category: "pointCloud")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let render = Logger(subsystem: subsystem, category: "render")
    static let gps = Logger(subsystem: subsystem, category: "gps")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let general = Logger(subsystem: subsystem, category: "general")
}
