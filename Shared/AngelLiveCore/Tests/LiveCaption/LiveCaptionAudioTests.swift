import XCTest
@testable import AngelLiveCore

final class LiveCaptionAudioTests: XCTestCase {
    func testSilenceDetection() {
        let quiet = [Float](repeating: 0.0001, count: 1600)
        let loud = [Float](repeating: 0.2, count: 1600)
        XCTAssertTrue(LiveCaptionAudio.isSilent(quiet))
        XCTAssertFalse(LiveCaptionAudio.isSilent(loud))
    }

    func testPreferenceRoundTrip() {
        let key = LiveCaptionPreference.enabledKey
        let previous = UserDefaults.shared.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.shared.set(previous, forKey: key)
            } else {
                UserDefaults.shared.removeObject(forKey: key)
            }
        }
        let pref = LiveCaptionPreference()
        pref.isEnabled = true
        XCTAssertTrue(LiveCaptionPreference().isEnabled)
        pref.isEnabled = false
        XCTAssertFalse(LiveCaptionPreference().isEnabled)
    }
}
