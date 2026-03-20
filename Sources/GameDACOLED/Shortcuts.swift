import AppIntents

protocol FixedModeIntent: AppIntent {
    static var targetMode: AppModel.DisplayMode { get }
    static var openAppWhenRun: Bool { get }
}

extension FixedModeIntent {
    func perform() async throws -> some IntentResult {
        ExternalModeControl.request(mode: Self.targetMode)
        return .result()
    }
}

struct TurnOLEDOffIntent: FixedModeIntent {
    static let title: LocalizedStringResource = "Turn OLED Off"
    static let description = IntentDescription("Turn the GameDAC OLED off and stop sending frames.")
    static let openAppWhenRun: Bool = false
    static let targetMode: AppModel.DisplayMode = .off
}

struct ShowClockIntent: FixedModeIntent {
    static let title: LocalizedStringResource = "Show Clock"
    static let description = IntentDescription("Switch the GameDAC OLED to clock mode.")
    static let openAppWhenRun: Bool = false
    static let targetMode: AppModel.DisplayMode = .clock
}

struct ShowSystemIntent: FixedModeIntent {
    static let title: LocalizedStringResource = "Show System"
    static let description = IntentDescription("Switch the GameDAC OLED to system mode.")
    static let openAppWhenRun: Bool = false
    static let targetMode: AppModel.DisplayMode = .system
}

struct ShowVisualizerIntent: FixedModeIntent {
    static let title: LocalizedStringResource = "Show Visualizer"
    static let description = IntentDescription("Switch the GameDAC OLED to visualizer mode.")
    static let openAppWhenRun: Bool = false
    static let targetMode: AppModel.DisplayMode = .visualizer
}

struct ShowMediaIntent: FixedModeIntent {
    static let title: LocalizedStringResource = "Show Media"
    static let description = IntentDescription("Switch the GameDAC OLED to media mode.")
    static let openAppWhenRun: Bool = false
    static let targetMode: AppModel.DisplayMode = .media
}

struct GameDACShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: TurnOLEDOffIntent(),
                phrases: [
                    "Turn OLED off in \(.applicationName)",
                    "Turn off the OLED in \(.applicationName)"
                ],
                shortTitle: "OLED Off",
                systemImageName: "power"
            ),
            AppShortcut(
                intent: ShowClockIntent(),
                phrases: [
                    "Show clock on OLED in \(.applicationName)",
                    "Switch OLED to clock in \(.applicationName)"
                ],
                shortTitle: "Show Clock",
                systemImageName: "clock"
            ),
            AppShortcut(
                intent: ShowSystemIntent(),
                phrases: [
                    "Show system on OLED in \(.applicationName)",
                    "Switch OLED to system in \(.applicationName)"
                ],
                shortTitle: "Show System",
                systemImageName: "cpu"
            ),
            AppShortcut(
                intent: ShowVisualizerIntent(),
                phrases: [
                    "Show visualizer on OLED in \(.applicationName)",
                    "Switch OLED to visualizer in \(.applicationName)"
                ],
                shortTitle: "Show Visualizer",
                systemImageName: "waveform"
            ),
            AppShortcut(
                intent: ShowMediaIntent(),
                phrases: [
                    "Show media on OLED in \(.applicationName)",
                    "Switch OLED to media in \(.applicationName)"
                ],
                shortTitle: "Show Media",
                systemImageName: "photo.on.rectangle"
            )
        ]
    }
}
