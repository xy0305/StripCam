//
//  AppConstants.swift
//  StripCam
//
//  统一管理颜色、间距、圆角等设计常量（参照 AngelLive 的原生克制风格）。
//

import SwiftUI
import UIKit

/// 格式化人气数字：10000 → "1.0万"，1000 → "1.0k"
func formatPopularity(_ count: Int) -> String {
    if count >= 10000 {
        return String(format: "%.1f万", Double(count) / 10000.0)
    } else if count >= 1000 {
        return String(format: "%.1fk", Double(count) / 1000.0)
    } else {
        return "\(count)"
    }
}

enum AppKeys {
    /// 登录后 Cookie（用于「我的最爱」）
    static let cookie = "stripcam.cookie"
    /// 本地收藏
    static let favorites = "stripcam.favorites"
}

enum AppConstants {

    // MARK: - 颜色系统

    enum Colors {
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color(.tertiaryLabel)

        static let primaryBackground = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let tertiaryBackground = Color(.tertiarySystemBackground)
        static let groupedBackground = Color(.systemGroupedBackground)

        static let accent = Color.accentColor
        static let link = Color.blue
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

        static let primaryBorder = Color.primary.opacity(0.2)
        static let separator = Color(.separator)
        static let lightSeparator = Color(.separator).opacity(0.5)

        /// 直播状态
        static let liveStatus = Color.green
        static let offlineStatus = Color.gray

        /// 占位渐变
        static func placeholderGradient() -> LinearGradient {
            LinearGradient(
                colors: [Color.gray.opacity(0.22), Color.gray.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - 间距系统

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - 圆角

    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let round: CGFloat = 999
    }

    // MARK: - 播放器 UI

    enum PlayerUI {
        enum Opacity {
            static let overlayLight: CGFloat = 0.3
            static let overlayMedium: CGFloat = 0.5
            static let overlayStrong: CGFloat = 0.6
            static let backplate: CGFloat = 0.35
        }
    }

    enum AspectRatio {
        /// 封面图比例（16:9）
        static let pic: CGFloat = 16.0 / 9.0
    }

    // MARK: - 设备检测

    enum Device {
        static var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
        static var isIPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    }
}

extension Color {
    static let appPrimaryText = AppConstants.Colors.primaryText
    static let appSecondaryText = AppConstants.Colors.secondaryText
    static let appTertiaryText = AppConstants.Colors.tertiaryText
}
