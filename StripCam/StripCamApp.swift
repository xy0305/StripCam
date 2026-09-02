//
//  StripCamApp.swift
//  StripCam
//
//  Created by xy0305 on 2026/09/02.
//

import SwiftUI
import AVFoundation

@main
struct StripCamApp: App {
    @StateObject private var favorites = FavoritesStore()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(favorites)
                .tint(AppConstants.Colors.accent)
        }
    }

    /// 预配置音频会话为播放类别（后台播放 / 静音开关不影响声音）。
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // 非致命：播放器会在真正起播时再次激活
        }
    }
}
