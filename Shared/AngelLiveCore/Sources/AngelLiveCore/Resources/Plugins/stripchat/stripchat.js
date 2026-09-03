// Stripchat 插件（AngelLive LiveParse 插件格式）
// 数据源与解析逻辑对照官方前端 /api/front/v2 与 HLS CDN。
(function () {
    "use strict";

    var API_HOST = "https://zh.stripchat.com";
    var IMG_BASE = "https://static-cdn.strpst.com";
    var PAGE_SIZE = 24;
    var LIVE_TYPE = "stripchat";
    var UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

    // 分类 id -> API 参数（primaryTag / tag / sortBy）
    var CATS = {
        "recommended":  { primary: "girls",  tag: "",        sort: "recommended" },
        "girls_hot":    { primary: "girls",  tag: "popular", sort: "viewersCount" },
        "girls_new":    { primary: "girls",  tag: "new",     sort: "viewersCount" },
        "girls_hd":     { primary: "girls",  tag: "hd",      sort: "viewersCount" },
        "girls_all":    { primary: "girls",  tag: "",        sort: "viewersCount" },
        "girls_cn":     { primary: "girls",  tag: "chinese", sort: "viewersCount" },
        "girls_jp":     { primary: "girls",  tag: "japanese", sort: "viewersCount" },
        "girls_kr":     { primary: "girls",  tag: "korean",  sort: "viewersCount" },
        "girls_vn":     { primary: "girls",  tag: "vietnamese", sort: "viewersCount" },
        "girls_th":     { primary: "girls",  tag: "thai",    sort: "viewersCount" },
        "girls_ua":     { primary: "girls",  tag: "ukrainian", sort: "viewersCount" },
        "girls_ru":     { primary: "girls",  tag: "russian", sort: "viewersCount" },
        "girls_us":     { primary: "girls",  tag: "american", sort: "viewersCount" },
        "girls_co":     { primary: "girls",  tag: "colombian", sort: "viewersCount" },
        "girls_br":     { primary: "girls",  tag: "brazilian", sort: "viewersCount" },
        "girls_mx":     { primary: "girls",  tag: "mexican", sort: "viewersCount" },
        "girls_ve":     { primary: "girls",  tag: "venezuelan", sort: "viewersCount" },
        "girls_de":     { primary: "girls",  tag: "german",  sort: "viewersCount" },
        "girls_fr":     { primary: "girls",  tag: "french",  sort: "viewersCount" },
        "girls_uk":     { primary: "girls",  tag: "uk-models", sort: "viewersCount" },
        "girls_ca":     { primary: "girls",  tag: "canadian", sort: "viewersCount" },
        "girls_it":     { primary: "girls",  tag: "italian", sort: "viewersCount" },
        "girls_es":     { primary: "girls",  tag: "spanish-speaking", sort: "viewersCount" },
        "girls_ro":     { primary: "girls",  tag: "romanian", sort: "viewersCount" },
        "girls_in":     { primary: "girls",  tag: "indian",  sort: "viewersCount" },
        "girls_ar":     { primary: "girls",  tag: "arab",    sort: "viewersCount" },
        "girls_af":     { primary: "girls",  tag: "african", sort: "viewersCount" },
        "girls_teens":  { primary: "girls",  tag: "teens",   sort: "viewersCount" },
        "girls_young":  { primary: "girls",  tag: "young",   sort: "viewersCount" },
        "girls_milfs":  { primary: "girls",  tag: "milfs",   sort: "viewersCount" },
        "girls_mature": { primary: "girls",  tag: "mature",  sort: "viewersCount" },
        "girls_asian":  { primary: "girls",  tag: "asian",   sort: "viewersCount" },
        "girls_latin":  { primary: "girls",  tag: "latin",   sort: "viewersCount" },
        "girls_ebony":  { primary: "girls",  tag: "ebony",   sort: "viewersCount" },
        "girls_white":  { primary: "girls",  tag: "white",   sort: "viewersCount" },
        "girls_mobile": { primary: "girls",  tag: "mobile",  sort: "viewersCount" },
        "girls_vr":     { primary: "girls",  tag: "vr",      sort: "viewersCount" },
        "couples_all":  { primary: "couples", tag: "",        sort: "viewersCount" },
        "couples_cn":   { primary: "couples", tag: "chinese", sort: "viewersCount" },
        "couples_hot":  { primary: "couples", tag: "popular", sort: "viewersCount" },
        "couples_new":  { primary: "couples", tag: "new",     sort: "viewersCount" },
        "men_hot":      { primary: "men",    tag: "popular", sort: "viewersCount" },
        "men_gay":      { primary: "men",    tag: "gays",    sort: "viewersCount" },
        "men_straight": { primary: "men",    tag: "straight", sort: "viewersCount" },
        "men_all":      { primary: "men",    tag: "",        sort: "viewersCount" }
    };

    function headers() {
        return {
            "User-Agent": UA,
            "Accept": "application/json",
            "Referer": "https://zh.stripchat.com/",
            "Origin": "https://zh.stripchat.com"
        };
    }

    async function httpJSON(url) {
        var res = await Host.http.request({ url: url, method: "GET", headers: headers() });
        if (res.status < 200 || res.status >= 300) {
            throw Host.makeError("NETWORK", "HTTP " + res.status + " " + url, {});
        }
        return JSON.parse(res.bodyText || "{}");
    }

    // 带登录 Cookie 的请求（authMode=platform_cookie 由宿主注入平台凭证）
    async function httpJSONAuth(url) {
        var res = await Host.http.request({ url: url, method: "GET", headers: headers(), authMode: "platform_cookie" });
        if (res.status < 200 || res.status >= 300) {
            throw Host.makeError("NETWORK", "HTTP " + res.status + " " + url, {});
        }
        return JSON.parse(res.bodyText || "{}");
    }

    // 我的最爱：多接口尝试（兼容谷歌登录 Cookie）
    async function fetchFavorites(page) {
        var offset = (Number(page || 1) - 1) * PAGE_SIZE;
        var urls = [
            API_HOST + "/api/front/models/favorites?sortBy=lastAdded&limit=" + PAGE_SIZE + "&offset=" + offset,
            API_HOST + "/api/front/models/favorites?sortBy=username&limit=" + PAGE_SIZE + "&offset=" + offset,
            API_HOST + "/api/front/models/favorites/online?sortBy=lastAdded&limit=" + PAGE_SIZE + "&offset=" + offset
        ];
        for (var i = 0; i < urls.length; i++) {
            try {
                var data = await httpJSONAuth(urls[i]);
                var list = data.models || data.favorites || data.items || [];
                if (list && list.length) return list;
            } catch (e) {}
        }
        return [];
    }

    function fullImage(p) {
        if (!p) return "";
        if (String(p).indexOf("http") === 0) return String(p);
        return IMG_BASE + String(p);
    }

    function cover(m) {
        if (m.snapshotTimestamp && m.id) {
            return "https://img.doppiocdn.com/thumbs/" + m.snapshotTimestamp + "/" + m.id;
        }
        if (m.popularSnapshotTimestamp && m.id) {
            return "https://img.doppiocdn.com/thumbs/" + m.popularSnapshotTimestamp + "/" + m.id;
        }
        return fullImage(m.previewUrlThumbSmall || m.avatarUrl || "");
    }

    function toRoom(m) {
        return {
            userName: m.username || "",
            roomTitle: m.username || "",
            roomCover: cover(m),
            userHeadImg: fullImage(m.avatarUrl || ""),
            liveState: (m.status === "public") ? "1" : "0",
            userId: String(m.id || ""),
            roomId: String(m.id || ""),
            liveWatchedCount: String(m.viewersCount || 0)
        };
    }

    async function fetchModels(primary, tag, page, sort) {
        var offset = (Number(page || 1) - 1) * PAGE_SIZE;
        var url = API_HOST + "/api/front/v2/models?limit=" + PAGE_SIZE +
            "&offset=" + offset +
            "&sortBy=" + encodeURIComponent(sort || "viewersCount") +
            "&primaryTag=" + encodeURIComponent(primary || "girls");
        if (tag) url += "&tag=" + encodeURIComponent(tag);
        var data = await httpJSON(url);
        var models = [];
        if (data.blocks && data.blocks.length) {
            for (var i = 0; i < data.blocks.length; i++) {
                var list = data.blocks[i].models || [];
                for (var j = 0; j < list.length; j++) models.push(list[j]);
            }
        } else if (data.models) {
            models = data.models;
        }
        return models;
    }

    function categories() {
        function c(id, title) { return { id: id, parentId: "stripchat", title: title, icon: "" }; }
        return [
            { id: "mine", title: "我的", icon: "", subList: [ c("favorites", "❤️ 我的最爱") ]},
            { id: "recommended", title: "推荐", icon: "", subList: [
                c("recommended", "✨ 最新精选"), c("girls_hot", "🔥 超赞免费直播"),
                c("girls_new", "🆕 最新女主播"), c("girls_hd", "📺 高清 HD 直播")
            ]},
            { id: "region", title: "地区", icon: "", subList: [
                c("girls_cn", "🇨🇳 中文直播"), c("girls_jp", "🇯🇵 日本女孩"), c("girls_kr", "🇰🇷 韩国女孩"),
                c("girls_vn", "🇻🇳 越南女孩"), c("girls_th", "🇹🇭 泰国女孩"), c("girls_ua", "🇺🇦 乌克兰女孩"),
                c("girls_ru", "🇷🇺 俄罗斯女孩"), c("girls_us", "🇺🇸 美国女孩"), c("girls_co", "🇨🇴 哥伦比亚女孩"),
                c("girls_br", "🇧🇷 巴西女孩"), c("girls_mx", "🇲🇽 墨西哥女孩"), c("girls_ve", "🇻🇪 委内瑞拉女孩"),
                c("girls_de", "🇩🇪 德国女孩"), c("girls_fr", "🇫🇷 法国女孩"), c("girls_uk", "🇬🇧 英国女孩"),
                c("girls_ca", "🇨🇦 加拿大女孩"), c("girls_it", "🇮🇹 意大利女孩"), c("girls_es", "🇪🇸 西班牙女孩"),
                c("girls_ro", "🇷🇴 罗马尼亚女孩"), c("girls_in", "🇮🇳 印度女孩"), c("girls_ar", "🇸🇦 阿拉伯女孩"),
                c("girls_af", "🌍 非洲女孩")
            ]},
            { id: "type", title: "类型", icon: "", subList: [
                c("girls_teens", "少女 18+"), c("girls_young", "鲜嫩青年 22+"), c("girls_milfs", "熟女"),
                c("girls_mature", "成熟"), c("girls_asian", "亚洲人"), c("girls_latin", "拉丁人"),
                c("girls_ebony", "黑珍珠"), c("girls_white", "白人"), c("girls_mobile", "📱 手机直播"), c("girls_vr", "🥽 VR 直播")
            ]},
            { id: "girls", title: "女主播", icon: "", subList: [ c("girls_all", "全部女主播") ]},
            { id: "couples", title: "情侣", icon: "", subList: [
                c("couples_all", "💕 情侣直播"), c("couples_cn", "中国情侣"), c("couples_hot", "热门情侣"), c("couples_new", "最新情侣")
            ]},
            { id: "men", title: "男主播", icon: "", subList: [
                c("men_hot", "最受欢迎男主播"), c("men_gay", "男同聊天"), c("men_straight", "直男"), c("men_all", "全部男主播")
            ]}
        ];
    }

    function qualityModels(roomId, presets) {
        var order = ["1080p", "960p", "720p", "480p", "240p", "160p"];
        if (presets && presets.length) {
            order = presets.filter(function (q) { return String(q).indexOf("blurred") < 0; })
                .sort(function (a, b) { return (parseInt(b, 10) || 0) - (parseInt(a, 10) || 0); });
        }
        var bases = [
            "https://edge-hls.saawsedge.com/hls/" + roomId + "/master/",
            "https://edge-hls.growcdnssedge.com/hls/" + roomId + "/master/",
            "https://edge-hls.doppiocdn.com/hls/" + roomId + "/master/"
        ];
        var result = [];
        var qn = 0;
        for (var c = 0; c < bases.length; c++) {
            var qs = [];
            qs.push({ title: "自动（最高画质）", qn: qn++, url: bases[c] + roomId + "_auto.m3u8", liveCodeType: "m3u8", liveType: LIVE_TYPE, roomId: String(roomId) });
            for (var q = 0; q < order.length; q++) {
                var quality = order[q];
                qs.push({ title: quality, qn: qn++, url: bases[c] + roomId + "_" + quality + ".m3u8?playlistType=lowLatency", liveCodeType: "m3u8", liveType: LIVE_TYPE, roomId: String(roomId) });
            }
            result.push({ cdn: "线路 " + (c + 1), qualitys: qs });
        }
        return result;
    }

    async function resolveStreams(roomId) {
        var presets = null;
        try {
            var models = await fetchModels("girls", "", 1, "viewersCount");
            for (var i = 0; i < models.length; i++) {
                if (String(models[i].id) === String(roomId)) { presets = models[i].presets || null; break; }
            }
        } catch (e) {}
        return qualityModels(roomId, presets);
    }

    globalThis.LiveParsePlugin = {
        apiVersion: 1,
        getCategories: async function () {
            return categories();
        },
        getRooms: async function (payload) {
            payload = payload || {};
            var id = payload.id || "recommended";
            var page = Number(payload.page || 1);
            if (id === "favorites") {
                return (await fetchFavorites(page)).map(toRoom);
            }
            var c = CATS[id] || CATS["recommended"];
            var models = await fetchModels(c.primary, c.tag, page, c.sort);
            return models.map(toRoom);
        },
        getPlayback: async function (payload) {
            payload = payload || {};
            var roomId = String(payload.roomId || "");
            if (!roomId) throw Host.makeError("INVALID_ARGS", "missing roomId", {});
            return await resolveStreams(roomId);
        },
        search: async function (payload) {
            payload = payload || {};
            var kw = String(payload.keyword || "").toLowerCase();
            if (!kw) return [];
            var models = await fetchModels("girls", "", 1, "recommended");
            return models.filter(function (m) { return (m.username || "").toLowerCase().indexOf(kw) >= 0; }).map(toRoom);
        },
        getRoomDetail: async function (payload) {
            payload = payload || {};
            var roomId = String(payload.roomId || "");
            var models = await fetchModels("girls", "", 1, "recommended");
            for (var i = 0; i < models.length; i++) {
                if (String(models[i].id) === roomId) return toRoom(models[i]);
            }
            return { userName: "", roomTitle: "", roomCover: "", userHeadImg: "", liveState: "1", userId: roomId, roomId: roomId, liveWatchedCount: "0" };
        },
        getLiveState: async function () {
            return { liveState: "1" };
        },
        getHomeFeed: async function () {
            async function section(id, title, primary, tag, sort) {
                var models = await fetchModels(primary, tag, 1, sort);
                var items = [];
                for (var i = 0; i < models.length; i++) {
                    var room = toRoom(models[i]);
                    items.push({ id: id + "-" + room.roomId, room: room, reason: null });
                }
                return {
                    id: id,
                    kind: "rooms",
                    title: title,
                    subtitle: null,
                    personalized: false,
                    items: items,
                    seeAllTarget: { type: "category", category: { id: id, parentId: "stripchat", title: title, icon: "" } }
                };
            }

            var recommended = await section("recommended", "✨ 最新精选", "girls", "", "recommended");
            var banners = [];
            for (var i = 0; i < Math.min(5, recommended.items.length); i++) {
                var item = recommended.items[i];
                banners.push({
                    id: "banner-" + item.room.roomId,
                    imageURL: item.room.roomCover,
                    title: item.room.userName,
                    subtitle: item.room.liveWatchedCount + " 人观看",
                    badge: "LIVE",
                    target: { type: "room", room: item.room }
                });
            }

            var sections = [recommended];
            var extras = [
                ["girls_hot", "🔥 超赞免费直播", "girls", "popular", "viewersCount"],
                ["girls_new", "🆕 最新女主播", "girls", "new", "viewersCount"],
                ["girls_cn", "🇨🇳 中文直播", "girls", "chinese", "viewersCount"],
                ["couples_hot", "💕 热门情侣", "couples", "popular", "viewersCount"]
            ];
            for (var e = 0; e < extras.length; e++) {
                var spec = extras[e];
                try {
                    sections.push(await section(spec[0], spec[1], spec[2], spec[3], spec[4]));
                } catch (err) {}
            }

            return {
                schemaVersion: 1,
                revision: String(Date.now()),
                ttlSeconds: 60,
                banners: banners,
                sections: sections
            };
        }
    };
})();
