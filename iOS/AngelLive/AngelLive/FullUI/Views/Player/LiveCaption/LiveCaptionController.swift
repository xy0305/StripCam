import Foundation
import Observation
import AngelLiveCore
import AngelLiveDependencies

/// FullUI-facing controller: preference + session, with UI-first disable.
@MainActor
@Observable
final class LiveCaptionController {
    let preference = LiveCaptionPreference()
    let session = LiveCaptionSession()

    /// Immediate UI flag; may diverge from `session.phase` briefly while tearing down.
    private(set) var showsCaptions = false
    private(set) var overlayLine: LiveCaptionLine?
    private(set) var overlayStatus = ""

    private var syncTask: Task<Void, Never>?
    private var lastSource: LiveCaptionSource?

    init() {
        showsCaptions = preference.isEnabled
        syncTask = Task { [weak self] in
            await self?.mirrorSession()
        }
    }

    deinit {
        syncTask?.cancel()
    }

    var translationBridge: AnyObject? { session.translationBridge }

    func currentSource(from viewModel: RoomInfoViewModel) -> LiveCaptionSource? {
        guard let url = viewModel.currentPlayURL else { return nil }
        let fallbackUA = resolvedUserAgent(viewModel.playerOption.userAgent)

        let selection = RoomPlaybackResolver.selection(
            in: viewModel.currentRoomPlayArgs,
            cdnIndex: viewModel.currentCdnIndex,
            qualityIndex: viewModel.currentQualityIndex
        )
        if let quality = selection?.quality {
            let request = RoomPlaybackResolver.requestOptions(
                for: quality,
                fallbackUserAgent: fallbackUA
            )
            return LiveCaptionSource(url: url, headers: request.headers, userAgent: request.userAgent)
        }
        return LiveCaptionSource(
            url: url,
            headers: ["User-Agent": fallbackUA],
            userAgent: fallbackUA
        )
    }

    /// Toggle from the player chrome. OFF is UI-first, then async teardown.
    func setEnabled(_ enabled: Bool, viewModel: RoomInfoViewModel) {
        preference.isEnabled = enabled
        showsCaptions = enabled
        if !enabled {
            overlayLine = nil
            overlayStatus = ""
            Task { await session.stop(clearText: true) }
            return
        }
        guard let source = currentSource(from: viewModel) else {
            overlayStatus = "等待播放地址…"
            return
        }
        lastSource = source
        Task { await session.start(source: source) }
    }

    func handlePlayURLChanged(viewModel: RoomInfoViewModel) {
        guard preference.isEnabled, showsCaptions else { return }
        guard let source = currentSource(from: viewModel) else { return }
        if source == lastSource { return }
        lastSource = source
        Task { await session.retarget(source: source) }
    }

    func resumeIfNeeded(viewModel: RoomInfoViewModel) {
        guard preference.isEnabled else { return }
        showsCaptions = true
        guard let source = currentSource(from: viewModel) else { return }
        lastSource = source
        Task { await session.start(source: source) }
    }

    func handlePlaybackBusy(_ busy: Bool) {
        guard showsCaptions else { return }
        session.holdForBandwidth(busy)
    }

    func shutdown() {
        showsCaptions = false
        overlayLine = nil
        overlayStatus = ""
        Task { await session.stop(clearText: true) }
    }

    private func resolvedUserAgent(_ value: Any?) -> String {
        if let value = value as? String, !value.isEmpty { return value }
        return "libmpv"
    }

    private func mirrorSession() async {
        while !Task.isCancelled {
            if showsCaptions {
                overlayLine = session.latest
                if session.phase == .starting || session.phase == .failed {
                    overlayStatus = session.statusMessage
                } else if overlayLine == nil {
                    overlayStatus = session.statusMessage
                } else {
                    overlayStatus = ""
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
