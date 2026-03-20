import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum VisualizerSource: String, CaseIterable, Identifiable {
        case systemAudio = "System Audio"
        case microphone = "Microphone"

        var id: String { rawValue }
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case off = "Off"
        case clock = "Clock"
        case system = "System"
        case visualizer = "Visualizer"
        case media = "Media"

        var id: String { rawValue }
    }

    @Published var mode: DisplayMode = .clock {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            Task { await applyCurrentMode() }
        }
    }
    @Published var statusMessage = "Looking for SteelSeries GameSense..."
    @Published var endpointDescription = "Not connected"
    @Published var selectedMediaURL: URL?
    @Published var previewImage: NSImage?
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var recentMessages: [String] = []
    @Published var showsDate = true {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            Task { await applyCurrentMode() }
        }
    }
    @Published var statsUpdateInterval: Double = 2 {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .system else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var usesUnixCPUPercent = false {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .system else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var hidesMetricPercentSymbols = false {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .system else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var visualizerSource: VisualizerSource = .systemAudio {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .visualizer else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var visualizerGain: Double = 0.05 {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .visualizer else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var visualizerHidesMetricPercentSymbols = false {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
        }
    }
    @Published var availableMicrophones: [MicrophoneOption] = []
    @Published var selectedMicrophoneID: String? {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .visualizer, visualizerSource == .microphone else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var visualizerAirPlayDelay = false {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
        }
    }
    @Published var visualizerShowsMetrics = false {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
        }
    }
    @Published var mediaDitheringEnabled = true {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .media else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var mediaContrast: Double = 1 {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .media else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var mediaZoom: Double = 1 {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .media else { return }
            Task { await applyCurrentMode() }
        }
    }
    @Published var mediaInverted = false {
        didSet {
            guard !isRestoringSettings else { return }
            persistSettings()
            guard mode == .media else { return }
            Task { await applyCurrentMode() }
        }
    }

    let supportedScreenDescription = "SteelSeries screened-128x52 (GameDAC / Arctis Pro + GameDAC)"

    private let gameSenseClient = GameSenseClient()
    private let systemStatsMonitor = SystemStatsMonitor()
    private let audioVisualizerCapture = AudioVisualizerCapture()
    private var modeTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var gifFrames: [GIFFrame] = []
    private var frameSequence = 0
    private var latestAudioLevels = Array(repeating: Float(0), count: 12)
    private var latestSystemSnapshot: SystemSnapshot?
    private var lastVisualizerMetricsUpdate: Date?
    private var delayedVisualizerFrames: [DelayedVisualizerFrame] = []
    private var isRestoringSettings = false

    init() {
        restoreSettings()
        refreshMicrophones()
        installExternalModeObserver()
        applyPendingExternalModeRequestIfNeeded()
        audioVisualizerCapture.onLevels = { [weak self] levels in
            Task { @MainActor in
                self?.latestAudioLevels = levels
            }
        }

        Task {
            await initialize()
        }
    }

    func initialize() async {
        isBusy = true
        do {
            let endpoint = try await gameSenseClient.initialize()
            endpointDescription = endpoint.absoluteString
            statusMessage = "Connected to SteelSeries GameSense"
            lastError = nil
            appendLog("Initialized GameSense at \(endpoint.absoluteString)")
            await applyCurrentMode()
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Unable to initialize GameSense"
            endpointDescription = "Install/open SteelSeries GG or Engine and enable GameSense"
            appendLog("Initialization failed: \(error.localizedDescription)")
        }
        isBusy = false
    }

    func reconnect() async {
        stopTasks()
        await initialize()
    }

    func clearDisplay() async {
        stopTasks()
        do {
            try await sendBitmap(ImageRenderer.blankBitmap())
            statusMessage = "Sent a blank frame"
            previewImage = ImageRenderer.previewImage(from: ImageRenderer.blankCGImage())
            lastError = nil
            appendLog("Sent blank OLED frame")
        } catch {
            present(error)
        }
    }

    func chooseStaticImage() {
        chooseMedia()
    }

    func chooseGIF() {
        chooseMedia()
    }

    func chooseMedia() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            selectedMediaURL = url
            persistSettings()
            mode = .media
            Task {
                await loadMedia(from: url)
            }
        }
    }

    func resendCurrentFrame() async {
        await applyCurrentMode()
    }

    func activate(mode newMode: DisplayMode) async {
        mode = newMode
    }

    private func applyCurrentMode() async {
        stopTasks()

        switch mode {
        case .off:
            await turnOff()
        case .clock:
            startHeartbeatLoop()
            startClockLoop()
        case .system:
            startHeartbeatLoop()
            startSystemLoop()
        case .visualizer:
            startHeartbeatLoop()
            await startVisualizerLoop()
        case .media:
            startHeartbeatLoop()
            if let selectedMediaURL {
                await loadMedia(from: selectedMediaURL)
            } else {
                statusMessage = "Choose an image or GIF to send to the GameDAC"
            }
        }
    }

    private func startClockLoop() {
        modeTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.sendClockFrame()

                do {
                    try await Task.sleep(for: .seconds(self.secondsUntilNextMinuteBoundary()))
                } catch {
                    break
                }
            }
        }
    }

    private func sendClockFrame() async {
        let cgImage = ImageRenderer.clockImage(date: Date(), showsDate: showsDate)
        previewImage = ImageRenderer.previewImage(from: cgImage)

        do {
            try await sendBitmap(ImageRenderer.packBitmap(from: cgImage))
            statusMessage = "Streaming the current time"
            lastError = nil
            appendLog("Sent clock frame")
        } catch {
            present(error)
        }
    }

    private func startSystemLoop() {
        modeTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                await self.sendSystemFrame()

                do {
                    try await Task.sleep(for: .seconds(self.statsUpdateInterval))
                } catch {
                    break
                }
            }
        }
    }

    private func startVisualizerLoop() async {
        do {
            latestAudioLevels = Array(repeating: 0, count: 12)
            delayedVisualizerFrames.removeAll()
            lastVisualizerMetricsUpdate = nil
            try await audioVisualizerCapture.start(source: visualizerCaptureSource(), gain: Float(visualizerGain))
            statusMessage = "Streaming audio visualizer"
            lastError = nil
            appendLog("Started \(visualizerSource == .systemAudio ? "system audio" : "microphone") visualizer")

            modeTask = Task { [weak self] in
                guard let self else { return }

                while !Task.isCancelled {
                    await self.sendVisualizerFrame()

                    do {
                        try await Task.sleep(for: .milliseconds(33))
                    } catch {
                        break
                    }
                }
            }
        } catch {
            present(error)
        }
    }

    private func sendSystemFrame() async {
        do {
            let snapshot = try systemStatsMonitor.snapshot(usesUnixCPUPercent: usesUnixCPUPercent)
            let cgImage = ImageRenderer.systemStatsImage(
                snapshot: snapshot,
                showsDate: showsDate,
                usesUnixCPUPercent: usesUnixCPUPercent,
                hidesMetricPercentSymbols: hidesMetricPercentSymbols
            )
            previewImage = ImageRenderer.previewImage(from: cgImage)
            try await sendBitmap(ImageRenderer.packBitmap(from: cgImage))
            statusMessage = "Streaming system stats"
            lastError = nil
            appendLog(
                "Sent system stats frame CPU \(snapshot.cpuPercent)\(usesUnixCPUPercent ? " unix" : "%") GPU \(snapshot.gpuPercent.map(String.init) ?? "--") RAM \(snapshot.ramPercent)\(hidesMetricPercentSymbols ? "" : "%")"
            )
        } catch {
            present(error)
        }
    }

    private func sendVisualizerFrame() async {
        if visualizerShowsMetrics {
            let shouldRefreshMetrics: Bool
            if let lastVisualizerMetricsUpdate {
                shouldRefreshMetrics = Date().timeIntervalSince(lastVisualizerMetricsUpdate) >= statsUpdateInterval
            } else {
                shouldRefreshMetrics = true
            }

            if shouldRefreshMetrics {
                latestSystemSnapshot = try? systemStatsMonitor.snapshot(usesUnixCPUPercent: usesUnixCPUPercent)
                lastVisualizerMetricsUpdate = Date()
            }
        }

        let cgImage = ImageRenderer.audioVisualizerImage(
            levels: latestAudioLevels,
            metrics: visualizerShowsMetrics ? latestSystemSnapshot : nil,
            hidesPercentSymbols: visualizerHidesMetricPercentSymbols,
            usesUnixCPUPercent: usesUnixCPUPercent
        )
        previewImage = ImageRenderer.previewImage(from: cgImage)
        let bitmap = ImageRenderer.packBitmap(from: cgImage)

        do {
            if visualizerAirPlayDelay {
                delayedVisualizerFrames.append(
                    DelayedVisualizerFrame(
                        bitmap: bitmap,
                        deliverAt: Date().addingTimeInterval(2)
                    )
                )

                if let readyFrame = delayedVisualizerFrames.first, readyFrame.deliverAt <= Date() {
                    delayedVisualizerFrames.removeFirst()
                    try await sendBitmap(readyFrame.bitmap)
                }
            } else {
                delayedVisualizerFrames.removeAll()
                try await sendBitmap(bitmap)
            }
            statusMessage = "Streaming audio visualizer"
            lastError = nil
        } catch {
            present(error)
        }
    }

    private func turnOff() async {
        do {
            previewImage = ImageRenderer.previewImage(from: ImageRenderer.blankCGImage())
            try await sendBitmap(ImageRenderer.blankBitmap())
            statusMessage = "OLED is off"
            lastError = nil
            appendLog("Turned OLED off")
        } catch {
            present(error)
        }
    }

    private func loadMedia(from url: URL) async {
        if isGIF(url) {
            await startGIFLoop(from: url)
        } else {
            await loadStaticImage(from: url)
        }
    }

    private func loadStaticImage(from url: URL) async {
        do {
            let cgImage = try ImageRenderer.loadFirstFrame(from: url)
            let rendered = try ImageRenderer.renderToScreen(
                cgImage,
                contrast: mediaContrast,
                zoom: mediaZoom,
                inverted: mediaInverted
            )
            previewImage = ImageRenderer.previewImage(from: rendered)
            try await sendBitmap(
                ImageRenderer.packBitmap(fromRendered: rendered, ditheringEnabled: mediaDitheringEnabled)
            )
            statusMessage = "Sent static image"
            lastError = nil
            appendLog("Sent static image frame from \(url.lastPathComponent)")
        } catch {
            present(error)
        }
    }

    private func startGIFLoop(from url: URL) async {
        do {
            gifFrames = try GIFLoader.loadFrames(from: url)

            guard !gifFrames.isEmpty else {
                throw AppError("The selected GIF did not contain any frames.")
            }

            previewImage = ImageRenderer.previewImage(from: gifFrames[0].image)
            lastError = nil

            modeTask = Task { [weak self] in
                guard let self else { return }
                var index = 0

                while !Task.isCancelled && !self.gifFrames.isEmpty {
                    let frame = self.gifFrames[index]
                    let rendered: CGImage
                    do {
                        rendered = try ImageRenderer.renderToScreen(
                            frame.image,
                            contrast: self.mediaContrast,
                            zoom: self.mediaZoom,
                            inverted: self.mediaInverted
                        )
                    } catch {
                        self.present(error)
                        break
                    }
                    self.previewImage = ImageRenderer.previewImage(from: rendered)

                    do {
                        try await self.sendBitmap(
                            ImageRenderer.packBitmap(fromRendered: rendered, ditheringEnabled: self.mediaDitheringEnabled)
                        )
                        self.statusMessage = "Animating GIF on the OLED"
                        self.lastError = nil
                        self.appendLog("Sent GIF frame \(index + 1)/\(self.gifFrames.count)")
                    } catch {
                        self.present(error)
                        break
                    }

                    index = (index + 1) % self.gifFrames.count

                    do {
                        try await Task.sleep(for: .seconds(max(frame.duration, 0.04)))
                    } catch {
                        break
                    }
                }
            }
        } catch {
            present(error)
        }
    }

    private func stopTasks() {
        modeTask?.cancel()
        modeTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        Task {
            await audioVisualizerCapture.stop()
        }
    }

    private func present(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = "Failed to update the OLED"
        appendLog("Error: \(error.localizedDescription)")
    }

    private func startHeartbeatLoop() {
        heartbeatTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    break
                }

                do {
                    try await self.gameSenseClient.heartbeat()
                    self.appendLog("Sent heartbeat")
                } catch {
                    self.present(error)
                }
            }
        }
    }

    private func sendBitmap(_ bitmap: [UInt8]) async throws {
        frameSequence = (frameSequence + 1) % 100
        try await gameSenseClient.send(bitmap: bitmap, value: frameSequence)
    }

    private func secondsUntilNextMinuteBoundary() -> Double {
        let seconds = Calendar.current.component(.second, from: Date())
        let remaining = 60 - seconds
        return Double(max(remaining, 1))
    }

    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        recentMessages.insert("[\(timestamp)] \(message)", at: 0)
        if recentMessages.count > 12 {
            recentMessages = Array(recentMessages.prefix(12))
        }
    }

    private func restoreSettings() {
        isRestoringSettings = true
        let settings = AppSettingsStore.load()

        if let restoredMode = DisplayMode(rawValue: settings.modeRawValue) {
            mode = restoredMode
        }
        showsDate = settings.showsDate
        statsUpdateInterval = settings.statsUpdateInterval
        usesUnixCPUPercent = settings.usesUnixCPUPercent
        hidesMetricPercentSymbols = settings.hidesMetricPercentSymbols
        visualizerHidesMetricPercentSymbols = settings.visualizerHidesMetricPercentSymbols
        visualizerSource = VisualizerSource(rawValue: settings.visualizerSourceRawValue) ?? .systemAudio
        visualizerGain = settings.visualizerGain
        selectedMicrophoneID = settings.selectedMicrophoneID
        visualizerAirPlayDelay = settings.visualizerAirPlayDelay
        visualizerShowsMetrics = settings.visualizerShowsMetrics
        mediaDitheringEnabled = settings.mediaDitheringEnabled
        mediaContrast = settings.mediaContrast
        mediaZoom = settings.mediaZoom
        mediaInverted = settings.mediaInverted

        if let selectedMediaPath = settings.selectedMediaPath ?? settings.selectedGIFPath ?? settings.selectedImagePath {
            let url = URL(fileURLWithPath: selectedMediaPath)
            if FileManager.default.fileExists(atPath: url.path) {
                selectedMediaURL = url
            }
        }

        isRestoringSettings = false
        persistSettings()
    }

    private func persistSettings() {
        guard !isRestoringSettings else { return }

        let settings = AppSettings(
            modeRawValue: mode.rawValue,
            showsDate: showsDate,
            statsUpdateInterval: statsUpdateInterval,
            usesUnixCPUPercent: usesUnixCPUPercent,
            hidesMetricPercentSymbols: hidesMetricPercentSymbols,
            visualizerHidesMetricPercentSymbols: visualizerHidesMetricPercentSymbols,
            visualizerSourceRawValue: visualizerSource.rawValue,
            visualizerGain: visualizerGain,
            selectedMicrophoneID: selectedMicrophoneID,
            visualizerAirPlayDelay: visualizerAirPlayDelay,
            visualizerShowsMetrics: visualizerShowsMetrics,
            mediaDitheringEnabled: mediaDitheringEnabled,
            mediaContrast: mediaContrast,
            mediaZoom: mediaZoom,
            mediaInverted: mediaInverted,
            selectedMediaPath: selectedMediaURL?.path,
            selectedImagePath: nil,
            selectedGIFPath: nil
        )
        AppSettingsStore.save(settings)
    }

    private func refreshMicrophones() {
        let devices = AudioVisualizerCapture.availableMicrophones()
        availableMicrophones = devices.map { MicrophoneOption(id: $0.uniqueID, name: $0.localizedName) }
        if let selectedMicrophoneID,
           !availableMicrophones.contains(where: { $0.id == selectedMicrophoneID }) {
            self.selectedMicrophoneID = availableMicrophones.first?.id
        } else if self.selectedMicrophoneID == nil {
            self.selectedMicrophoneID = availableMicrophones.first?.id
        }
    }

    private func visualizerCaptureSource() -> AudioVisualizerCapture.Source {
        switch visualizerSource {
        case .systemAudio:
            .systemAudio
        case .microphone:
            .microphone(selectedMicrophoneID)
        }
    }

    private func isGIF(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("gif") == .orderedSame
    }

    private func installExternalModeObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: ExternalModeControl.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyPendingExternalModeRequestIfNeeded()
            }
        }
    }

    private func applyPendingExternalModeRequestIfNeeded() {
        guard let mode = ExternalModeControl.consumeRequestedMode() else {
            return
        }
        self.mode = mode
    }
}

struct MicrophoneOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DelayedVisualizerFrame {
    let bitmap: [UInt8]
    let deliverAt: Date
}

struct GIFFrame {
    let image: CGImage
    let duration: TimeInterval
}

struct AppError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
