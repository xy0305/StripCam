import AngelLiveCore
import Foundation

#if canImport(Translation)
import Translation
#endif

#if os(iOS) || os(macOS)

public enum LiveCaptionTranslationStatus: String, Sendable {
    case unknown
    case unsupportedOS
    case unsupported
    case needsDownload
    case installed

    public var title: String {
        switch self {
        case .unknown: "检测中"
        case .unsupportedOS: "需要 iOS 18 / macOS 15"
        case .unsupported: "此设备不支持"
        case .needsDownload: "需下载英语→简体中文语言包"
        case .installed: "已安装"
        }
    }
}

public enum LiveCaptionAppleTranslation {
    public static func status() async -> LiveCaptionTranslationStatus {
        #if canImport(Translation)
        if #available(iOS 18.0, macOS 15.0, *) {
            let s = await LanguageAvailability().status(
                from: Locale.Language(identifier: "en"),
                to: Locale.Language(identifier: "zh-Hans")
            )
            switch s {
            case .installed: return .installed
            case .supported: return .needsDownload
            case .unsupported: return .unsupported
            @unknown default: return .unknown
            }
        }
        #endif
        return .unsupportedOS
    }
}

#if canImport(Translation)
/// iOS 26+ / macOS 26+: UI-less session once packs are installed.
@available(iOS 26.0, macOS 26.0, *)
public final class LiveCaptionDirectTranslator: LiveCaptionTranslating, @unchecked Sendable {
    public let displayName = "Apple 翻译"
    private let session = TranslationSession(
        installedSource: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "zh-Hans")
    )

    public init() {}

    public func prepare() async throws {
        let st = await LiveCaptionAppleTranslation.status()
        guard st == .installed else {
            throw st == .needsDownload
                ? LiveCaptionEngineError.translationNeedsDownload
                : LiveCaptionEngineError.translationUnsupported
        }
    }

    public func translate(_ english: String) async throws -> String {
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return try await session.translate(trimmed).targetText
    }

    public func shutdown() {}
}

/// iOS 18–25: TranslationSession only lives inside SwiftUI `.translationTask`.
@available(iOS 18.0, macOS 15.0, *)
public final class LiveCaptionTranslationBridge: LiveCaptionTranslating, @unchecked Sendable {
    public let displayName = "Apple 翻译"

    public struct Request: Sendable {
        public let text: String
        public let reply: CheckedContinuation<String, Error>
    }

    private let lock = NSLock()
    private var continuation: AsyncStream<Request>.Continuation?
    private var stream: AsyncStream<Request>?

    @MainActor public private(set) var configuration: TranslationSession.Configuration?
    @MainActor public private(set) var attached = false

    public init() {
        makeStream()
    }

    private func makeStream() {
        lock.lock(); defer { lock.unlock() }
        let (s, c) = AsyncStream.makeStream(of: Request.self)
        stream = s
        continuation = c
    }

    @MainActor
    public func activate() {
        if configuration == nil {
            configuration = .init(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "zh-Hans")
            )
        } else {
            shutdown()
            configuration?.invalidate()
        }
    }

    /// Runs on the MainActor like SwiftUI's `.translationTask` closure, so the non-Sendable
    /// `TranslationSession` never crosses an isolation boundary.
    @MainActor
    public func serve(_ session: TranslationSession) async {
        try? await session.prepareTranslation()
        let s: AsyncStream<Request>? = {
            lock.lock(); defer { lock.unlock() }
            return stream
        }()
        guard let s else { return }
        attached = true
        for await req in s {
            do {
                let out = try await session.translate(req.text).targetText
                req.reply.resume(returning: out)
            } catch {
                req.reply.resume(throwing: error)
            }
        }
        attached = false
    }

    public func prepare() async throws {
        let st = await LiveCaptionAppleTranslation.status()
        if st == .needsDownload {
            // prepareTranslation inside serve() will prompt download when the host attaches.
            return
        }
        guard st == .installed || st == .needsDownload else {
            throw LiveCaptionEngineError.translationUnsupported
        }
    }

    public func translate(_ english: String) async throws -> String {
        let trimmed = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            lock.lock(); let c = continuation; lock.unlock()
            guard let c else {
                cont.resume(throwing: LiveCaptionEngineError.notReady)
                return
            }
            if case .terminated = c.yield(Request(text: trimmed, reply: cont)) {
                cont.resume(throwing: LiveCaptionEngineError.notReady)
            }
        }
    }

    public func shutdown() {
        lock.lock()
        continuation?.finish()
        continuation = nil
        lock.unlock()
        makeStream()
    }
}
#endif

#endif
