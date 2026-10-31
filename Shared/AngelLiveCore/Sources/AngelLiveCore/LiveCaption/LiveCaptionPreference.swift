import Foundation
import Observation

/// Persisted FullUI preference for English→Chinese live captions.
@Observable
public final class LiveCaptionPreference {
    public static let enabledKey = "AngelLive.Setting.liveCaptionENZH"

    public init() {}

    @ObservationIgnored
    public var isEnabled: Bool {
        get {
            access(keyPath: \.isEnabled)
            return UserDefaults.shared.value(forKey: Self.enabledKey, synchronize: true) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.isEnabled) {
                UserDefaults.shared.set(newValue, forKey: Self.enabledKey, synchronize: true)
            }
        }
    }
}
