//
//  LiveRecordingManager.swift
//  AngelLive
//
//  多路直播录制：每路独立 HLS 下载，退出播放页不停止。
//  用 playback 音频会话 + 后台任务撑住 App 进后台后的下载。
//

import Foundation
import SwiftUI
import AVFoundation
import UIKit
import AngelLiveCore

struct LiveRecordingItem: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case recording
        case stopping
        case finished
        case failed(String)
    }

    let id: String
    let roomId: String
    let liveType: String
    let userName: String
    let roomTitle: String
    let coverURL: String
    var fileURL: URL?
    var bytes: Int64
    var startedAt: Date
    var endedAt: Date?
    var status: Status

    var isActive: Bool {
        switch status {
        case .recording, .stopping: return true
        default: return false
        }
    }

    var durationText: String {
        let end = endedAt ?? Date()
        let seconds = max(0, Int(end.timeIntervalSince(startedAt)))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor
final class LiveRecordingManager: ObservableObject {
    static let shared = LiveRecordingManager()

    @Published private(set) var items: [LiveRecordingItem] = []
    @Published var banner: String?

    private var tasks: [String: Task<Void, Never>] = [:]
    private var recorders: [String: HLSRecorder] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var keepAlivePlayer: AVAudioPlayer?

    private init() {
        reloadFinishedFiles()
    }

    var activeCount: Int { items.filter(\.isActive).count }

    func isRecording(room: LiveModel) -> Bool {
        items.contains { $0.id == Self.jobID(for: room) && $0.isActive }
    }

    func item(for room: LiveModel) -> LiveRecordingItem? {
        items.first { $0.id == Self.jobID(for: room) }
    }

    func toggle(room: LiveModel, playURL: URL?, playArgs: [LiveQualityModel]?, quality: LiveQualityDetail?) {
        if isRecording(room: room) {
            stop(room: room)
        } else {
            start(room: room, playURL: playURL, playArgs: playArgs, quality: quality)
        }
    }

    func start(room: LiveModel, playURL: URL?, playArgs: [LiveQualityModel]?, quality: LiveQualityDetail?) {
        let id = Self.jobID(for: room)
        if isRecording(room: room) { return }

        let streamURL = playURL
            ?? quality.flatMap { RoomPlaybackResolver.playableURL(for: $0) }
            ?? RoomPlaybackResolver.findHLSQuality(in: playArgs).flatMap { RoomPlaybackResolver.playableURL(for: $0) }
            ?? RoomPlaybackResolver.firstPlayableURL(from: playArgs ?? [])

        guard let streamURL else {
            banner = "没有可录制的直播地址"
            return
        }

        let options = quality.map {
            RoomPlaybackResolver.requestOptions(for: $0, fallbackUserAgent: Self.defaultUA)
        }
        var headers = options?.headers ?? [:]
        if headers["User-Agent"] == nil && headers["user-agent"] == nil {
            headers["User-Agent"] = Self.defaultUA
        }
        if headers["Referer"] == nil && headers["referer"] == nil {
            headers["Referer"] = "https://zh.stripchat.com/"
        }
        if headers["Origin"] == nil && headers["origin"] == nil {
            headers["Origin"] = "https://zh.stripchat.com"
        }

        let partURL = Self.recordingsDirectory()
            .appendingPathComponent("\(Self.filePrefix(room))-\(Self.stamp()).part")

        let item = LiveRecordingItem(
            id: id,
            roomId: room.roomId,
            liveType: room.liveType.rawValue,
            userName: room.userName,
            roomTitle: room.roomTitle,
            coverURL: room.roomCover,
            fileURL: partURL,
            bytes: 0,
            startedAt: Date(),
            endedAt: nil,
            status: .recording
        )
        items.removeAll { $0.id == id && !$0.isActive }
        items.insert(item, at: 0)
        banner = "开始录制 \(room.userName)"
        activateBackground()

        let recorder = HLSRecorder()
        recorders[id] = recorder
        let headersCopy = headers
        tasks[id] = Task.detached(priority: .utility) { [weak self] in
            do {
                let result = try await recorder.record(
                    playlistURL: streamURL,
                    headers: headersCopy,
                    outputURL: partURL,
                    onBytes: { bytes in
                        Task { @MainActor in
                            self?.update(id: id) { item in
                                item.bytes = bytes
                            }
                        }
                    }
                )
                await MainActor.run {
                    self?.finish(id: id, url: result.outputURL, bytes: result.bytes, error: nil)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.finish(id: id, url: nil, bytes: nil, error: "已取消")
                }
            } catch HLSRecorder.RecorderError.cancelled {
                await MainActor.run {
                    self?.finishStopped(id: id)
                }
            } catch {
                await MainActor.run {
                    self?.finish(id: id, url: nil, bytes: nil, error: error.localizedDescription)
                }
            }
        }
    }

    func stop(room: LiveModel) {
        stop(id: Self.jobID(for: room))
    }

    func stop(id: String) {
        update(id: id) { item in
            if item.status == .recording {
                item.status = .stopping
            }
        }
        recorders[id]?.stop()
        tasks[id]?.cancel()
        banner = "正在结束录制…"
    }

    func stopAll() {
        for item in items where item.isActive {
            stop(id: item.id)
        }
    }

    func delete(_ item: LiveRecordingItem) {
        if item.isActive {
            stop(id: item.id)
        }
        if let url = item.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id && $0.startedAt == item.startedAt }
    }

    func shareURL(for item: LiveRecordingItem) -> URL? {
        item.fileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    // MARK: - Finish

    private func finishStopped(id: String) {
        var fileURL: URL?
        var bytes: Int64 = 0
        if let current = items.first(where: { $0.id == id }) {
            fileURL = current.fileURL.flatMap { existing in
                let dir = existing.deletingLastPathComponent()
                let stem = existing.deletingPathExtension().lastPathComponent
                let candidates = ["mp4", "ts", "m4s", "part"].map {
                    dir.appendingPathComponent("\(stem).\($0)")
                }
                return candidates.first { FileManager.default.fileExists(atPath: $0.path) } ?? existing
            }
            bytes = current.bytes
            if bytes == 0, let url = fileURL,
               let values = try? url.resourceValues(forKeys: [.fileSizeKey]) {
                bytes = Int64(values.fileSize ?? 0)
            }
        }
        finish(id: id, url: fileURL, bytes: bytes, error: bytes == 0 ? "没有写入数据" : nil)
    }

    private func finish(id: String, url: URL?, bytes: Int64?, error: String?) {
        update(id: id) { item in
            item.endedAt = Date()
            if let url { item.fileURL = url }
            if let bytes { item.bytes = bytes }
            if let error, !error.isEmpty, error != "已取消" {
                item.status = .failed(error)
            } else if (bytes ?? item.bytes) == 0 {
                item.status = .failed("没有写入数据")
            } else {
                item.status = .finished
            }
        }
        tasks[id] = nil
        recorders[id] = nil
        if let error, !error.isEmpty, error != "已取消" {
            banner = "录制失败：\(error)"
        } else if let name = items.first(where: { $0.id == id })?.userName {
            banner = "已保存 \(name) 的录像"
        }
        if activeCount == 0 {
            deactivateBackground()
        }
    }

    private func update(id: String, mutate: (inout LiveRecordingItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.isActive })
                ?? items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    // MARK: - Persistence of finished files

    func reloadFinishedFiles() {
        let dir = Self.recordingsDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let activeIDs = Set(items.filter(\.isActive).map(\.id))
        let existingFinished = items.filter { !$0.isActive }
        var rebuilt = items.filter(\.isActive)

        let recordings = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["mp4", "ts", "m4s", "mov"].contains(ext)
        }
        .sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }

        for url in recordings {
            if existingFinished.contains(where: { $0.fileURL == url }) { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let name = Self.displayName(from: url)
            let item = LiveRecordingItem(
                id: "file-\(url.lastPathComponent)",
                roomId: "",
                liveType: "",
                userName: name,
                roomTitle: url.lastPathComponent,
                coverURL: "",
                fileURL: url,
                bytes: Int64(values?.fileSize ?? 0),
                startedAt: values?.creationDate ?? Date(),
                endedAt: values?.creationDate,
                status: .finished
            )
            if !activeIDs.contains(item.id) {
                rebuilt.append(item)
            }
        }
        items = rebuilt
    }

    // MARK: - Background keep-alive

    private func activateBackground() {
        configureAudioSession()
        startKeepAlive()
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "StripCamRecording") { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }

    private func deactivateBackground() {
        stopKeepAlive()
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            Logger.warning("录制音频会话失败: \(error)", category: .app)
        }
    }

    private func startKeepAlive() {
        guard keepAlivePlayer == nil else { return }
        let url = Self.silentAudioURL()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0.0
        player.prepareToPlay()
        player.play()
        keepAlivePlayer = player
    }

    private func stopKeepAlive() {
        keepAlivePlayer?.stop()
        keepAlivePlayer = nil
    }

    private static func silentAudioURL() -> URL {
        let dest = recordingsDirectory().appendingPathComponent(".keepalive.wav")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let data = Self.minimalWav()
        try? data.write(to: dest, options: .atomic)
        return dest
    }

    /// 0.25s 静音 WAV，用来声明正在播放，避免 iOS 立刻挂起后台下载。
    private static func minimalWav() -> Data {
        let sampleRate: UInt32 = 8000
        let samples: UInt32 = 2000
        var data = Data()
        func append<T>(_ value: T) {
            var value = value
            data.append(Data(bytes: &value, count: MemoryLayout<T>.size))
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples * 2))
        data.append(Data(count: Int(samples * 2)))
        return data
    }

    // MARK: - Paths

    static func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func jobID(for room: LiveModel) -> String {
        "\(room.liveType.rawValue)-\(room.roomId)"
    }

    private static func filePrefix(_ room: LiveModel) -> String {
        let raw = room.userName.isEmpty ? room.roomId : room.userName
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let joined = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return joined.isEmpty ? room.roomId : joined
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static func displayName(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        if let range = stem.range(of: #"-\d{8}-\d{6}$"#, options: .regularExpression) {
            return String(stem[..<range.lowerBound])
        }
        return stem
    }

    private static let defaultUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
