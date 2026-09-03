//
//  HLSRecorder.swift
//  AngelLive
//
//  独立于播放器的 HLS 分片下载。退出直播间后仍可继续，
//  不走 AVAssetReader（LL-HLS / 音视频分离流会立刻失败）。
//

import Foundation
internal import AVFoundation

final class HLSRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case invalidURL
        case emptyPlaylist
        case http(Int)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的直播地址"
            case .emptyPlaylist: return "播放列表为空"
            case .http(let code): return "下载失败（HTTP \(code)）"
            case .cancelled: return "已取消"
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

    func record(
        playlistURL: URL,
        headers: [String: String],
        outputURL: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> Result {
        stopFlag = false
        let started = Date()
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        var bytes: Int64 = 0
        var mediaURL = playlistURL
        var seen = Set<String>()
        var wroteInit = false
        var consecutiveEmpty = 0

        while !isStopped {
            let text = try await fetchText(mediaURL, headers: headers)
            if isMaster(text) {
                guard let next = pickBestVariant(text, base: mediaURL) else {
                    throw RecorderError.emptyPlaylist
                }
                mediaURL = next
                continue
            }

            let parsed = parseMedia(text, base: mediaURL)
            if let initURL = parsed.mapURL, !wroteInit {
                bytes += try await append(initURL, headers: headers, to: handle)
                wroteInit = true
                onBytes(bytes)
            }

            var added = 0
            for segment in parsed.segments {
                if isStopped { break }
                if seen.contains(segment.key) { continue }
                seen.insert(segment.key)
                bytes += try await append(segment.url, headers: headers, to: handle)
                added += 1
                onBytes(bytes)
            }

            if parsed.endList { break }
            if added == 0 {
                consecutiveEmpty += 1
                if consecutiveEmpty > 40 { break }
            } else {
                consecutiveEmpty = 0
            }

            let wait = max(0.4, min(parsed.targetDuration / 2, 2.0))
            try await sleep(wait)
        }

        try handle.synchronize()
        let duration = Date().timeIntervalSince(started)
        let finalized = try await finalize(outputURL)
        return Result(outputURL: finalized, bytes: bytes, duration: duration)
    }

    // MARK: - Playlist

    private func isMaster(_ text: String) -> Bool {
        text.contains("#EXT-X-STREAM-INF")
    }

    private func pickBestVariant(_ text: String, base: URL) -> URL? {
        var bestURL: URL?
        var bestBW = -1
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        var pendingBW = 0
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingBW = bandwidth(in: line)
            } else if !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if pendingBW >= bestBW, let url = resolve(line, relativeTo: base) {
                    bestBW = pendingBW
                    bestURL = url
                }
                pendingBW = 0
            }
        }
        return bestURL
    }

    private struct MediaPlaylist {
        var targetDuration: Double = 1
        var mapURL: URL?
        var segments: [(key: String, url: URL)] = []
        var endList = false
    }

    private func parseMedia(_ text: String, base: URL) -> MediaPlaylist {
        var parsed = MediaPlaylist()
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
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
                expectSegment = true
            } else if line == "#EXT-X-ENDLIST" {
                parsed.endList = true
            } else if expectSegment, !line.hasPrefix("#"), !line.isEmpty {
                if let url = resolve(line, relativeTo: base) {
                    parsed.segments.append((key: "\(seq)-\(line)", url: url))
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

    private func append(_ url: URL, headers: [String: String], to handle: FileHandle) async throws -> Int64 {
        let data = try await fetch(url, headers: headers)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return Int64(data.count)
    }

    private func fetch(_ url: URL, headers: [String: String]) async throws -> Data {
        if isStopped { throw RecorderError.cancelled }
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

    private func sleep(_ seconds: Double) async throws {
        let ns = UInt64(seconds * 1_000_000_000)
        let slice: UInt64 = 200_000_000
        var remaining = ns
        while remaining > 0 {
            if isStopped { throw RecorderError.cancelled }
            let step = min(slice, remaining)
            try await Task.sleep(nanoseconds: step)
            remaining -= step
        }
    }

    // MARK: - Finalize

    private func finalize(_ partURL: URL) async throws -> URL {
        let ext = guessExtension(partURL)
        let finalURL = partURL.deletingPathExtension().appendingPathExtension(ext)
        if finalURL != partURL {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: partURL, to: finalURL)
        }
        if ext == "ts" || ext == "m4s" {
            if let mp4 = await exportMP4(from: finalURL) {
                return mp4
            }
        }
        return finalURL
    }

    private func guessExtension(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let header = try? handle.read(upToCount: 12) else {
            return "ts"
        }
        try? handle.close()
        if header.starts(with: [0x00, 0x00, 0x00]) || header.dropFirst(4).starts(with: Array("ftyp".utf8)) {
            return "mp4"
        }
        return "ts"
    }

    private func exportMP4(from url: URL) async -> URL? {
        let dest = url.deletingPathExtension().appendingPathExtension("mp4")
        if dest == url { return url }
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return nil
        }
        session.outputURL = dest
        session.outputFileType = .mp4
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        guard session.status == .completed else { return nil }
        try? FileManager.default.removeItem(at: url)
        return dest
    }
}
