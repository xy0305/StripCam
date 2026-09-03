//
//  BuiltInPluginSeeder.swift
//  AngelLiveCore
//
//  StripCam 打开就应该是 Stripchat。首页只认沙盒已安装插件，
//  所以把包内 stripchat 插件拷进 Application Support。
//

import Foundation

public enum BuiltInPluginSeeder {
    public static let pluginId = "stripchat"
    public static let bundledVersion = "1.0.2"

    @discardableResult
    public static func seedIfNeeded() -> Bool {
        let storage = LiveParsePlugins.shared.storage
        let installed = storage.listInstalledVersions(pluginId: pluginId)
            .map(\.lastPathComponent)
        if installed.contains(where: { semverCompare($0, bundledVersion) >= 0 }) {
            return false
        }

        guard let jsURL = findBundledJS(),
              let manifestData = findBundledManifestData() else {
            NSLog("[BuiltInPluginSeeder] bundled stripchat plugin not found in app bundle")
            return false
        }

        do {
            try storage.ensureDirectories()
            let dest = storage.pluginVersionDirectory(pluginId: pluginId, version: bundledVersion)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let jsDest = dest.appendingPathComponent("stripchat.js")
            if FileManager.default.fileExists(atPath: jsDest.path) {
                try FileManager.default.removeItem(at: jsDest)
            }
            try FileManager.default.copyItem(at: jsURL, to: jsDest)
            try manifestData.write(to: dest.appendingPathComponent("manifest.json"), options: .atomic)
            try LiveParsePlugins.shared.reload()
            PlatformCapability.invalidateCache()
            NSLog("[BuiltInPluginSeeder] installed %@ %@", pluginId, bundledVersion)
            return true
        } catch {
            NSLog("[BuiltInPluginSeeder] install failed: %@", error.localizedDescription)
            return false
        }
    }

    private static func findBundledJS() -> URL? {
        for bundle in [Bundle.module, Bundle.main] {
            let candidates: [URL?] = [
                bundle.url(forResource: "stripchat", withExtension: "js", subdirectory: "Plugins/stripchat"),
                bundle.url(forResource: "stripchat", withExtension: "js"),
                bundle.resourceURL?.appendingPathComponent("Plugins/stripchat/stripchat.js"),
                bundle.bundleURL.appendingPathComponent("Plugins/stripchat/stripchat.js")
            ]
            if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return url
            }
        }
        return nil
    }

    private static func findBundledManifestData() -> Data? {
        for bundle in [Bundle.module, Bundle.main] {
            let candidates: [URL?] = [
                bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "Plugins/stripchat"),
                bundle.url(forResource: "lp_plugin_stripchat_1.0.0_manifest", withExtension: "json", subdirectory: "Plugins/stripchat"),
                bundle.url(forResource: "lp_plugin_stripchat_1.0.1_manifest", withExtension: "json", subdirectory: "Plugins/stripchat"),
                bundle.url(forResource: "manifest", withExtension: "json"),
                bundle.resourceURL?.appendingPathComponent("Plugins/stripchat/manifest.json"),
                bundle.resourceURL?.appendingPathComponent("Plugins/stripchat/lp_plugin_stripchat_1.0.0_manifest.json")
            ]
            for url in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
                if let data = try? Data(contentsOf: url) { return data }
            }
        }
        return nil
    }
}
