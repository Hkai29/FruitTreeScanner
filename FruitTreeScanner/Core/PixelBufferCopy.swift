// PixelBufferCopy.swift
// CVPixelBuffer copy helpers for retaining AR frame data safely.

import CoreVideo
import Foundation

/// CVPixelBuffer 深拷贝（避免持有 ARFrame 可复用内存池中的 buffer）
func duplicatePixelBuffer(input: CVPixelBuffer) -> CVPixelBuffer? {
    var copyOut: CVPixelBuffer?
    let w = CVPixelBufferGetWidth(input)
    let h = CVPixelBufferGetHeight(input)
    let fmt = CVPixelBufferGetPixelFormatType(input)
    let attachments = CVBufferCopyAttachments(input, .shouldPropagate)
    let createStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        w,
        h,
        fmt,
        attachments,
        &copyOut
    )
    guard createStatus == kCVReturnSuccess, let output = copyOut else { return nil }

    guard CVPixelBufferLockBaseAddress(input, .readOnly) == kCVReturnSuccess else { return nil }
    guard CVPixelBufferLockBaseAddress(output, []) == kCVReturnSuccess else {
        CVPixelBufferUnlockBaseAddress(input, .readOnly)
        return nil
    }
    defer {
        CVPixelBufferUnlockBaseAddress(input, .readOnly)
        CVPixelBufferUnlockBaseAddress(output, [])
    }

    let planeCount = CVPixelBufferGetPlaneCount(input)
    if planeCount > 0 {
        for plane in 0..<planeCount {
            guard let src = CVPixelBufferGetBaseAddressOfPlane(input, plane),
                  let dst = CVPixelBufferGetBaseAddressOfPlane(output, plane)
            else { return nil }

            let rows = CVPixelBufferGetHeightOfPlane(input, plane)
            let srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(input, plane)
            let dstBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(output, plane)
            let bytesPerRow = min(srcBytesPerRow, dstBytesPerRow)

            for row in 0..<rows {
                memcpy(
                    dst.advanced(by: row * dstBytesPerRow),
                    src.advanced(by: row * srcBytesPerRow),
                    bytesPerRow
                )
            }
        }
    } else if let src = CVPixelBufferGetBaseAddress(input),
              let dst = CVPixelBufferGetBaseAddress(output) {
        let rows = CVPixelBufferGetHeight(input)
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(input)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(output)
        let bytesPerRow = min(srcBytesPerRow, dstBytesPerRow)

        for row in 0..<rows {
            memcpy(
                dst.advanced(by: row * dstBytesPerRow),
                src.advanced(by: row * srcBytesPerRow),
                bytesPerRow
            )
        }
    } else {
        return nil
    }

    return output
}
