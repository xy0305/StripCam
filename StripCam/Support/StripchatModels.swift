//
//  StripchatModels.swift
//  StripCam
//
//  Stripchat 的分类目录、主播模型与直播流模型。
//  字段与解析逻辑严格对照插件脚本（Stripchat 直播模块 v6.4）。
//

import Foundation

// MARK: - 分类

struct StripchatCategory: Identifiable, Hashable {
    let id: String
    let title: String
    /// girls / couples / men / favorites
    let primaryTag: String
    /// 空串表示不过滤标签
    let tag: String
    /// viewersCount / recommended / lastAdded
    let sortBy: String
    let requiresCookie: Bool

    init(
        id: String,
        title: String,
        primaryTag: String,
        tag: String = "",
        sortBy: String = "viewersCount",
        requiresCookie: Bool = false
    ) {
        self.id = id
        self.title = title
        self.primaryTag = primaryTag
        self.tag = tag
        self.sortBy = sortBy
        self.requiresCookie = requiresCookie
    }
}

struct StripchatSection: Identifiable {
    let id: String
    let title: String
    let categories: [StripchatCategory]
}

enum StripchatCatalog {
    /// 与官方插件一致的完整分类，分组用于侧边栏展示。
    static let sections: [StripchatSection] = [
        StripchatSection(id: "mine", title: "我的", categories: [
            StripchatCategory(id: "favorites", title: "❤️ 我的最爱", primaryTag: "favorites", sortBy: "lastAdded", requiresCookie: true),
        ]),
        StripchatSection(id: "recommended", title: "推荐", categories: [
            StripchatCategory(id: "recommended", title: "✨ 匹配您的最新精选", primaryTag: "girls", sortBy: "recommended"),
            StripchatCategory(id: "girls_hot", title: "🔥 超赞免费直播", primaryTag: "girls", tag: "popular"),
            StripchatCategory(id: "girls_new", title: "🆕 最新女主播", primaryTag: "girls", tag: "new"),
            StripchatCategory(id: "girls_hd", title: "📺 高清 HD 直播", primaryTag: "girls", tag: "hd"),
        ]),
        StripchatSection(id: "region", title: "地区", categories: [
            StripchatCategory(id: "girls_cn", title: "🇨🇳 中文直播", primaryTag: "girls", tag: "chinese"),
            StripchatCategory(id: "girls_jp", title: "🇯🇵 日本女孩", primaryTag: "girls", tag: "japanese"),
            StripchatCategory(id: "girls_kr", title: "🇰🇷 韩国女孩", primaryTag: "girls", tag: "korean"),
            StripchatCategory(id: "girls_vn", title: "🇻🇳 越南女孩", primaryTag: "girls", tag: "vietnamese"),
            StripchatCategory(id: "girls_th", title: "🇹🇭 泰国女孩", primaryTag: "girls", tag: "thai"),
            StripchatCategory(id: "girls_ua", title: "🇺🇦 乌克兰女孩", primaryTag: "girls", tag: "ukrainian"),
            StripchatCategory(id: "girls_ru", title: "🇷🇺 俄罗斯女孩", primaryTag: "girls", tag: "russian"),
            StripchatCategory(id: "girls_us", title: "🇺🇸 美国女孩", primaryTag: "girls", tag: "american"),
            StripchatCategory(id: "girls_co", title: "🇨🇴 哥伦比亚女孩", primaryTag: "girls", tag: "colombian"),
            StripchatCategory(id: "girls_br", title: "🇧🇷 巴西女孩", primaryTag: "girls", tag: "brazilian"),
            StripchatCategory(id: "girls_mx", title: "🇲🇽 墨西哥女孩", primaryTag: "girls", tag: "mexican"),
            StripchatCategory(id: "girls_ve", title: "🇻🇪 委内瑞拉女孩", primaryTag: "girls", tag: "venezuelan"),
            StripchatCategory(id: "girls_de", title: "🇩🇪 德国女孩", primaryTag: "girls", tag: "german"),
            StripchatCategory(id: "girls_fr", title: "🇫🇷 法国女孩", primaryTag: "girls", tag: "french"),
            StripchatCategory(id: "girls_uk", title: "🇬🇧 英国女孩", primaryTag: "girls", tag: "uk-models"),
            StripchatCategory(id: "girls_ca", title: "🇨🇦 加拿大女孩", primaryTag: "girls", tag: "canadian"),
            StripchatCategory(id: "girls_it", title: "🇮🇹 意大利女孩", primaryTag: "girls", tag: "italian"),
            StripchatCategory(id: "girls_es", title: "🇪🇸 西班牙女孩", primaryTag: "girls", tag: "spanish-speaking"),
            StripchatCategory(id: "girls_ro", title: "🇷🇴 罗马尼亚女孩", primaryTag: "girls", tag: "romanian"),
            StripchatCategory(id: "girls_in", title: "🇮🇳 印度女孩", primaryTag: "girls", tag: "indian"),
            StripchatCategory(id: "girls_ar", title: "🇸🇦 阿拉伯女孩", primaryTag: "girls", tag: "arab"),
            StripchatCategory(id: "girls_af", title: "🌍 非洲女孩", primaryTag: "girls", tag: "african"),
        ]),
        StripchatSection(id: "type", title: "类型", categories: [
            StripchatCategory(id: "girls_teens", title: "少女 18+", primaryTag: "girls", tag: "teens"),
            StripchatCategory(id: "girls_young", title: "鲜嫩青年 22+", primaryTag: "girls", tag: "young"),
            StripchatCategory(id: "girls_milfs", title: "熟女", primaryTag: "girls", tag: "milfs"),
            StripchatCategory(id: "girls_mature", title: "成熟", primaryTag: "girls", tag: "mature"),
            StripchatCategory(id: "girls_asian", title: "亚洲人", primaryTag: "girls", tag: "asian"),
            StripchatCategory(id: "girls_latin", title: "拉丁人", primaryTag: "girls", tag: "latin"),
            StripchatCategory(id: "girls_ebony", title: "黑珍珠", primaryTag: "girls", tag: "ebony"),
            StripchatCategory(id: "girls_white", title: "白人", primaryTag: "girls", tag: "white"),
            StripchatCategory(id: "girls_mobile", title: "📱 手机直播", primaryTag: "girls", tag: "mobile"),
            StripchatCategory(id: "girls_vr", title: "🥽 VR 直播", primaryTag: "girls", tag: "vr"),
        ]),
        StripchatSection(id: "girls", title: "女主播", categories: [
            StripchatCategory(id: "girls_all", title: "全部女主播", primaryTag: "girls"),
        ]),
        StripchatSection(id: "couples", title: "情侣", categories: [
            StripchatCategory(id: "couples_all", title: "💕 情侣直播", primaryTag: "couples"),
            StripchatCategory(id: "couples_cn", title: "中国情侣", primaryTag: "couples", tag: "chinese"),
            StripchatCategory(id: "couples_hot", title: "热门情侣", primaryTag: "couples", tag: "popular"),
            StripchatCategory(id: "couples_new", title: "最新情侣", primaryTag: "couples", tag: "new"),
        ]),
        StripchatSection(id: "men", title: "男主播", categories: [
            StripchatCategory(id: "men_hot", title: "最受欢迎男主播", primaryTag: "men", tag: "popular"),
            StripchatCategory(id: "men_gay", title: "男同聊天", primaryTag: "men", tag: "gays"),
            StripchatCategory(id: "men_straight", title: "直男", primaryTag: "men", tag: "straight"),
            StripchatCategory(id: "men_all", title: "全部男主播", primaryTag: "men"),
        ]),
    ]

    static let allCategories: [StripchatCategory] = sections.flatMap(\.categories)

    /// 默认进入的分类
    static let defaultCategory: StripchatCategory = {
        allCategories.first { $0.id == "recommended" } ?? allCategories[0]
    }()
}

// MARK: - 主播模型

struct StripModel: Identifiable, Hashable {
    let id: String
    let username: String
    let gender: String
    let status: String
    let viewersCount: Int
    let isHd: Bool
    let isNew: Bool
    let isLovense: Bool
    let country: String
    let snapshotTimestamp: Int
    let popularSnapshotTimestamp: Int
    let previewUrlThumbSmall: String
    let avatarUrl: String
    let presets: [String]

    init(json: [String: Any]) {
        id = StripModel.str(json["id"])
        username = StripModel.str(json["username"])
        gender = StripModel.str(json["gender"])
        status = StripModel.str(json["status"])
        viewersCount = StripModel.int(json["viewersCount"])
        isHd = StripModel.bool(json["isHd"])
        isNew = StripModel.bool(json["isNew"])
        isLovense = StripModel.bool(json["isLovense"])
        country = StripModel.str(json["country"])
        snapshotTimestamp = StripModel.int(json["snapshotTimestamp"])
        popularSnapshotTimestamp = StripModel.int(json["popularSnapshotTimestamp"])
        previewUrlThumbSmall = StripModel.str(json["previewUrlThumbSmall"])
        avatarUrl = StripModel.str(json["avatarUrl"])
        presets = StripModel.strArray(json["presets"])
    }

    private static let imgBase = "https://static-cdn.strpst.com"

    static func fullImage(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if path.hasPrefix("http") { return path }
        return imgBase + path
    }

    /// 封面图（优先实时缩略图）
    var coverURL: URL? {
        var cover = ""
        if snapshotTimestamp > 0 && !id.isEmpty {
            cover = "https://img.doppiocdn.com/thumbs/\(snapshotTimestamp)/\(id)"
        } else if popularSnapshotTimestamp > 0 && !id.isEmpty {
            cover = "https://img.doppiocdn.com/thumbs/\(popularSnapshotTimestamp)/\(id)"
        } else {
            cover = StripModel.fullImage(previewUrlThumbSmall.isEmpty ? avatarUrl : previewUrlThumbSmall)
        }
        return URL(string: cover)
    }

    var avatarURL: URL? {
        let a = StripModel.fullImage(avatarUrl)
        guard !a.isEmpty else { return nil }
        return URL(string: a)
    }

    // MARK: - 解析辅助

    static func str(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    static func int(_ any: Any?) -> Int {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) ?? 0 }
        return 0
    }

    static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }

    static func strArray(_ any: Any?) -> [String] {
        guard let arr = any as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }
    }
}

// MARK: - 直播流

struct StreamInfo: Identifiable, Hashable {
    let name: String        // "自动" / "1080p" / ...
    let url: URL
    let bandwidth: Int
    let cdn: String         // 线路标签
    var isAuto: Bool = false

    var id: String { url.absoluteString }
}

// MARK: - 可播放模型（进入播放器的最小信息）

struct PlayableModel: Identifiable, Hashable {
    let id: String
    let username: String
    let avatarURL: URL?
    let coverURL: URL?
    let viewersCount: Int
    let status: String
    let gender: String
    let country: String
    let isHd: Bool
    let isNew: Bool
    let isLovense: Bool
    let presets: [String]

    init(model: StripModel) {
        id = model.id
        username = model.username
        avatarURL = model.avatarURL
        coverURL = model.coverURL
        viewersCount = model.viewersCount
        status = model.status
        gender = model.gender
        country = model.country
        isHd = model.isHd
        isNew = model.isNew
        isLovense = model.isLovense
        presets = model.presets
    }

    init(saved: SavedModel) {
        id = saved.id
        username = saved.username
        avatarURL = saved.avatarURL
        coverURL = saved.coverURL
        viewersCount = saved.viewersCount
        status = saved.status
        gender = saved.gender
        country = saved.country
        isHd = saved.isHd
        isNew = saved.isNew
        isLovense = saved.isLovense
        presets = []
    }
}

// MARK: - 本地收藏（持久化子集）

struct SavedModel: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let coverURLString: String
    let avatarURLString: String
    let viewersCount: Int
    let status: String
    let gender: String
    let country: String
    let isHd: Bool
    let isNew: Bool
    let isLovense: Bool

    init(model: StripModel) {
        id = model.id
        username = model.username
        coverURLString = model.coverURL?.absoluteString ?? ""
        avatarURLString = model.avatarURL?.absoluteString ?? ""
        viewersCount = model.viewersCount
        status = model.status
        gender = model.gender
        country = model.country
        isHd = model.isHd
        isNew = model.isNew
        isLovense = model.isLovense
    }

    init(playable: PlayableModel) {
        id = playable.id
        username = playable.username
        coverURLString = playable.coverURL?.absoluteString ?? ""
        avatarURLString = playable.avatarURL?.absoluteString ?? ""
        viewersCount = playable.viewersCount
        status = playable.status
        gender = playable.gender
        country = playable.country
        isHd = playable.isHd
        isNew = playable.isNew
        isLovense = playable.isLovense
    }

    var coverURL: URL? { URL(string: coverURLString) }
    var avatarURL: URL? { URL(string: avatarURLString) }
}
