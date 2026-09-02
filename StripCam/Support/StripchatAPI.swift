//
//  StripchatAPI.swift
//  StripCam
//
//  Stripchat 接口客户端 + HLS 直播流解析。
//  接口与解析逻辑严格对照插件脚本（Stripchat 直播模块 v6.4），
//  用于获取最高画质与声音的直播流。
//

import Foundation

final class StripchatAPI {
    static let shared = StripchatAPI()

    static let apiHost = "https://zh.stripchat.com"
    static let imgBase = "https://static-cdn.strpst.com"
    static let pageSize = 24

    private let session: URLSession

    /// 当前登录 Cookie（来自设置，供「我的最爱」使用）
    var cookie: String {
        UserDefaults.standard.string(forKey: AppKeys.cookie) ?? ""
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/json",
            "Referer": "https://zh.stripchat.com/",
            "Origin": "https://zh.stripchat.com",
        ]
        session = URLSession(configuration: config)
    }

    // MARK: - 通用请求

    private func headers() -> [String: String] {
        var h: [String: String] = [:]
        let c = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { h["Cookie"] = c }
        return h
    }

    private func getJSON(_ urlString: String) async throws -> Any {
        guard let url = URL(string: urlString) else {
            throw StripchatError.invalidURL
        }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = headers()
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StripchatError.http(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func getText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw StripchatError.invalidURL
        }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = headers()
        let (data, _) = try await session.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 主播列表

    func fetchModels(category: StripchatCategory, page: Int) async throws -> [StripModel] {
        if category.primaryTag == "favorites" {
            return try await fetchFavorites(page: page)
        }
        let offset = (page - 1) * Self.pageSize
        let sort = category.sortBy.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category.sortBy
        let primary = category.primaryTag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category.primaryTag
        var url = "\(Self.apiHost)/api/front/v2/models?limit=\(Self.pageSize)&offset=\(offset)&sortBy=\(sort)&primaryTag=\(primary)"
        if !category.tag.isEmpty {
            let tag = category.tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category.tag
            url += "&tag=\(tag)"
        }
        let json = try await getJSON(url)
        return StripchatAPI.parseModels(json)
    }

    func search(keyword: String) async throws -> [StripModel] {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return [] }
        // 官方列表接口不支持关键词搜索，这里拉取推荐页后本地过滤用户名。
        let models = try await fetchModels(
            category: StripchatCategory(id: "search", title: "", primaryTag: "girls", sortBy: "recommended"),
            page: 1
        )
        let lower = kw.lowercased()
        return models.filter { $0.username.lowercased().contains(lower) }
    }

    // MARK: - 我的最爱（多接口兼容）

    private func fetchFavorites(page: Int) async throws -> [StripModel] {
        let c = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else {
            throw StripchatError.needCookie
        }
        let offset = (page - 1) * Self.pageSize
        let userId = extractUserId(cookie: c)

        var urls = [
            "\(Self.apiHost)/api/front/models/favorites?sortBy=lastAdded&limit=\(Self.pageSize)&offset=\(offset)",
            "\(Self.apiHost)/api/front/models/favorites?sortBy=username&limit=\(Self.pageSize)&offset=\(offset)",
            "\(Self.apiHost)/api/front/models/favorites/online?sortBy=lastAdded&limit=\(Self.pageSize)&offset=\(offset)",
        ]
        if let uid = userId {
            urls.append("\(Self.apiHost)/api/front/users/\(uid)/favorites?limit=\(Self.pageSize)&offset=\(offset)")
            urls.append("\(Self.apiHost)/api/front/users/\(uid)/favorites?sortBy=lastAdded&limit=\(Self.pageSize)&offset=\(offset)")
        }

        for u in urls {
            if let json = try? await getJSON(u) {
                let models = StripchatAPI.parseModels(json)
                if !models.isEmpty { return models }
            }
        }
        return []
    }

    private func extractUserId(cookie: String) -> String? {
        // 从 AMP_ 里解 userId
        if let range = cookie.range(of: "AMP_[^=]+=([^;]+)", options: .regularExpression) {
            var decoded = String(cookie[range]).components(separatedBy: "=").dropFirst().joined(separator: "=")
            if let d1 = decoded.removingPercentEncoding { decoded = d1 }
            if let d2 = decoded.removingPercentEncoding { decoded = d2 }
            if let r = decoded.range(of: "\"userId\"\\s*:\\s*\"?(\\d+)\"?", options: .regularExpression) {
                let m = String(decoded[r])
                if let n = m.range(of: "(\\d+)", options: .regularExpression) {
                    return String(m[n])
                }
            }
        }
        if let r = cookie.range(of: "userId[\"\\s:=]+(\\d+)", options: .regularExpression) {
            let m = String(cookie[r])
            if let n = m.range(of: "(\\d+)", options: .regularExpression) {
                return String(m[n])
            }
        }
        return nil
    }

    private static func parseModels(_ json: Any) -> [StripModel] {
        var rawModels: [[String: Any]] = []
        if let dict = json as? [String: Any] {
            if let blocks = dict["blocks"] as? [[String: Any]] {
                for b in blocks {
                    if let list = b["models"] as? [[String: Any]] { rawModels += list }
                }
            } else if let list = dict["models"] as? [[String: Any]] {
                rawModels = list
            }
        }
        return rawModels.map(StripModel.init(json:))
    }

    // MARK: - 直播流解析（最高画质 + 声音）

    /// 解析某主播可用的 HLS 流，按码率从高到低排序。
    /// 返回结果中包含「自动」主播放列表（视频+音频多路复用，AVPlayer 自动选最高画质）。
    func resolveStreams(modelId: String, presets: [String]?) async -> [StreamInfo] {
        var qualityOrder = ["1080p", "960p", "720p", "480p", "240p", "160p"]
        if let presets, !presets.isEmpty {
            qualityOrder = presets
                .filter { !$0.contains("blurred") }
                .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
        }

        let cdnBases = [
            "https://edge-hls.saawsedge.com/hls/\(modelId)/master/",
            "https://edge-hls.growcdnssedge.com/hls/\(modelId)/master/",
            "https://edge-hls.doppiocdn.com/hls/\(modelId)/master/",
        ]
        let cdnLabels = ["线路 1", "线路 2", "线路 3"]

        var streams: [StreamInfo] = []
        var seen = Set<String>()

        // 1) 直连各清晰度
        for (i, base) in cdnBases.enumerated() {
            for q in qualityOrder {
                let urlString = base + "\(modelId)_\(q).m3u8?playlistType=lowLatency"
                guard !seen.contains(urlString), let url = URL(string: urlString) else { continue }
                seen.insert(urlString)
                streams.append(StreamInfo(name: "\(q)", url: url, bandwidth: (Int(q) ?? 480) * 2000, cdn: cdnLabels[i]))
            }
        }

        // 2) 主播放列表（自动 + 解析变体）
        for (i, base) in cdnBases.enumerated() {
            let masterUrlString = base + "\(modelId)_auto.m3u8"
            if let masterURL = URL(string: masterUrlString) {
                streams.append(StreamInfo(name: "自动", url: masterURL, bandwidth: 100_000_000, cdn: cdnLabels[i], isAuto: true))
            }

            guard let text = try? await getText(masterUrlString),
                  text.contains("#EXTM3U") else { continue }

            let lines = text.components(separatedBy: .newlines)

            // 提取 pkey（MOUFLON PSCH）
            var pkey = ""
            for line in lines where line.hasPrefix("#EXT-X-MOUFLON:PSCH:v2:") {
                let parts = line.components(separatedBy: ":")
                if let last = parts.last {
                    let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { pkey = trimmed; break }
                }
            }

            for idx in 0..<lines.count {
                let line = lines[idx]
                guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }

                let name = regexCapture(line, pattern: #"NAME="([^"]+)""#) ?? ""
                let res = regexCapture(line, pattern: #"RESOLUTION=(\d+x\d+)"#) ?? ""
                let bw = Int(regexCapture(line, pattern: #"BANDWIDTH=(\d+)"#) ?? "") ?? 0

                guard idx + 1 < lines.count else { continue }
                var mediaUrl = lines[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !mediaUrl.isEmpty, !mediaUrl.hasPrefix("#") else { continue }

                let sep = mediaUrl.contains("?") ? "&" : "?"
                mediaUrl += sep + "playlistType=lowLatency"
                if !pkey.isEmpty { mediaUrl += "&psch=v2&pkey=" + pkey }

                guard !seen.contains(mediaUrl), let url = URL(string: mediaUrl) else { continue }
                seen.insert(mediaUrl)
                let quality = name.isEmpty ? (res.isEmpty ? "自动" : res) : name
                streams.append(StreamInfo(name: quality, url: url, bandwidth: bw, cdn: cdnLabels[i]))
            }
        }

        streams.sort { $0.bandwidth > $1.bandwidth }
        return streams
    }
}

// MARK: - 正则辅助

private func regexCapture(_ text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let m = regex.firstMatch(in: text, range: range), m.numberOfRanges > 1 else { return nil }
    return ns.substring(with: m.range(at: 1))
}

// MARK: - 错误

enum StripchatError: LocalizedError {
    case invalidURL
    case http(Int)
    case needCookie
    case noStream

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的链接"
        case .http(let code): return "请求失败（HTTP \(code)）"
        case .needCookie: return "「我的最爱」需要先在设置中填写登录后的 Cookie"
        case .noStream: return "未找到可用的直播流"
        }
    }
}
