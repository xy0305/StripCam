import XCTest
@testable import AngelLiveCore

final class LiveCaptionHLSTests: XCTestCase {
    /// Trimmed Chaturbate / MMCDN LL-HLS master captured 2026-10-31.
    private let chaturbateMaster = """
    #EXTM3U
    #EXT-X-VERSION:6
    #EXT-X-INDEPENDENT-SEGMENTS
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio_45763_0",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="/v1/edge/streams/origin.room.X/chunklist_0_audio_1_llhls.m3u8?session=abc"


    #EXT-X-STREAM-INF:BANDWIDTH=546000,RESOLUTION=428x240,FRAME-RATE=30.000,CODECS="avc1.42c015,mp4a.40.2",AUDIO="audio_aac_96"
    /v1/edge/streams/origin.room.X/chunklist_1_video_1_llhls.m3u8?session=abc
    #EXT-X-STREAM-INF:BANDWIDTH=1696000,RESOLUTION=960x540,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
    /v1/edge/streams/origin.room.X/chunklist_4_video_1_llhls.m3u8?session=abc
    """

    func testChaturbatePicksAudioRendition() throws {
        let base = URL(string: "https://edge26-sin.live.mmcdn.com/v1/edge/streams/origin.room.X/llhls.m3u8?token=t")!
        guard case .master(let url) = LiveCaptionHLS.classify(chaturbateMaster, baseURL: base) else {
            return XCTFail("expected master")
        }
        XCTAssertEqual(url.absoluteString, "https://edge26-sin.live.mmcdn.com/v1/edge/streams/origin.room.X/chunklist_0_audio_1_llhls.m3u8?session=abc")
    }

    func testMuxedMasterPicksLowestVariant() {
        let text = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        hi/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=320x180
        lo/index.m3u8
        """
        let base = URL(string: "https://cdn.example.com/live/master.m3u8")!
        XCTAssertEqual(LiveCaptionHLS.classify(text, baseURL: base), .master(audioURL: URL(string: "https://cdn.example.com/live/lo/index.m3u8")!))
    }

    func testSessionDuplicatedIsInvalid() {
        let base = URL(string: "https://edge.example.com/llhls.m3u8")!
        guard case .invalid = LiveCaptionHLS.classify("w3: session_duplicated", baseURL: base) else {
            return XCTFail("expected invalid")
        }
    }

    func testMediaPlaylist() {
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:1.6,\nseg.m4s\n"
        XCTAssertEqual(LiveCaptionHLS.classify(text, baseURL: URL(string: "https://a/b.m3u8")!), .media)
    }

    func testChaturbateRequiresFreshPlaylist() {
        XCTAssertTrue(LiveCaptionHLS.requiresFreshPlaylist(liveType: "chaturbate"))
        XCTAssertFalse(LiveCaptionHLS.requiresFreshPlaylist(liveType: "bilibili"))
    }

    func testStreamIdentityDropsToken() {
        let a = URL(string: "https://e/v1/origin.r.X/llhls.m3u8?token=1")!
        let b = URL(string: "https://e/v1/origin.r.X/llhls.m3u8?token=2")!
        XCTAssertEqual(LiveCaptionHLS.streamIdentity(a), LiveCaptionHLS.streamIdentity(b))
    }
}
