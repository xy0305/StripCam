// Chaturbate 插件（AngelLive LiveParse 插件格式）
// 从「涩涩聚合」adultlive 插件中抽离出的 chaturbate（平台2）独立实现。
// 数据源对照官网 /api/ts/roomlist/room-list/ 与 get_edge_hls_url_ajax。
(function () {
    "use strict";

    var PLUGIN_ID = "chaturbate";
    var LIVE_TYPE = "chaturbate";
    var BASE_URL = "https://www.chaturbate.com";
    var PLAYBACK_UA = "libmpv";
    var WEB_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

    // ---- 工具函数 ----

    function str(v) { return v === undefined || v === null ? "" : String(v); }
    function int(v, fb) { var n = Number(v); return isFinite(n) ? Math.trunc(n) : fb; }
    function page(v) { return Math.max(1, int(v, 1)); }
    function pageSize(v, fb, mx) { return Math.max(1, Math.min(mx || 100, int(v, fb || 24))); }

    function throwErr(code, message, ctx) {
        if (globalThis.Host && typeof Host.raise === "function") Host.raise(code, message, ctx || {});
        if (globalThis.Host && typeof Host.makeError === "function") throw Host.makeError(code || "UNKNOWN", message || "", ctx || {});
        throw new Error("LP_PLUGIN_ERROR:" + JSON.stringify({ code: String(code || "UNKNOWN"), message: String(message || ""), context: ctx || {} }));
    }

    function parseJSON(text, fb) { try { return JSON.parse(str(text)); } catch (e) { return fb; } }

    function form(data) {
        return Object.keys(data || {}).map(function (k) {
            return encodeURIComponent(str(k)) + "=" + encodeURIComponent(str(data[k])).replace(/%20/g, "+");
        }).join("&");
    }

    function firstString(obj, keys) {
        for (var i = 0; i < keys.length; i++) {
            var v = obj && obj[keys[i]];
            if (typeof v === "string" && v) return v;
            if (v !== undefined && v !== null && typeof v !== "object") return String(v);
            if (v && typeof v === "object") {
                var n = v.url || v.src || v.medium || v.small || v.original || v.webp || v.address;
                if (n) return str(n);
            }
        }
        return "";
    }

    function headers(referer, accept) {
        return {
            "User-Agent": WEB_UA,
            "Accept": accept || "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Referer": referer || BASE_URL + "/"
        };
    }

    async function requestJSON(url, referer, method, body, extraHeaders) {
        var res = await Host.http.request({
            platformId: PLUGIN_ID,
            // platform_cookie：宿主有保存登录态时自动注入 Cookie；未登录则匿名请求。
            authMode: "platform_cookie",
            request: {
                url: url,
                method: method || "GET",
                headers: Object.assign({}, headers(referer), extraHeaders || {}),
                body: body || null,
                timeout: 20
            }
        });
        var status = int(res && (res.status || res.statusCode), 0);
        if (status < 200 || status >= 300) throwErr("UPSTREAM", "chaturbate request failed", { status: status, url: url });
        var data = parseJSON(res && res.bodyText, null);
        if (data === null || data === undefined) throwErr("INVALID_RESPONSE", "chaturbate json response invalid", { url: url });
        return data;
    }

    // ---- 分类 ----

    var DYNAMIC_TAG_LIMIT = 20;

    var FALLBACK_TAGS = [
        { id: "tag:lovense", title: "Lovense", icon: "" },
        { id: "tag:squirt", title: "Squirt", icon: "" },
        { id: "tag:bigass", title: "Big Ass", icon: "" },
        { id: "tag:anal", title: "Anal", icon: "" },
        { id: "tag:new", title: "New", icon: "" },
        { id: "tag:bigboobs", title: "Big Boobs", icon: "" },
        { id: "tag:latina", title: "Latina", icon: "" },
        { id: "tag:18", title: "18", icon: "" },
        { id: "tag:teen", title: "Teen 18+", icon: "" },
        { id: "tag:cum", title: "Cum", icon: "" },
        { id: "tag:young", title: "Young", icon: "" },
        { id: "tag:bigcock", title: "Big Cock", icon: "" },
        { id: "tag:asian", title: "Asian", icon: "" },
        { id: "tag:ebony", title: "Ebony", icon: "" },
        { id: "tag:feet", title: "Feet", icon: "" },
        { id: "tag:skinny", title: "Skinny", icon: "" },
        { id: "tag:natural", title: "Natural", icon: "" },
        { id: "tag:smalltits", title: "Small Tits", icon: "" },
        { id: "tag:milf", title: "MILF", icon: "" },
        { id: "tag:toys", title: "Toys", icon: "" }
    ];

    var FIXED_TAGS = [
        { id: "tag:latina", title: "Latina", icon: "" },
        { id: "tag:asian", title: "Asian", icon: "" },
        { id: "tag:ebony", title: "Ebony", icon: "" }
    ];

    var REGION_CATEGORIES = [
        { id: "region:north-american-cams", title: "North American Cams", icon: "" },
        { id: "region:south-american-cams", title: "South American Cams", icon: "" },
        { id: "region:euro-russian-cams", title: "Euro Russian Cams", icon: "" },
        { id: "region:asian-cams", title: "Asian Cams", icon: "" },
        { id: "region:other-region-cams", title: "Other Region Cams", icon: "" }
    ];

    function mergeCategories() {
        var merged = [], seen = {};
        for (var i = 0; i < arguments.length; i++) {
            var list = Array.isArray(arguments[i]) ? arguments[i] : [];
            for (var j = 0; j < list.length; j++) {
                var item = list[j] || {};
                var id = str(item.id).trim();
                if (!id || seen[id]) continue;
                seen[id] = true;
                merged.push({ id: id, title: item.title || id, icon: item.icon || "" });
            }
        }
        return merged;
    }

    var BASE_CATEGORIES = mergeCategories(FALLBACK_TAGS, FIXED_TAGS, REGION_CATEGORIES);

    function tagTitle(tag) {
        var value = str(tag).trim().toLowerCase();
        var map = {
            "18": "18", anal: "Anal", asian: "Asian", bbw: "BBW", bdsm: "BDSM",
            bigass: "Big Ass", bigboobs: "Big Boobs", bigcock: "Big Cock", bigtits: "Big Tits",
            blonde: "Blonde", cum: "Cum", ebony: "Ebony", feet: "Feet", fuckmachine: "Fuck Machine",
            hairy: "Hairy", latina: "Latina", lesbian: "Lesbian", lovense: "Lovense", mature: "Mature",
            milf: "MILF", natural: "Natural", new: "New", petite: "Petite", skinny: "Skinny",
            smalltits: "Small Tits", squirt: "Squirt", teen: "Teen 18+", toys: "Toys", young: "Young"
        };
        if (map[value]) return map[value];
        var spaced = value.replace(/[_-]+/g, " ").replace(/([a-z])([0-9])/g, "$1 $2").replace(/([0-9])([a-z])/g, "$1 $2");
        return spaced.replace(/\b[a-z]/g, function (c) { return c.toUpperCase(); });
    }

    function tagCategory(tag) {
        var value = str(tag).replace(/^#+/, "").trim().toLowerCase();
        if (!/^[a-z0-9_-]{1,64}$/.test(value)) return null;
        return { id: "tag:" + value, title: tagTitle(value), icon: "" };
    }

    function hashtagTableURL(limit) {
        return BASE_URL + "/api/ts/hashtags/tag-table-data/?" + form({
            sort: "-rc", page: "1", limit: String(Math.max(1, int(limit, DYNAMIC_TAG_LIMIT))), gender: ""
        });
    }

    function pickTopHashtags(data) {
        var list = Array.isArray(data && data.hashtags) ? data.hashtags : [];
        var picked = [];
        for (var i = 0; i < list.length; i++) {
            var item = list[i] || {};
            var c = tagCategory(item.hashtag || item.tag || item.name);
            if (!c) continue;
            picked.push({ category: c, roomCount: int(item.room_count !== undefined ? item.room_count : item.roomCount, 0), index: i });
        }
        picked.sort(function (l, r) { return r.roomCount - l.roomCount || l.index - r.index; });
        var cats = [];
        for (var j = 0; j < picked.length && cats.length < DYNAMIC_TAG_LIMIT; j++) cats.push(picked[j].category);
        return cats;
    }

    async function fetchTopHashtagCategories() {
        var data = await requestJSON(hashtagTableURL(DYNAMIC_TAG_LIMIT), BASE_URL + "/tags/", "GET", null, { "X-Requested-With": "XMLHttpRequest" });
        var dynamic = pickTopHashtags(data);
        if (!dynamic.length) return BASE_CATEGORIES;
        return mergeCategories(dynamic, FIXED_TAGS, REGION_CATEGORIES);
    }

    // ---- 房间/详情/播放 ----

    function sourceRoomURL(username) {
        return "https://chaturbate.com/" + encodeURIComponent(username) + "/";
    }

    function status(value) {
        var s = str(value).toLowerCase();
        if (s === "public") return "1";
        if (s === "private" || s === "hidden") return "2";
        return "3";
    }

    function toRoom(model) {
        var username = str(model && model.username).trim();
        return {
            userName: username,
            roomTitle: str(model && (model.room_subject || model.subject || username)),
            roomCover: firstString(model, ["image_url_360x270", "image_url", "image", "img"]),
            userHeadImg: firstString(model, ["image_url", "avatar", "avatarUrl"]),
            liveType: LIVE_TYPE,
            liveState: status(model && model.current_show),
            userId: sourceRoomURL(username),
            roomId: username,
            liveWatchedCount: String(Math.max(0, int(model && (model.num_users || model.viewers), 0)))
        };
    }

    function categorySlug(raw) {
        var v = str(raw || "featured").trim().toLowerCase();
        if (!v || v === "all" || v === "featured-cams" || v === "home") return "featured";
        return v;
    }

    var REGION_MAP = {
        "north-american-cams": "NA", "south-american-cams": "SA", "asian-cams": "AS",
        "euro-russian-cams": "ER", "other-region-cams": "O"
    };

    function categorySpec(raw) {
        var value = categorySlug(raw);
        var parts = value.split(":");
        if (parts[0] === "tag" && parts.length >= 2) {
            var tag = parts.slice(1).join(":").trim().toLowerCase();
            return tag ? { type: "tag", tag: tag, slug: "tag/" + tag } : { type: "featured", slug: "featured" };
        }
        if (parts[0] === "region" && parts.length >= 2) {
            var slug = parts.slice(1).join(":").trim().toLowerCase();
            return { type: "region", region: REGION_MAP[slug] || slug.toUpperCase(), slug: slug };
        }
        if (REGION_MAP[value]) return { type: "region", region: REGION_MAP[value], slug: value };
        return { type: "legacy", slug: value };
    }

    function roomListParams(raw, payload) {
        var spec = categorySpec(raw);
        var categoryId = spec.slug;
        var p = page(payload && payload.page);
        var ps = pageSize(payload && payload.pageSize, 24, 90);
        var params = { offset: String((p - 1) * ps), limit: String(ps) };
        if (spec.type === "tag") params.hashtags = spec.tag;
        else if (spec.type === "region") params.regions = spec.region;
        else if (categoryId === "female-cams") params.genders = "f";
        else if (categoryId === "male-cams") params.genders = "m";
        else if (categoryId === "couple-cams") params.genders = "c";
        else if (categoryId === "trans-cams") params.genders = "t";
        else if (categoryId === "new-cams") params.new_cams = "true";
        else if (categoryId === "gaming-cams") params.gaming = "true";
        else if (categoryId === "teen-cams") { params.from_age = "18"; params.to_age = "20"; }
        else if (categoryId === "18to21-cams") { params.from_age = "18"; params.to_age = "22"; }
        else if (categoryId === "20to30-cams") { params.from_age = "20"; params.to_age = "31"; }
        else if (categoryId === "30to50-cams") { params.from_age = "30"; params.to_age = "51"; }
        else if (categoryId === "mature-cams") { params.from_age = "50"; params.to_age = "100"; }
        return params;
    }

    function roomListURL(payload, categoryId) {
        return BASE_URL + "/api/ts/roomlist/room-list/?" + form(roomListParams(categoryId, payload));
    }

    function categoryReferer(categoryId) {
        var spec = categorySpec(categoryId);
        var slug = spec.slug;
        return slug === "featured" ? BASE_URL + "/" : BASE_URL + "/" + slug + "/";
    }

    async function fetchInfo(username) {
        var body = form({ room_slug: username, bandwidth: "high" });
        var data = await requestJSON(
            "https://chaturbate.com/get_edge_hls_url_ajax/",
            "https://www.chaturbate.com/" + encodeURIComponent(username),
            "POST", body,
            { "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8", "X-Requested-With": "XMLHttpRequest" }
        );
        data.username = data.username || username;
        return data;
    }

    function playback(username, info) {
        var url = str(info.url);
        if (info.cmaf_edge) {
            url = url.replace("playlist.m3u8", "playlist_sfm4s.m3u8").replace(/live-.+amlst/, "live-c-fhls/amlst");
        }
        return [{
            cdn: "chaturbate",
            qualitys: [{
                roomId: username,
                title: "原画",
                qn: 0,
                url: url,
                liveCodeType: "m3u8",
                liveType: LIVE_TYPE,
                userAgent: PLAYBACK_UA,
                headers: {
                    "User-Agent": PLAYBACK_UA,
                    Referer: "https://www.chaturbate.com/" + encodeURIComponent(username)
                }
            }]
        }];
    }

    // ---- 首页 feed ----

    async function fetchRoomsForFeed(categoryId, limit) {
        var data = await requestJSON(roomListURL({ page: 1, pageSize: limit || 24 }, categoryId || "featured"), categoryReferer(categoryId || "featured"), "GET", null, { "X-Requested-With": "XMLHttpRequest" });
        var list = Array.isArray(data && data.rooms) ? data.rooms : [];
        return list.map(toRoom).filter(function (r) { return !!r.userName; });
    }

    async function section(id, title, categoryId, limit) {
        var rooms = await fetchRoomsForFeed(categoryId, limit);
        var items = [];
        for (var i = 0; i < rooms.length; i++) {
            var room = rooms[i];
            items.push({ id: id + "-" + room.roomId, room: room, reason: null });
        }
        return {
            id: id,
            kind: "rooms",
            title: title,
            subtitle: null,
            personalized: false,
            items: items,
            seeAllTarget: { type: "category", category: { id: id, parentId: "chaturbate", title: title, icon: "" } }
        };
    }

    // ---- 插件导出 ----

    globalThis.LiveParsePlugin = {
        apiVersion: 1,

        getCategories: async function () {
            var groups = [];
            var dynamic = [];
            try { dynamic = await fetchTopHashtagCategories(); } catch (e) { dynamic = BASE_CATEGORIES; }

            groups.push({ id: "recommended", title: "推荐", icon: "", subList: [{ id: "featured", parentId: "recommended", title: "精选直播", icon: "" }] });
            groups.push({
                id: "type", title: "类型", icon: "", subList: dynamic.map(function (c) {
                    return { id: c.id, parentId: "type", title: c.title, icon: "" };
                })
            });
            groups.push({
                id: "region", title: "地区", icon: "", subList: REGION_CATEGORIES.map(function (c) {
                    return { id: c.id, parentId: "region", title: c.title, icon: "" };
                })
            });
            return groups;
        },

        getRooms: async function (payload) {
            payload = payload || {};
            var id = payload.id || "featured";
            var p = Number(payload.page || 1);
            var data = await requestJSON(
                roomListURL({ page: p, pageSize: payload.pageSize }, id),
                categoryReferer(id), "GET", null, { "X-Requested-With": "XMLHttpRequest" }
            );
            var list = Array.isArray(data && data.rooms) ? data.rooms : [];
            return list.map(toRoom).filter(function (r) { return !!r.userName; });
        },

        getPlayback: async function (payload) {
            payload = payload || {};
            var username = str(payload.roomId || payload.userId || payload.username || "").trim();
            if (!username) throwErr("INVALID_ARGS", "roomId is required", {});
            var info = await fetchInfo(username);
            var st = status(info.room_status);
            if (st !== "1" || !info.url) throwErr("NOT_LIVE", "chaturbate room is not public", { roomId: username });
            return playback(username, info);
        },

        search: async function (payload) {
            payload = payload || {};
            var kw = str(payload.keyword || "").replace(/^@+/, "");
            if (!/^[A-Za-z0-9_-]{2,80}$/.test(kw)) return [];
            var info = await fetchInfo(kw);
            var room = toRoom({ username: kw, room_subject: kw, current_show: info.room_status, num_users: info.num_users || 0 });
            return room.liveState === "3" ? [] : [room];
        },

        getRoomDetail: async function (payload) {
            payload = payload || {};
            var username = str(payload.roomId || payload.userId || payload.username || payload.id || "").trim();
            if (!username) throwErr("INVALID_ARGS", "roomId is required", {});
            var info = await fetchInfo(username);
            return toRoom({ username: username, room_subject: username, current_show: info.room_status, num_users: info.num_users || 0 });
        },

        getLiveState: async function (payload) {
            payload = payload || {};
            var username = str(payload.roomId || payload.userId || payload.username || "").trim();
            var info = await fetchInfo(username);
            return { liveState: status(info.room_status) };
        },

        resolveShare: async function (payload) {
            payload = payload || {};
            var source = str(payload.shareCode || payload.url || payload.text || "").trim();
            var pathMatch = source.match(/(?:^|\/\/)(?:www\.)?chaturbate\.com\/(?!in(?:[/?#]|$))([A-Za-z0-9_-]{2,80})(?:[/?#]|$)/i);
            var queryMatch = source.match(/[?&](?:room|room_slug)=([A-Za-z0-9_-]{2,80})(?:[&#]|$)/i);
            var username = pathMatch && pathMatch[1] ? pathMatch[1] : (queryMatch && queryMatch[1] ? queryMatch[1] : "");
            if (!username) throwErr("PARSE", "cannot parse chaturbate share", { shareCode: source });
            return this.getRoomDetail({ roomId: username });
        },

        getHomeFeed: async function () {
            var recommended = await section("recommended", "✨ 精选直播", "featured", 24);
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
                ["female", "👩 女主播", "female-cams"],
                ["couple", "💑 情侣", "couple-cams"],
                ["male", "👨 男主播", "male-cams"],
                ["trans", "🏳️‍⚧️ 跨性别", "trans-cams"]
            ];
            for (var e = 0; e < extras.length; e++) {
                var spec = extras[e];
                try { sections.push(await section(spec[0], spec[1], spec[2], 24)); } catch (err) {}
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
