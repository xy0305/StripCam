//
//  UserDefaults+Extension.swift
//  AngelLiveCore
//
//  Created by pangchong
//

import Foundation

public extension UserDefaults {
    /// StripCam 是单 App 侧载分发，没有配置 App Group。
    /// 原版 AngelLive 用 `group.dev.idog.angellivetvos` 和 tvOS 共享设置；
    /// 在没有对应 entitlement 时 `UserDefaults(suiteName:)!` 会在启动瞬间崩溃。
    nonisolated(unsafe) static let shared = UserDefaults.standard

    func synchronized() -> UserDefaults {
        return .standard
    }

    func set(_ value: (some Sendable)?, forKey key: String, synchronize: Bool) {
        self.set(value, forKey: key)
        if synchronize {
            self.synchronize()
        }
    }

    func value(forKey key: String, synchronize: Bool) -> Any? {
        return self.value(forKey: key)
    }
}
