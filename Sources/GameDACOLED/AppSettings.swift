import Foundation

struct AppSettings {
    var modeRawValue: String = AppModel.DisplayMode.clock.rawValue
    var showsDate = true
    var statsUpdateInterval: Double = 2
    var usesUnixCPUPercent = false
    var hidesMetricPercentSymbols = false
    var visualizerHidesMetricPercentSymbols = false
    var visualizerSourceRawValue = AppModel.VisualizerSource.systemAudio.rawValue
    var visualizerGain: Double = 0.05
    var selectedMicrophoneID: String?
    var visualizerAirPlayDelay = false
    var visualizerShowsMetrics = false
    var mediaDitheringEnabled = true
    var mediaContrast: Double = 1
    var mediaZoom: Double = 1
    var mediaInverted = false
    var selectedMediaPath: String?
    var selectedImagePath: String?
    var selectedGIFPath: String?
}

@MainActor
enum AppSettingsStore {
    private static let key = "GameDACOLED.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return AppSettings()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        UserDefaults.standard.set(data, forKey: key)
    }
}

extension AppSettings: Codable {}
