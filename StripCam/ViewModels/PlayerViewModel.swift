//
//  PlayerViewModel.swift
//  StripCam
//
//  播放器状态机：解析直播流、管理 AVPlayer、切换清晰度。
//

import AVFoundation
import Combine
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    let model: PlayableModel
    let player = AVPlayer()

    @Published private(set) var streams: [StreamInfo] = []
    @Published private(set) var currentStream: StreamInfo?
    @Published private(set) var isBuffering = true
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private var itemStatusObservation: NSKeyValueObservation?

    init(model: PlayableModel) {
        self.model = model
        // 观察播放状态（缓冲 / 播放中）
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isBuffering = (status != .playing)
            }
            .store(in: &cancellables)
    }

    deinit {
        itemStatusObservation?.invalidate()
    }

    func load() async {
        do {
            let resolved = await StripchatAPI.shared.resolveStreams(modelId: model.id, presets: model.presets)
            streams = resolved
            guard let first = resolved.first else {
                throw StripchatError.noStream
            }
            play(first)
        } catch {
            errorMessage = error.localizedDescription
            isBuffering = false
        }
    }

    func play(_ stream: StreamInfo) {
        currentStream = stream
        errorMessage = nil
        isBuffering = true

        itemStatusObservation?.invalidate()
        let item = AVPlayerItem(url: stream.url)

        // 「自动」档：不限制码率，让系统优先选择最高画质（视频 + 音频多路复用）。
        if stream.isAuto {
            item.preferredPeakBitRate = 0
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                if item.status == .failed {
                    self.errorMessage = item.error?.localizedDescription ?? "播放失败"
                    self.isBuffering = false
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
    }

    func retry() {
        if let s = currentStream {
            play(s)
        } else {
            Task { await load() }
        }
    }
}
