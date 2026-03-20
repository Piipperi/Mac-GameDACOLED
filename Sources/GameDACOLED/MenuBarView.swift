import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    let showControlWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GameDAC OLED")
                .font(.headline)

            Text(appModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Mode", selection: $appModel.mode) {
                ForEach(AppModel.DisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button("Open Window") {
                    showControlWindow()
                }

                Button("Reconnect") {
                    Task { await appModel.reconnect() }
                }
            }

            switch appModel.mode {
            case .off:
                Text("Stop updates and clear the OLED.")
                    .foregroundStyle(.secondary)
            case .clock:
                Toggle("Show Date", isOn: $appModel.showsDate)
            case .system:
                Toggle("Show Date", isOn: $appModel.showsDate)
                Picker("Rate", selection: $appModel.statsUpdateInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                Toggle("CPU as Unix %", isOn: $appModel.usesUnixCPUPercent)
                Toggle("Hide % symbols", isOn: $appModel.hidesMetricPercentSymbols)
            case .visualizer:
                Picker("Source", selection: $appModel.visualizerSource) {
                    ForEach(AppModel.VisualizerSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                if appModel.visualizerSource == .microphone {
                    Picker("Microphone", selection: $appModel.selectedMicrophoneID) {
                        ForEach(appModel.availableMicrophones) { microphone in
                            Text(microphone.name).tag(Optional(microphone.id))
                        }
                    }
                }
                Picker("Rate", selection: $appModel.statsUpdateInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                Toggle("CPU as Unix %", isOn: $appModel.usesUnixCPUPercent)
                Toggle("Hide % symbols", isOn: $appModel.visualizerHidesMetricPercentSymbols)
                VisualizerGainField(gain: $appModel.visualizerGain)
                Toggle("AirPlay delay (2s)", isOn: $appModel.visualizerAirPlayDelay)
                Toggle("Show metrics overlay", isOn: $appModel.visualizerShowsMetrics)
            case .media:
                Button("Choose Image or GIF") {
                    appModel.chooseMedia()
                }
                Toggle("Enable dithering", isOn: $appModel.mediaDitheringEnabled)
                Toggle("Invert", isOn: $appModel.mediaInverted)
                HStack(spacing: 8) {
                    Text("Contrast")
                    Slider(value: $appModel.mediaContrast, in: 0.5 ... 2, step: 0.05)
                }
                HStack(spacing: 8) {
                    Text("Zoom")
                    Slider(value: $appModel.mediaZoom, in: 0.5 ... 3, step: 0.05)
                }
            }

            if let lastError = appModel.lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Send Now") {
                    Task { await appModel.resendCurrentFrame() }
                }

                Button("Clear") {
                    Task { await appModel.clearDisplay() }
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
