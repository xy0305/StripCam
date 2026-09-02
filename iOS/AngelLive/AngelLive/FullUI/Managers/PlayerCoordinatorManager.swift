//
//  PlayerCoordinatorManager.swift
//  AngelLive
//
//  Created by Claude on 10/28/25.
//

import Foundation
import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

/// 全局播放器协调器管理器
/// 确保整个 APP 只有一个播放器实例，避免重复创建
@MainActor
@Observable
final class PlayerCoordinatorManager {
    /// 全局共享的播放器协调器。延后到真正进播放页再创建，
    /// 避免冷启动就触发 KSPlayer / FFmpeg 动态库加载。
    private var storedCoordinator: KSVideoPlayer.Coordinator?

    var coordinator: KSVideoPlayer.Coordinator {
        if let storedCoordinator {
            return storedCoordinator
        }
        let created = KSVideoPlayer.Coordinator()
        storedCoordinator = created
        Logger.debug("🟢 PlayerCoordinatorManager 首次创建播放器协调器", category: .player)
        return created
    }

    /// 是否已检测到视频尺寸（用于控制播放器可见性）
    /// 保存在全局管理器中，避免横竖屏切换时重置
    var hasDetectedSize: Bool = false

    init() {
        Logger.debug("🟢 PlayerCoordinatorManager init", category: .player)
    }

    deinit {
        Logger.debug("🔴 PlayerCoordinatorManager deinit", category: .player)
    }

    /// 重置播放器状态
    /// 在退出播放页面时调用，清理播放器状态
    func reset() {
        Logger.debug("🔄 PlayerCoordinatorManager reset - 重置播放器状态", category: .player)

        if let storedCoordinator {
            if let playerLayer = storedCoordinator.playerLayer {
                playerLayer.pause()
                playerLayer.stop()
            }
            storedCoordinator.isScaleAspectFill = false
            storedCoordinator.isMaskShow = false
        }
        hasDetectedSize = false
    }

    /// 准备播放器
    /// 在进入播放页面时调用，确保播放器状态干净
    func prepare() {
        Logger.debug("🟢 PlayerCoordinatorManager prepare - 准备播放器", category: .player)
        Logger.debug("   当前 playerLayer 状态: \(coordinator.playerLayer != nil ? "存在" : "不存在")", category: .player)
        Logger.debug("   当前 hasDetectedSize: \(hasDetectedSize)", category: .player)

        // 不调用 shutdown，只是确保状态正确
        // shutdown 会清理 playerLayer，导致横竖屏切换时无法重新渲染
    }
}
