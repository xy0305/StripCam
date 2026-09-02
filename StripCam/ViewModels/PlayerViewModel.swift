//
//  PlayerViewModel.swift
//  StripCam
//
//  播放器状态：解析直播流、维护当前流/清晰度切换。
//  渲染与播放由 KSPlayer 负责。
//

import Foundation
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {
    let model: PlayableModel

    @Published private(set) var streams: [StreamInfo] = []
    @Published private(set) var currentStream: StreamInfo?
    @Published var errorMessage: String?

    init(model: PlayableModel) {
        self.model = model
    }

    func load() async {
        do {
            let resolved = await StripchatAPI.shared.resolveStreams(modelId: model.id, presets: model.presets)
            streams = resolved
            guard let first = resolved.first else {
                throw StripchatError.noStream
            }
            currentStream = first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ stream: StreamInfo) {
        currentStream = stream
        errorMessage = nil
    }

    func retry() {
        errorMessage = nil
        if currentStream == nil {
            Task { await load() }
        }
    }
}
