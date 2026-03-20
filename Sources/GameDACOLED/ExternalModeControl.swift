import Foundation

enum ExternalModeControl {
    static let requestedModeDefaultsKey = "GameDACOLED.requestedMode"
    static let notificationName = Notification.Name("GameDACOLED.ExternalModeChanged")

    static func request(mode: AppModel.DisplayMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: requestedModeDefaultsKey)
        DistributedNotificationCenter.default().post(name: notificationName, object: nil)
    }

    static func consumeRequestedMode() -> AppModel.DisplayMode? {
        guard let rawValue = UserDefaults.standard.string(forKey: requestedModeDefaultsKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: requestedModeDefaultsKey)
        return AppModel.DisplayMode(rawValue: rawValue)
    }
}
