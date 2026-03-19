import SwiftUI
import AppKit

// MARK: - SBrain Design System

enum SB {

    // MARK: - Color Palette

    enum Colors {
        // Background
        static let bgPrimary = Color(hex: "FAF8F5")       // 따뜻한 크림
        static let bgSecondary = Color(hex: "F2EDE8")     // 아이보리
        static let bgTertiary = Color(hex: "EBE5DE")      // 호버/선택
        static let bgElevated = Color.white                // 모달/팝오버

        // Navy (BI Primary)
        static let navy900 = Color(hex: "1B2A4A")         // 주요 텍스트
        static let navy700 = Color(hex: "2D4470")         // 보조 텍스트
        static let navy500 = Color(hex: "5A7099")         // 비활성
        static let navy300 = Color(hex: "8FA3C4")         // 플레이스홀더
        static let navy100 = Color(hex: "D4DCE8")         // 보더/구분선

        // Gold (BI Accent)
        static let gold600 = Color(hex: "C4973B")         // 포인트, 활성
        static let gold400 = Color(hex: "D4AD5A")         // 호버
        static let gold200 = Color(hex: "E8D49B")         // 밝은 포인트
        static let gold100 = Color(hex: "F5EDD8")         // 포인트 배경

        // Semantic
        static let accentBlue = Color(hex: "3B7CC4")      // 링크, 정보
        static let accentGreen = Color(hex: "4CAF7D")     // 성공, 연결
        static let accentRed = Color(hex: "D45A5A")       // 에러, 삭제
        static let accentOrange = Color(hex: "D4883B")    // 경고

        // Icon Bar
        static let iconBarBg = Color(hex: "1B2A4A")       // 네이비 배경
        static let iconBarIcon = Color(hex: "8FA3C4")     // 기본 아이콘
        static let iconBarActive = Color(hex: "C4973B")   // 활성 아이콘

        // Terminal (Light)
        static let terminalBg = Color(hex: "FAF8F5")
        static let terminalFg = Color(hex: "1B2A4A")
        static let terminalCursor = Color(hex: "C4973B")
        static let terminalSelection = Color(hex: "D4AD5A").opacity(0.2)
    }

    // MARK: - Typography

    enum Font {
        static func titleLg() -> SwiftUI.Font { .system(size: 20, weight: .bold) }
        static func titleMd() -> SwiftUI.Font { .system(size: 16, weight: .semibold) }
        static func titleSm() -> SwiftUI.Font { .system(size: 14, weight: .semibold) }
        static func bodyMd() -> SwiftUI.Font { .system(size: 13, weight: .regular) }
        static func bodySm() -> SwiftUI.Font { .system(size: 12, weight: .regular) }
        static func caption() -> SwiftUI.Font { .system(size: 11, weight: .medium) }
        static func mono() -> SwiftUI.Font { .system(size: 12, weight: .regular, design: .monospaced) }
        static func monoSm() -> SwiftUI.Font { .system(size: 11, weight: .regular, design: .monospaced) }
    }

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let full: CGFloat = 9999
    }

    // MARK: - Shadows

    enum Shadow {
        static func sm() -> some View {
            Color(hex: "1B2A4A").opacity(0.08)
        }

        static func md() -> some View {
            Color(hex: "1B2A4A").opacity(0.1)
        }
    }

    // MARK: - Layout Constants

    enum Layout {
        static let iconBarWidth: CGFloat = 48
        static let explorerPanelWidth: CGFloat = 240
        static let explorerPanelMinWidth: CGFloat = 180
        static let explorerPanelMaxWidth: CGFloat = 360
        static let topBarHeight: CGFloat = 44
        static let terminalMinHeight: CGFloat = 120
        static let terminalMaxHeight: CGFloat = 500
        static let terminalDefaultHeight: CGFloat = 250
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

}

// MARK: - NSColor Helpers (for AppKit views like SwiftTerm)

enum SBNSColor {
    static let bgPrimary = NSColor(red: CGFloat(250)/255, green: CGFloat(248)/255, blue: CGFloat(245)/255, alpha: 1)
    static let bgSecondary = NSColor(red: CGFloat(242)/255, green: CGFloat(237)/255, blue: CGFloat(232)/255, alpha: 1)
    static let navy900 = NSColor(red: CGFloat(27)/255, green: CGFloat(42)/255, blue: CGFloat(74)/255, alpha: 1)
    static let navy700 = NSColor(red: CGFloat(45)/255, green: CGFloat(68)/255, blue: CGFloat(112)/255, alpha: 1)
    static let gold600 = NSColor(red: CGFloat(196)/255, green: CGFloat(151)/255, blue: CGFloat(59)/255, alpha: 1)
    static let gold400 = NSColor(red: CGFloat(212)/255, green: CGFloat(173)/255, blue: CGFloat(90)/255, alpha: 1)
}
