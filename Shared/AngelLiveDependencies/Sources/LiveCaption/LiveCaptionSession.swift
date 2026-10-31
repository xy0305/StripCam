import AngelLiveCore
import Foundation
import Observation

/// Owns the audio reader + EN ASR + Apple MT pipeline for one playback URL.
@MainActor
@Observable
public final class LiveCaptionSession {
    public private(set) var phase: LiveCaptionPhase = .idle
    public private(set) var latest: LiveCaptionLine?
    public private(set) var statusMessage: String = ""
    public private(set) var lastError: String?

    /// Soft lead for the secondary demux so it does not race too far ahead of live.
    public var maxLeadSeconds: TimeInterval = 4

    @ObservationIgnored private let reader = LiveCaptionAudioReader()
    @ObservationIgnored private var recognizer: (any LiveCaptionRecognizing)?
    @ObservationIgnored private var translator: (any LiveCaptionTranslating)?
    @ObservationIgnored private var processTask: Task<Void, Never>?
    @ObservationIgnored private var pcmContinuation: AsyncStream<(samples: [Float], time: Double, generation: Int)>.Continuation?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var buffered: [Float] = []
    @ObservationIgnored private var bufferStart: Double = 0

    /// Cross-isolation pacing state read by the FFmpeg reader thread.
    @ObservationIgnored private let pace = PaceClock()

    /// iOS 18–25 Translation bridge exposed for the SwiftUI `.translationTask` host.
    public private(set) var translationBridge: AnyObject?

    public init() {}

    public var isActive: Bool {
        phase == .running || phase == .starting
    }

    public func start(source: LiveCaptionSource) async {
        if isActive {
            await stop(clearText: false)
        }
        phase = .starting
        lastError = nil
        statusMessage = "正在启动实时翻译…"
        generation &+= 1
        let gen = generation
        buffered.removeAll(keepingCapacity: true)
        latest = nil
        pace.reset(maxLead: maxLeadSeconds)

        do {
            #if os(iOS) || os(macOS)
            let recognizer = try await LiveCaptionEnglishRecognizer.make()
            try await recognizer.prepare()
            self.recognizer = recognizer

            let translator: any LiveCaptionTranslating
            if #available(iOS 26.0, macOS 26.0, *) {
                #if canImport(Translation)
                let direct = LiveCaptionDirectTranslator()
                try await direct.prepare()
                translator = direct
                translationBridge = nil
                #else
                throw LiveCaptionEngineError.translationUnsupported
                #endif
            } else if #available(iOS 18.0, macOS 15.0, *) {
                #if canImport(Translation)
                let bridge = LiveCaptionTranslationBridge()
                try await bridge.prepare()
                bridge.activate()
                translator = bridge
                translationBridge = bridge
                #else
                throw LiveCaptionEngineError.translationUnsupported
                #endif
            } else {
                throw LiveCaptionEngineError.unavailable("实时翻译需要 iOS 18 或更新系统")
            }
            self.translator = translator
            #else
            throw LiveCaptionEngineError.unavailable("当前平台不支持实时翻译")
            #endif

            let (stream, cont) = AsyncStream.makeStream(
                of: (samples: [Float], time: Double, generation: Int).self
            )
            pcmContinuation = cont
            let pace = self.pace
            reader.onPCM = { samples, time, g in
                pace.noteMedia(time + Double(samples.count) / LiveCaptionAudio.sampleRate)
                cont.yield((samples, time, g))
            }
            reader.onError = { [weak self] message in
                Task { @MainActor in
                    self?.lastError = message
                    self?.statusMessage = message
                }
            }
            reader.shouldRun = {
                pace.shouldRun()
            }

            var headers = source.headers
            if headers["User-Agent"] == nil && headers["user-agent"] == nil {
                headers["User-Agent"] = source.userAgent
            }
            reader.start(.init(url: source.url, headers: headers), generation: gen)
            processTask = Task { [weak self] in
                await self?.consume(stream, generation: gen)
            }
            phase = .running
            statusMessage = "实时翻译运行中"
        } catch {
            phase = .failed
            lastError = error.localizedDescription
            statusMessage = error.localizedDescription
            await tearDownWorkers()
        }
    }

    /// UI-first stop: caller should clear overlay text immediately, then await this.
    public func stop(clearText: Bool = true) async {
        phase = .stopping
        statusMessage = ""
        if clearText { latest = nil }
        await tearDownWorkers()
        phase = .idle
    }

    public func holdForBandwidth(_ on: Bool) {
        reader.holdForBandwidth(on)
        pace.setHold(on)
    }

    public func retarget(source: LiveCaptionSource) async {
        guard isActive || phase == .failed else { return }
        await start(source: source)
    }

    private func tearDownWorkers() async {
        processTask?.cancel()
        processTask = nil
        pcmContinuation?.finish()
        pcmContinuation = nil
        reader.stop()
        translator?.shutdown()
        translator = nil
        recognizer = nil
        translationBridge = nil
        buffered.removeAll(keepingCapacity: false)
    }

    private func consume(
        _ stream: AsyncStream<(samples: [Float], time: Double, generation: Int)>,
        generation: Int
    ) async {
        for await packet in stream {
            if Task.isCancelled { break }
            guard packet.generation == generation else { continue }
            if buffered.isEmpty { bufferStart = packet.time }
            buffered.append(contentsOf: packet.samples)
            while buffered.count >= LiveCaptionAudio.chunkSamples {
                let chunk = Array(buffered.prefix(LiveCaptionAudio.chunkSamples))
                buffered.removeFirst(LiveCaptionAudio.chunkSamples)
                let start = bufferStart
                bufferStart += Double(LiveCaptionAudio.chunkSamples) / LiveCaptionAudio.sampleRate
                await processChunk(chunk, mediaTime: start, generation: generation)
            }
        }
    }

    private func processChunk(_ samples: [Float], mediaTime: Double, generation: Int) async {
        guard generation == self.generation, let recognizer, let translator else { return }
        if LiveCaptionAudio.isSilent(samples) { return }
        do {
            let english = try await recognizer.transcribe(samples: samples)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, generation == self.generation else { return }
            let chinese = try await translator.translate(english)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chinese.isEmpty, generation == self.generation else { return }
            latest = LiveCaptionLine(english: english, chinese: chinese, mediaTime: mediaTime)
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Lock-protected pacing so the FFmpeg reader thread never hops to the MainActor.
private final class PaceClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wallAnchor = Date()
    private var mediaAnchor: Double = 0
    private var lastMedia: Double = 0
    private var maxLead: TimeInterval = 4
    private var hold = false
    private var started = false

    func reset(maxLead: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        self.maxLead = maxLead
        wallAnchor = Date()
        mediaAnchor = 0
        lastMedia = 0
        hold = false
        started = false
    }

    func setHold(_ on: Bool) {
        lock.lock(); hold = on; lock.unlock()
    }

    func noteMedia(_ t: Double) {
        lock.lock(); defer { lock.unlock() }
        if !started {
            started = true
            mediaAnchor = t
            wallAnchor = Date()
        }
        lastMedia = t
    }

    func shouldRun() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if hold { return false }
        guard started else { return true }
        let wall = Date().timeIntervalSince(wallAnchor)
        let media = max(0, lastMedia - mediaAnchor)
        return (media - wall) < maxLead
    }
}
