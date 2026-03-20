import Foundation

struct GameSenseClient {
    private let session: URLSession

    private static let gameName = "GAMEDAC_OLED"
    private static let eventName = "FRAME"
    private static let screenWidth = 128
    private static let screenHeight = 52

    init(session: URLSession = .shared) {
        self.session = session
    }

    func initialize() async throws -> URL {
        let endpoint = try discoverEndpoint()

        try await post(
            to: endpoint,
            path: "game_metadata",
            payload: [
                "game": Self.gameName,
                "game_display_name": "GameDAC OLED Controller",
                "developer": "Codex",
                "deinitialize_timer_length_ms": 60000
            ]
        )

        try await post(
            to: endpoint,
            path: "bind_game_event",
            payload: [
                "game": Self.gameName,
                "event": Self.eventName,
                "min_value": 0,
                "max_value": 100,
                "value_optional": true,
                "icon_id": 0,
                "handlers": [
                    [
                        "device-type": "screened-\(Self.screenWidth)x\(Self.screenHeight)",
                        "zone": "one",
                        "mode": "screen",
                        "datas": [
                            [
                                "has-text": false,
                                "image-data": ImageRenderer.blankBitmap(),
                                "length-millis": 0
                            ]
                        ]
                    ]
                ]
            ]
        )

        return endpoint
    }

    func send(bitmap: [UInt8], value: Int) async throws {
        guard bitmap.count == ImageRenderer.bitmapLength else {
            throw AppError("Invalid bitmap length \(bitmap.count); expected \(ImageRenderer.bitmapLength).")
        }

        let endpoint = try discoverEndpoint()
        try await post(
            to: endpoint,
            path: "game_event",
            payload: [
                "game": Self.gameName,
                "event": Self.eventName,
                "data": [
                    "value": value,
                    "frame": [
                        "image-data-\(Self.screenWidth)x\(Self.screenHeight)": bitmap
                    ]
                ]
            ]
        )
    }

    func heartbeat() async throws {
        let endpoint = try discoverEndpoint()
        try await post(
            to: endpoint,
            path: "game_heartbeat",
            payload: [
                "game": Self.gameName
            ]
        )
    }

    private func discoverEndpoint() throws -> URL {
        for path in Self.corePropsPaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }

            let data = try Data(contentsOf: url)
            let props = try JSONDecoder().decode(CoreProps.self, from: data)
            return try normalizedEndpoint(from: props.address)
        }

        throw AppError(
            """
            Could not find SteelSeries coreProps.json. Checked:
            \(Self.corePropsPaths.joined(separator: "\n"))
            """
        )
    }

    private func normalizedEndpoint(from address: String) throws -> URL {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if let url = URL(string: "http://\(trimmed)") {
            return url
        }

        throw AppError("SteelSeries coreProps.json contained an invalid address: \(address)")
    }

    private func post(to endpoint: URL, path: String, payload: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let requestURL = endpoint.appendingPathComponent(path)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError("GameSense returned an invalid response for \(path).")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let bodyString, !bodyString.isEmpty {
                throw AppError("GameSense returned HTTP \(httpResponse.statusCode) for \(path): \(bodyString)")
            }

            throw AppError("GameSense returned HTTP \(httpResponse.statusCode) for \(path).")
        }
    }

    private struct CoreProps: Decodable {
        let address: String
    }

    private static let corePropsPaths: [String] = [
        "/Library/Application Support/SteelSeries GG/coreProps.json",
        "/Library/Application Support/SteelSeries Engine 3/coreProps.json",
        "\(NSHomeDirectory())/Library/Application Support/SteelSeries GG/coreProps.json",
        "\(NSHomeDirectory())/Library/Application Support/SteelSeries Engine 3/coreProps.json"
    ]
}
