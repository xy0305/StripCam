//
//  CrashLogStore.swift
//  AngelLive
//
//  侧载包经常被系统 SIGKILL，设置里的「分析数据」不一定有记录。
//  启动面包屑和捕获到的异常/信号写进沙盒，下次打开就能导出。
//

import Darwin
import Foundation
import UIKit

enum CrashLogStore {
    private static let folderName = "CrashLogs"
    private static let breadcrumbFile = "launch-breadcrumbs.log"
    private static let crashFile = "last-crash.log"
    private static let signalFile = "signal-scratch.log"
    private static let bootStateFile = "boot-state.txt"

    private static let stateBooting = "booting"
    private static let stateReady = "ui_ready"
    private static let stateClean = "clean_exit"

    nonisolated(unsafe) private static var crashFD: Int32 = -1
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var pendingRecovery = false

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var documentsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var breadcrumbURL: URL { directoryURL.appendingPathComponent(breadcrumbFile) }
    static var crashURL: URL { directoryURL.appendingPathComponent(crashFile) }
    static var signalURL: URL { directoryURL.appendingPathComponent(signalFile) }
    static var bootStateURL: URL { directoryURL.appendingPathComponent(bootStateFile) }

    static var shouldShowRecovery: Bool { pendingRecovery }

    static func install() {
        guard !installed else { return }
        installed = true

        let previousState = (try? String(contentsOf: bootStateURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hadCrashFile = fileHasContent(crashURL) || fileHasContent(signalURL)
        pendingRecovery = hadCrashFile || previousState == stateBooting

        openSignalFileDescriptor()
        rotateBreadcrumbsIfNeeded()
        appendBreadcrumb("boot_start \(isoNow()) \(deviceSummary()) previous=\(previousState ?? "none") recovery=\(pendingRecovery)")
        writeBootState(stateBooting)
        publishToDocuments()

        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)

        signal(SIGABRT, crashSignalHandler)
        signal(SIGSEGV, crashSignalHandler)
        signal(SIGBUS, crashSignalHandler)
        signal(SIGILL, crashSignalHandler)
        signal(SIGTRAP, crashSignalHandler)
        signal(SIGFPE, crashSignalHandler)
        signal(SIGSYS, crashSignalHandler)

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            markCleanExit()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            appendBreadcrumb("did_enter_background \(isoNow())")
            publishToDocuments()
        }
    }

    static func markUIReady() {
        appendBreadcrumb("ui_ready \(isoNow())")
        writeBootState(stateReady)
        publishToDocuments()
    }

    static func markCleanExit() {
        appendBreadcrumb("clean_exit \(isoNow())")
        writeBootState(stateClean)
        publishToDocuments()
    }

    static func appendBreadcrumb(_ line: String) {
        let text = line.hasSuffix("\n") ? line : line + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: breadcrumbURL.path) {
            FileManager.default.createFile(atPath: breadcrumbURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: breadcrumbURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    static func exportText() -> String {
        var parts: [String] = []
        parts.append("=== StripCam crash export \(isoNow()) ===")
        parts.append(deviceSummary())
        parts.append("boot-state: \((try? String(contentsOf: bootStateURL, encoding: .utf8)) ?? "(none)")")
        parts.append("")
        parts.append("=== last-crash.log ===")
        parts.append((try? String(contentsOf: crashURL, encoding: .utf8)) ?? "(no crash file)")
        parts.append("")
        parts.append("=== signal-scratch.log ===")
        parts.append((try? String(contentsOf: signalURL, encoding: .utf8)) ?? "(empty)")
        parts.append("")
        parts.append("=== launch-breadcrumbs.log ===")
        parts.append((try? String(contentsOf: breadcrumbURL, encoding: .utf8)) ?? "(empty)")
        return parts.joined(separator: "\n")
    }

    static func clearCrashFile() {
        try? FileManager.default.removeItem(at: crashURL)
        try? FileManager.default.removeItem(at: signalURL)
        pendingRecovery = false
        openSignalFileDescriptor()
        publishToDocuments()
    }

    static func publishToDocuments() {
        let dest = documentsDirectoryURL
        let files = [breadcrumbURL, crashURL, signalURL, bootStateURL]
        for file in files where FileManager.default.fileExists(atPath: file.path) {
            let target = dest.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: file, to: target)
        }
        let export = dest.appendingPathComponent("crash-export.txt")
        try? exportText().data(using: .utf8)?.write(to: export, options: .atomic)
    }

    // MARK: - Private

    private static func fileHasContent(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }

    private static func deviceSummary() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let id = info?["CFBundleIdentifier"] as? String ?? "?"
        return "bundle=\(id) version=\(version)(\(build)) ios=\(UIDevice.current.systemVersion) model=\(UIDevice.current.model) idiom=\(UIDevice.current.userInterfaceIdiom.rawValue)"
    }

    private static func rotateBreadcrumbsIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: breadcrumbURL.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > 256 * 1024 else { return }
        let backup = directoryURL.appendingPathComponent("launch-breadcrumbs.prev.log")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: breadcrumbURL, to: backup)
    }

    private static func writeBootState(_ value: String) {
        try? value.data(using: .utf8)?.write(to: bootStateURL, options: .atomic)
    }

    private static func openSignalFileDescriptor() {
        if crashFD >= 0 {
            Darwin.close(crashFD)
            crashFD = -1
        }
        crashFD = open(signalURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }

    fileprivate static func writeCrashText(_ text: String) {
        let payload = text.hasSuffix("\n") ? text : text + "\n"
        try? payload.data(using: .utf8)?.write(to: crashURL, options: .atomic)
        appendBreadcrumb("crash_written \(isoNow())")
        publishToDocuments()
    }

    fileprivate static func writeCrashSignal(_ sig: Int32) {
        guard crashFD >= 0 else { return }
        var buf: [Int8] = [83, 73, 71, 32, 48, 48, 48, 10]
        let value = abs(Int(sig))
        buf[4] = 48 + Int8((value / 100) % 10)
        buf[5] = 48 + Int8((value / 10) % 10)
        buf[6] = 48 + Int8(value % 10)
        _ = buf.withUnsafeBufferPointer { pointer in
            Darwin.write(crashFD, pointer.baseAddress, 8)
        }
        _ = Darwin.fsync(crashFD)
    }
}

private func isoNow() -> String {
    ISO8601DateFormatter().string(from: Date())
}

private func crashSignalHandler(_ sig: Int32) {
    CrashLogStore.writeCrashSignal(sig)
    signal(sig, SIG_DFL)
    raise(sig)
}

private func uncaughtExceptionHandler(_ exception: NSException) {
    let stack = exception.callStackSymbols.joined(separator: "\n")
    let text = """
    NSException \(isoNow())
    name: \(exception.name.rawValue)
    reason: \(exception.reason ?? "nil")
    userInfo: \(String(describing: exception.userInfo))
    stack:
    \(stack)
    """
    CrashLogStore.writeCrashText(text)
}
