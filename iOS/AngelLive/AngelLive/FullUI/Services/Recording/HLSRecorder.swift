//
//  HLSRecorder.swift
//  AngelLive
//
//  把直播 HLS 存成本地 VOD 播放列表（init + 分片 + index.m3u8）。
//  不再把 fMP4 分片硬拼成一个假 mp4 —— AVPlayer 打不开那种文件。
//

import Foundation
internal import AVFoundation

final class HLSRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case invalidURL
        case emptyPlaylist
        case http(Int)
        case cancelled
        case noSegments

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的直播地址"
            case .emptyPlaylist: return "播放列表为空"
            case .http(let code): return "下载失败（HTTP \(code)）"
            case .cancelled: return "已取消"
            case .noSegments: return "没有录到有效分片"
            }
        }
    }

    struct Result: Sendable {
        let outputURL: URL
        let bytes: Int64
        let duration: TimeInterval
    }

    private let session: URLSession
    private var stopFlag = false
    private let lock = NSLock()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func stop() {
        lock.lock()
        stopFlag = true
        lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopFlag
    }

    /// `outputURL` 是最终的 `index.m3u8`。分片写在同一目录。
    func record(
        playlistURL: URL,
        headers: [String: String],
        outputURL: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> Result {
        stopFlag = false
        let started = Date()
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var bytes: Int64 = 0
        var mediaURL = playlistURL
        var seen = Set<String>()
        var wroteInit = false
        var initName: String?
        var segments: [(name: String, duration: Double)] = []
        var targetDuration: Double = 1
        var consecutiveEmpty = 0
        var index = 0

        while !Task.isCancelled {
            if isStopped { break }

            let text = try await fetchText(mediaURL, headers: headers)
            if isMaster(text) {
                guard let next = pickBestVariant(text, base: mediaURL) else {
                    throw RecorderError.emptyPlaylist
                }
                mediaURL = next
                continue
            }

            let parsed = parseMedia(text, base: mediaURL)
            targetDuration = max(targetDuration, parsed.targetDuration)

            if let initURL = parsed.mapURL, !wroteInit {
                let name = "init.mp4"
                let data = try await fetch(initURL, headers: headers)
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                bytes += Int64(data.count)
                initName = name
                wroteInit = true
                onBytes(bytes)
            }

            var added = 0
            for segment in parsed.segments {
                if isStopped || Task.isCancelled { break }
                if seen.contains(segment.key) { continue }
                seen.insert(segment.key)
                let ext = segment.url.pathExtension.isEmpty ? (wroteInit ? "m4s" : "ts") : segment.url.pathExtension
                let name = String(format: "seg_%05d.%@", index, ext)
                index += 1
                let data = try await fetch(segment.url, headers: headers)
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                bytes += Int64(data.count)
                segments.append((name: name, duration: max(segment.duration, 0.01)))
                added += 1
                onBytes(bytes)
                writePlaylist(
                    to: outputURL,
                    targetDuration: targetDuration,
                    initName: initName,
                    segments: segments,
                    ended: false
                )
            }

            if parsed.endList { break }
            if isStopped { break }
            if added == 0 {
                consecutiveEmpty += 1
                if consecutiveEmpty > 40 { break }
            } else {
                consecutiveEmpty = 0
            }

            let wait = max(0.4, min(parsed.targetDuration / 2, 2.0))
            await sleep(wait)
        }

        guard !segments.isEmpty else {
            throw bytes == 0 ? RecorderError.noSegments : RecorderError.cancelled
        }

        writePlaylist(
            to: outputURL,
            targetDuration: targetDuration,
            initName: initName,
            segments: segments,
            ended: true
        )
        let duration = Date().timeIntervalSince(started)
        return Result(outputURL: outputURL, bytes: bytes, duration: duration)
    }

    // MARK: - Playlist file

    private func writePlaylist(
        to url: URL,
        targetDuration: Double,
        initName: String?,
        segments: [(name: String, duration: Double)],
        ended: Bool
    ) {
        var lines: [String] = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(max(1, Int(ceil(targetDuration))))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:\(ended ? "VOD" : "EVENT")"
        ]
        if let initName {
            lines.append("#EXT-X-MAP:URI=\"\(initName)\"")
        }
        for segment in segments {
            lines.append(String(format: "#EXTINF:%.3f,", segment.duration))
            lines.append(segment.name)
        }
        if ended {
            lines.append("#EXT-X-ENDLIST")
        }
        let body = lines.joined(separator: "\n") + "\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Playlist parse

    private func isMaster(_ text: String) -> Bool {
        text.contains("#EXT-X-STREAM-INF")
    }

    private func pickBestVariant(_ text: String, base: URL) -> URL? {
        var bestURL: URL?
        var bestBW = -1
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var pendingBW = 0
        var pendingOK = false
        for line in lines {
            if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF") {
                pendingOK = false
                continue
            }
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingBW = bandwidth(in: line)
                pendingOK = line.contains("RESOLUTION") || line.contains("BANDWIDTH")
                if line.contains("CODECS=\"mp4a") && !line.contains("avc") && !line.contains("hvc") && !line.contains("hev") {
                    pendingOK = false
                }
            } else if pendingOK, !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if pendingBW >= bestBW, let url = resolve(line, relativeTo: base) {
                    bestBW = pendingBW
                    bestURL = url
                }
                pendingOK = false
                pendingBW = 0
            }
        }
        return bestURL
    }

    private struct MediaPlaylist {
        var targetDuration: Double = 1
        var mapURL: URL?
        var segments: [(key: String, url: URL, duration: Double)] = []
        var endList = false
    }

    private func parseMedia(_ text: String, base: URL) -> MediaPlaylist {
        var parsed = MediaPlaylist()
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        var pendingDuration: Double = 1
        var expectSegment = false
        var seq = 0
        for line in lines {
            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                parsed.targetDuration = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count)) ?? 1
            } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                seq = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)) ?? 0
            } else if line.hasPrefix("#EXT-X-MAP:") {
                if let uri = attribute(line, name: "URI"), let url = resolve(uri, relativeTo: base) {
                    parsed.mapURL = url
                }
            } else if line.hasPrefix("#EXTINF:") {
                let raw = line.dropFirst("#EXTINF:".count)
                let number = raw.split(separator: ",", maxSplits: 1).first.map(String.init) ?? "1"
                pendingDuration = Double(number) ?? 1
                expectSegment = true
            } else if line == "#EXT-X-ENDLIST" {
                parsed.endList = true
            } else if expectSegment, !line.hasPrefix("#"), !line.isEmpty {
                if let url = resolve(line, relativeTo: base) {
                    parsed.segments.append((key: "\(seq)-\(line)", url: url, duration: pendingDuration))
                    seq += 1
                }
                expectSegment = false
            }
        }
        return parsed
    }

    private func bandwidth(in line: String) -> Int {
        Int(attribute(line, name: "BANDWIDTH") ?? "0") ?? 0
    }

    private func attribute(_ line: String, name: String) -> String? {
        let pattern = #"\#(name)="?([^,"]+)"?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let valueRange = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[valueRange])
    }

    private func resolve(_ ref: String, relativeTo base: URL) -> URL? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    // MARK: - Network

    private func fetchText(_ url: URL, headers: [String: String]) async throws -> String {
        let data = try await fetch(url, headers: headers)
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func fetch(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("*/*", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw RecorderError.http(http.statusCode)
        }
        return data
    }

    private func sleep(_ seconds: Double) async {
        let ns = UInt64(seconds * 1_000_000_000)
        let slice: UInt64 = 200_000_000
        var remaining = ns
        while remaining > 0 {
            if isStopped || Task.isCancelled { return }
            let step = min(slice, remaining)
            try? await Task.sleep(nanoseconds: step)
            remaining -= step
        }
    }
}
