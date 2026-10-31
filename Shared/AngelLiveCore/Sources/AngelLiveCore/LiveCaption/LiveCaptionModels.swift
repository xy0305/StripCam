import Foundation

/// One finished English→Chinese live caption line.
public struct LiveCaptionLine: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let english: String
    public let chinese: String
    /// Approximate media time (seconds) of the audio chunk start, when known.
    public let mediaTime: TimeInterval
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        english: String,
        chinese: String,
        mediaTime: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.mediaTime = mediaTime
        self.createdAt = createdAt
    }
}

public enum LiveCaptionPhase: String, Sendable, Equatable {
    case idle
    case requestingPermission
    case starting
    case running
    case stopping
    case unavailable
    case failed
}

public struct LiveCaptionSource: Sendable, Equatable {
    public var url: URL
    public var headers: [String: String]
    public var userAgent: String

    public init(url: URL, headers: [String: String] = [:], userAgent: String = "libmpv") {
        self.url = url
        self.headers = headers
        self.userAgent = userAgent
    }
}

/// Shared EN→ZH live-caption contracts. Implementations live in AngelLiveDependencies (Speech / Translation / FFmpeg).
public protocol LiveCaptionRecognizing: Sendable {
    func prepare() async throws
    func transcribe(samples: [Float]) async throws -> String
}

public protocol LiveCaptionTranslating: Sendable {
    var displayName: String { get }
    func prepare() async throws
    func translate(_ english: String) async throws -> String
    func shutdown()
}

/// PCM helpers used by the live caption pipeline (16 kHz mono Float32).
public enum LiveCaptionAudio {
    public static let sampleRate: Double = 16_000
    /// ~2.4 s windows keep Apple on-device ASR snappy without starving the player.
    public static let chunkSamples = 38_400
    public static let silenceRMSThreshold: Float = 0.008

    public static func isSilent(_ samples: ArraySlice<Float>, threshold: Float = silenceRMSThreshold) -> Bool {
        guard !samples.isEmpty else { return true }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return sqrt(sum / Float(samples.count)) < threshold
    }

    public static func isSilent(_ samples: [Float], threshold: Float = silenceRMSThreshold) -> Bool {
        isSilent(samples[...], threshold: threshold)
    }
}
