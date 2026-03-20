import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            modePicker
            controls
            preview
            debugLog
            footer
        }
        .padding(20)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GameDAC OLED Controller")
                .font(.system(size: 28, weight: .semibold))
            Text(appModel.supportedScreenDescription)
                .foregroundStyle(.secondary)
            Label(appModel.statusMessage, systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.primary)
            Text(appModel.endpointDescription)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $appModel.mode) {
            ForEach(AppModel.DisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            Button("Reconnect") {
                Task { await appModel.reconnect() }
            }

            Button("Send Now") {
                Task { await appModel.resendCurrentFrame() }
            }

            Button("Clear OLED") {
                Task { await appModel.clearDisplay() }
            }

            Spacer()
        }

        switch appModel.mode {
        case .off:
            Text("Off mode clears the OLED once and stops sending frames.")
                .foregroundStyle(.secondary)
        case .clock:
            Toggle("Show date", isOn: $appModel.showsDate)
            Text("Clock mode redraws only when the displayed minute changes.")
                .foregroundStyle(.secondary)
        case .system:
            HStack(spacing: 16) {
                Toggle("Show date", isOn: $appModel.showsDate)
                Picker("Update rate", selection: $appModel.statsUpdateInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                .pickerStyle(.segmented)
            }
            Toggle("CPU as Unix %", isOn: $appModel.usesUnixCPUPercent)
            Toggle("Hide % symbols", isOn: $appModel.hidesMetricPercentSymbols)
        case .visualizer:
            Picker("Source", selection: $appModel.visualizerSource) {
                ForEach(AppModel.VisualizerSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            if appModel.visualizerSource == .microphone {
                Picker("Microphone", selection: $appModel.selectedMicrophoneID) {
                    ForEach(appModel.availableMicrophones) { microphone in
                        Text(microphone.name).tag(Optional(microphone.id))
                    }
                }
            }
            HStack(spacing: 16) {
                Picker("Update rate", selection: $appModel.statsUpdateInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                    Text("10s").tag(10.0)
                }
                .pickerStyle(.segmented)
            }
            Toggle("CPU as Unix %", isOn: $appModel.usesUnixCPUPercent)
            Toggle("Hide % symbols", isOn: $appModel.visualizerHidesMetricPercentSymbols)
            VisualizerGainField(gain: $appModel.visualizerGain)
            Toggle("AirPlay delay (2s)", isOn: $appModel.visualizerAirPlayDelay)
            Toggle("Show metrics overlay", isOn: $appModel.visualizerShowsMetrics)
            Text("Visualizer mode can use either system audio or a selected microphone input.")
                .foregroundStyle(.secondary)
        case .media:
            HStack(spacing: 12) {
                Button("Choose Image or GIF") {
                    appModel.chooseMedia()
                }
                Text(appModel.selectedMediaURL?.path ?? "No media selected")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            Toggle("Enable dithering", isOn: $appModel.mediaDitheringEnabled)
            Toggle("Invert", isOn: $appModel.mediaInverted)
            HStack(spacing: 12) {
                Text("Contrast")
                Slider(value: $appModel.mediaContrast, in: 0.5 ... 2, step: 0.05)
                Text(appModel.mediaContrast, format: .number.precision(.fractionLength(2)))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Text("Zoom")
                Slider(value: $appModel.mediaZoom, in: 0.5 ... 3, step: 0.05)
                Text(appModel.mediaZoom, format: .number.precision(.fractionLength(2)))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OLED Preview")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                if let previewImage = appModel.previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .padding(18)
                } else {
                    Text("Nothing rendered yet")
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
        }
    }

    private var debugLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(appModel.recentMessages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(height: 120)
            .padding(10)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let lastError = appModel.lastError {
            Text(lastError)
                .font(.system(.footnote, design: .default))
                .foregroundStyle(.red)
        } else {
            Text("This app uses SteelSeries GameSense over localhost and targets the GameDAC's official 128x52 screen class.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
