// DesignSystemContrastTests.swift
// 回归测试：浅色工作区与深色画布上的正文级文字必须满足 WCAG AA（4.5:1）。
//
// 背景：一次实测发现 muted/attention 在纸底上只有 3.42/4.03，
// 不满足小字号的最低对比要求。本测试把可读性下限固化下来，
// 避免后续调整配色时再次把日期、单位、状态文字变得难以在日光下阅读。

import SwiftUI
import UIKit
import XCTest
@testable import FruitTreeScanner

final class DesignSystemContrastTests: XCTestCase {

    // MARK: - 对比度计算

    private struct RGB {
        let r: Double
        let g: Double
        let b: Double

        init(_ color: Color) {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            self.r = Double(r)
            self.g = Double(g)
            self.b = Double(b)
        }

        var luminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
    }

    private func contrastRatio(_ lhs: Color, _ rhs: Color) -> Double {
        let a = RGB(lhs).luminance
        let b = RGB(rhs).luminance
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - 浅色工作区

    /// 承载正文级小字的颜色（日期、单位、状态标签）必须在两种表面下达 AA。
    func testBodySizedTextColorsMeetAAOnPaperAndWhite() {
        let paper = Design.Colors.Workspace.background
        let white = Design.Colors.Workspace.surface

        let bodyColors: [(String, Color)] = [
            ("ink", Design.Colors.Workspace.ink),
            ("secondary", Design.Colors.Workspace.secondary),
            ("muted", Design.Colors.Workspace.muted),
            ("accent", Design.Colors.Workspace.accent),
            ("attention", Design.Colors.Workspace.attention),
            ("failure", Design.Colors.Workspace.failure),
            ("reliable", Design.Colors.Workspace.reliable),
            ("information", Design.Colors.Workspace.information)
        ]

        for (name, color) in bodyColors {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(color, paper), 4.5,
                "\(name) on paper background must reach WCAG AA (4.5:1)"
            )
            XCTAssertGreaterThanOrEqual(
                contrastRatio(color, white), 4.5,
                "\(name) on white surface must reach WCAG AA (4.5:1)"
            )
        }
    }

    /// 主要文字在纸底上应达到 AAA（7:1）。
    func testPrimaryInkMeetsAAAOnPaper() {
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Design.Colors.Workspace.ink, Design.Colors.Workspace.background),
            7.0
        )
    }

    /// `faint` 只用于装饰（箭头、图标），不用于正文；
    /// 但仍需保证在纸底上不低于 3:1，否则会完全看不见。
    func testDecorativeFaintStaysVisible() {
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Design.Colors.Workspace.faint, Design.Colors.Workspace.background),
            3.0
        )
    }

    /// 实心按钮底色配白字必须可读。
    func testFilledButtonSurfacesSupportWhiteText() {
        let fills: [(String, Color)] = [
            ("accent", Design.Colors.Workspace.accent),
            ("attention", Design.Colors.Workspace.attention),
            ("failure", Design.Colors.Workspace.failure),
            ("reliable", Design.Colors.Workspace.reliable)
        ]
        for (name, fill) in fills {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(.white, fill), 4.5,
                "white text on \(name) fill must remain readable"
            )
        }
    }

    // MARK: - 深色画布

    /// 深色画布上的实心按钮是"亮底 + 墨字"，不能沿用白字：
    /// 浅锈红 #E58B7B 配白字只有 2.6:1，远低于 AA。
    func testDarkFilledButtonsUseInkOnLightFill() {
        let fills: [(String, Color)] = [
            ("glow", Design.Colors.Dark.glow),
            ("error", Design.Colors.Dark.error)
        ]
        for (name, fill) in fills {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(Design.Colors.Dark.bgDeep, fill), 4.5,
                "ink text on the dark-canvas \(name) fill must reach WCAG AA (4.5:1)"
            )
            XCTAssertLessThan(
                contrastRatio(.white, fill), 4.5,
                "white text must not be used on the dark-canvas \(name) fill"
            )
        }
    }

    /// 采集 HUD 与点云视口上的小字必须在深色表面上达到 AA。
    func testDarkCanvasTextMeetsAA() {
        let surfaces = [
            Design.Colors.Dark.bgDeep,
            Design.Colors.Dark.bgSurface,
            Design.Colors.Dark.controlSurface
        ]
        let texts: [(String, Color)] = [
            ("textPrimary", Design.Colors.Dark.textPrimary),
            ("textSecondary", Design.Colors.Dark.textSecondary),
            ("textMuted", Design.Colors.Dark.textMuted),
            ("glow", Design.Colors.Dark.glow),
            ("success", Design.Colors.Dark.success),
            ("warning", Design.Colors.Dark.warning),
            ("error", Design.Colors.Dark.error),
            ("info", Design.Colors.Dark.info)
        ]
        for (name, text) in texts {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(text, surface), 4.5,
                    "\(name) must reach WCAG AA (4.5:1) on the dark canvas"
                )
            }
        }
    }

    // MARK: - 语义一致性

    /// 旧的别名必须与新语义保持同色，避免同一语义出现两种颜色。
    func testLegacyAliasesMatchSemanticColors() {
        XCTAssertEqual(Design.Colors.harvest, Design.Colors.Workspace.attention)
        XCTAssertEqual(Design.Colors.warning, Design.Colors.Workspace.attention)
        XCTAssertEqual(Design.Colors.forest, Design.Colors.Workspace.reliable)
        XCTAssertEqual(Design.Colors.success, Design.Colors.Workspace.reliable)
        XCTAssertEqual(Design.Colors.error, Design.Colors.Workspace.failure)
        XCTAssertEqual(Design.Colors.apple, Design.Colors.Workspace.failure)
        XCTAssertEqual(Design.Colors.information, Design.Colors.Workspace.information)
    }
}
