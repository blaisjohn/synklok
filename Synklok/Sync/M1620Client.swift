import Foundation

struct DeviceStatus {
    let configuredRate: Int?
    let madiRate: Int?
    let madiSync: Bool?
}

enum M1620Error: Error, LocalizedError {
    case unreachable(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unreachable(let msg): return msg
        case .badResponse:          return "Unexpected response from device"
        }
    }
}

actor M1620Client {
    private var host: String
    private let session: URLSession

    init(host: String) {
        self.host = host
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 2
        cfg.timeoutIntervalForResource = 2
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    func setHost(_ host: String) {
        self.host = host
    }

    private var url: URL {
        URL(string: "http://\(host)/api/v2/self")!
    }

    func getStatus() async throws -> DeviceStatus {
        let payload: [String: Any] = [
            "clock": [
                "sampling_rate": NSNull(),
                "sources": [
                    "madi_coaxial": ["rate": NSNull(), "sync": NSNull()]
                ]
            ]
        ]
        let json = try await post(payload)
        let clock = json["clock"] as? [String: Any] ?? [:]
        let sources = clock["sources"] as? [String: Any] ?? [:]
        let madi = sources["madi_coaxial"] as? [String: Any] ?? [:]
        return DeviceStatus(
            configuredRate: clock["sampling_rate"] as? Int,
            madiRate: madi["rate"] as? Int,
            madiSync: madi["sync"] as? Bool
        )
    }

    func setRate(_ hz: Int) async throws {
        _ = try await post(["clock": ["sampling_rate": hz]])
    }

    private func post(_ payload: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw M1620Error.badResponse
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw M1620Error.badResponse
            }
            return json
        } catch let e as M1620Error {
            throw e
        } catch {
            throw M1620Error.unreachable(error.localizedDescription)
        }
    }
}
