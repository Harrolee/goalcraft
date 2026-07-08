import Foundation

/// Talks to the GoalCraft FastAPI backend (Postgres-backed).
/// In local dev the backend runs with DEV_AUTH_BYPASS=true, so no token is
/// required; in production `tokenProvider` supplies the Auth0 bearer token.
struct APIClient {
    var baseURL: URL
    var tokenProvider: () -> String? = { nil }

    static let shared: APIClient = {
        // Release builds hit the deployed backend; debug builds hit local.
        // Override either with the GOALCRAFT_API environment variable.
        #if DEBUG
        let fallback = "http://localhost:8000/api"
        #else
        let fallback = "https://goalcraft-backend-342572871397.us-central1.run.app/api"
        #endif
        let base = ProcessInfo.processInfo.environment["GOALCRAFT_API"] ?? fallback
        return APIClient(baseURL: URL(string: base)!,
                         tokenProvider: { TokenStore.shared.bearer })
    }()

    // MARK: JSON coders

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = DateParsing.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Bad date: \(raw)"))
        }
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: Core request

    enum APIError: LocalizedError {
        case status(Int, String)
        var errorDescription: String? {
            switch self {
            case let .status(code, body): return "Server error \(code): \(body)"
            }
        }
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                       body: Encodable? = nil) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body { req.httpBody = try Self.encoder.encode(AnyEncodable(body)) }

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.status(code, String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try Self.decoder.decode(T.self, from: data)
    }

    private func requestVoid(_ path: String, method: String, body: Encodable? = nil) async throws {
        _ = try await request(path, method: method, body: body) as EmptyResponse
    }

    // MARK: Goals

    func listGoals() async throws -> [Goal] {
        try await request("goals")
    }

    func createGoal(title: String, identity: String?, targetDate: Date?) async throws -> Goal {
        try await request("goals", method: "POST",
                          body: CreateGoalBody(title: title, identity: identity,
                                               targetDate: targetDate, generateMilestones: false))
    }

    func deleteGoal(_ id: Int) async throws { try await requestVoid("goals/\(id)", method: "DELETE") }

    // MARK: Metrics

    func listMetrics(goalId: Int) async throws -> [Metric] {
        try await request("goals/\(goalId)/metrics")
    }

    func createMetric(goalId: Int, name: String, unit: String, symbol: String,
                      color: String, target: Int?, order: Int) async throws -> Metric {
        try await request("goals/\(goalId)/metrics", method: "POST",
                          body: CreateMetricBody(name: name, unit: unit, symbol: symbol,
                                                 color: color, target: target, order: order))
    }

    func deleteMetric(_ id: Int) async throws { try await requestVoid("metrics/\(id)", method: "DELETE") }

    func logEntry(metricId: Int, amount: Int, note: String) async throws -> Metric {
        try await request("metrics/\(metricId)/entries", method: "POST",
                          body: LogEntryBody(amount: amount, note: note))
    }

    func deleteEntry(metricId: Int, entryId: Int) async throws {
        try await requestVoid("metrics/\(metricId)/entries/\(entryId)", method: "DELETE")
    }

    // MARK: Account

    func deleteAccount() async throws { try await requestVoid("account", method: "DELETE") }
}

// MARK: - Request bodies

private struct CreateGoalBody: Encodable {
    let title: String
    let identity: String?
    let targetDate: Date?
    let generateMilestones: Bool
}
private struct CreateMetricBody: Encodable {
    let name: String; let unit: String; let symbol: String
    let color: String; let target: Int?; let order: Int
}
private struct LogEntryBody: Encodable { let amount: Int; let note: String }

struct EmptyResponse: Decodable {}

/// Type-erased Encodable so `request` can take any body.
private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

// MARK: - Lenient ISO8601 date parsing (handles Postgres microseconds + offset)

enum DateParsing {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let micro: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return f
    }()

    static func date(from raw: String) -> Date? {
        micro.date(from: raw) ?? isoFractional.date(from: raw) ?? iso.date(from: raw)
    }
}
