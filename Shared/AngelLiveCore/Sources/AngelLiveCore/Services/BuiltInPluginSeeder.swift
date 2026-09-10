//
//  BuiltInPluginSeeder.swift
//  AngelLiveCore
//
//  StripCam 打开就应该是 Stripchat + Chaturbate。首页只认沙盒已安装插件，
//  所以把包内插件（stripchat / chaturbate / panda）拷进 Application Support。
//  拷贝整个插件目录（manifest + 入口 JS + preload 脚本 + assets 图标），
//  让平台卡片图标与登录入口随插件一起生效。
//

import Foundation

public enum BuiltInPluginSeeder {
    public struct BundledPlugin: Sendable {
        public let pluginId: String
        public let version: String
        /// 入口脚本文件名（manifest.entry）
        public let entry: String

        public init(pluginId: String, version: String, entry: String) {
            self.pluginId = pluginId
            self.version = version
            self.entry = entry
        }
    }

    /// 内置插件清单：版本号必须 >= 线上订阅源版本，避免被旧版覆盖回退。
    public static let bundledPlugins: [BundledPlugin] = [
        BundledPlugin(pluginId: "stripchat", version: "1.0.2", entry: "stripchat.js"),
        BundledPlugin(pluginId: "chaturbate", version: "1.1.0", entry: "index.js"),
        BundledPlugin(pluginId: "panda", version: "2.0.4", entry: "index.js")
    ]

    /// 兼容旧调用：主插件 = stripchat。
    public static let pluginId = "stripchat"
    public static let bundledVersion = "1.0.2"

    @discardableResult
    public static func seedIfNeeded() -> Bool {
        var seededAny = false
        for plugin in bundledPlugins {
            if seedPlugin(plugin) {
                seededAny = true
            }
        }
        return seededAny
    }

    /// 安装单个内置插件。已安装同版本或更新版本时跳过。
    @discardableResult
    static func seedPlugin(_ plugin: BundledPlugin) -> Bool {
        let storage = LiveParsePlugins.shared.storage
        let installed = storage.listInstalledVersions(pluginId: plugin.pluginId)
            .map(\.lastPathComponent)
        if installed.contains(where: { semverCompare($0, plugin.version) >= 0 }) {
            return false
        }

        guard let sourceDir = findBundledPluginDirectory(pluginId: plugin.pluginId) else {
            NSLog("[BuiltInPluginSeeder] bundled %@ plugin not found in app bundle", plugin.pluginId)
            return false
        }

        do {
            try storage.ensureDirectories()
            let dest = storage.pluginVersionDirectory(pluginId: plugin.pluginId, version: plugin.version)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            // 整目录拷贝：manifest.json + 入口 JS + preload 脚本 + assets/
            let items = try FileManager.default.contentsOfDirectory(
                at: sourceDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for item in items {
                let destItem = dest.appendingPathComponent(item.lastPathComponent)
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    try FileManager.default.copyItem(at: item, to: destItem)
                } else {
                    try FileManager.default.copyItem(at: item, to: destItem)
                }
            }
            try LiveParsePlugins.shared.reload()
            PlatformCapability.invalidateCache()
            NSLog("[BuiltInPluginSeeder] installed %@ %@", plugin.pluginId, plugin.version)
            return true
        } catch {
            NSLog("[BuiltInPluginSeeder] install %@ failed: %@", plugin.pluginId, error.localizedDescription)
            return false
        }
    }

    /// 在 app bundle 中定位 `Plugins/<pluginId>/` 目录（SPM .copy 资源或主 bundle）。
    private static func findBundledPluginDirectory(pluginId: String) -> URL? {
        for bundle in [Bundle.module, Bundle.main] {
            let candidates: [URL?] = [
                bundle.url(forResource: pluginId, withExtension: nil, subdirectory: "Plugins"),
                bundle.resourceURL?.appendingPathComponent("Plugins/\(pluginId)", isDirectory: true),
                bundle.bundleURL.appendingPathComponent("Plugins/\(pluginId)", isDirectory: true)
            ]
            if let url = candidates.compactMap({ $0 }).first(where: {
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
            }) {
                return url
            }
        }
        return nil
    }
}
