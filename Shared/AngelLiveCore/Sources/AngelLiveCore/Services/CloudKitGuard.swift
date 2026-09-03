//
//  CloudKitGuard.swift
//  AngelLiveCore
//
//  侧载工具常把 com.apple.developer.icloud-services 签成 "*"。
//  iOS 26/27 上 CKContainer 初始化会立刻抛 CKException 并杀掉进程。
//  没有合法 CloudKit entitlement 时，所有云同步都走本地。
//  Swift 接不住 CKException，真正创建容器必须走 ObjC @try/@catch。
//

import AngelLiveCoreCKSafe
import CloudKit
import Darwin
import Foundation

nonisolated public enum CloudKitGuard {
    public static let isUsable: Bool = evaluate()

    public static func makeContainer(identifier: String) -> CKContainer? {
        guard isUsable else { return nil }
        return ALCKContainerCreate(identifier)
    }

    public static func makeDefaultContainer() -> CKContainer? {
        guard isUsable else { return nil }
        return ALCKContainerDefault()
    }

    public static func requireContainer(identifier: String) throws -> CKContainer {
        guard let container = makeContainer(identifier: identifier) else {
            throw unavailableError
        }
        return container
    }

    public static var unavailableError: SyncError {
        SyncError(
            code: -8,
            kind: .permission,
            title: "iCloud 不可用",
            advice: "当前安装没有有效的 iCloud 权限。侧载时请不要勾选 iCloud。收藏仍保存在本地。",
            rawDescription: "missing or malformed com.apple.developer.icloud-services"
        )
    }

    private static func evaluate() -> Bool {
        let services = copyEntitlement("com.apple.developer.icloud-services")
        if !isStringArray(services) || !array(services).contains("CloudKit") {
            NSLog("[CloudKitGuard] disabled: icloud-services=%@", describe(services))
            return false
        }

        let containers = copyEntitlement("com.apple.developer.icloud-container-identifiers")
        if let containers, !isStringArray(containers) {
            NSLog("[CloudKitGuard] disabled: icloud-container-identifiers=%@", describe(containers))
            return false
        }

        NSLog("[CloudKitGuard] entitlements look valid")
        return true
    }

    private static func isStringArray(_ value: Any?) -> Bool {
        guard let value else { return false }
        if value is String { return false }
        guard let items = value as? [Any] else { return false }
        let strings = items.compactMap { $0 as? String }
        return strings.count == items.count && !strings.isEmpty
    }

    private static func array(_ value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func describe(_ value: Any?) -> String {
        switch value {
        case nil: return "nil"
        case let s as String: return "string(\(s))"
        case let arr as [Any]: return "array(\(arr))"
        default: return String(describing: type(of: value!))
        }
    }

    private static func copyEntitlement(_ name: String) -> Any? {
        typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
        typealias CopyFn = @convention(c) (
            AnyObject,
            CFString,
            UnsafeMutablePointer<Unmanaged<CFError>?>?
        ) -> Unmanaged<AnyObject>?

        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let createSym = dlsym(defaultHandle, "SecTaskCreateFromSelf"),
              let copySym = dlsym(defaultHandle, "SecTaskCopyValueForEntitlement") else {
            return nil
        }

        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let copy = unsafeBitCast(copySym, to: CopyFn.self)
        guard let task = create(nil)?.takeRetainedValue() else { return nil }
        var error: Unmanaged<CFError>?
        return copy(task, name as CFString, &error)?.takeRetainedValue()
    }
}
