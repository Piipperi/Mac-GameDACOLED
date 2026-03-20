import SwiftUI

struct VisualizerGainField: View {
    @Binding private var gain: Double
    @FocusState private var isFocused: Bool
    @State private var text: String

    init(gain: Binding<Double>) {
        self._gain = gain
        self._text = State(initialValue: Self.displayText(for: gain.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("Gain %")
            TextField("Gain", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .focused($isFocused)
                .onChange(of: text) { newValue in
                    guard !newValue.isEmpty, let parsed = Self.parsePercent(newValue) else {
                        return
                    }
                    gain = Self.clampGain(parsed / 100)
                }
                .onChange(of: isFocused) { focused in
                    if !focused {
                        commit()
                    }
                }
                .onSubmit {
                    commit()
                }
            Text("%")
                .foregroundStyle(.secondary)
        }
    }

    private func commit() {
        if let parsed = Self.parsePercent(text) {
            gain = Self.clampGain(parsed / 100)
        }
        text = Self.displayText(for: gain)
    }

    private static func parsePercent(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else {
            return nil
        }
        return Double(cleaned)
    }

    private static func displayText(for gain: Double) -> String {
        String(Int((gain * 100).rounded()))
    }

    private static func clampGain(_ gain: Double) -> Double {
        min(max(gain, 0.0001), 0.3)
    }
}
