import Foundation
import SwiftUI

// Models mirror the GoalCraft FastAPI responses. Nothing is hardcoded —
// every value is loaded from / written to the Postgres-backed API.

// MARK: - MetricEntry

struct MetricEntry: Identifiable, Codable, Hashable {
    let id: Int
    var amount: Int
    var note: String
    var loggedAt: Date

    var date: Date { loggedAt }
}

// MARK: - Metric

struct Metric: Identifiable, Codable, Hashable {
    let id: Int
    let goalId: Int
    var name: String
    var unit: String
    var symbol: String
    /// Hex accent color string, e.g. "#1E9068".
    var color: String
    var target: Int?
    var order: Int
    var entries: [MetricEntry]
    /// Server-computed sum of entry amounts.
    var total: Int

    var tint: Color { Color(hex: color) }

    var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(1.0, Double(total) / Double(target))
    }

    /// Cumulative running total over time — for trend charts.
    var cumulativeSeries: [(date: Date, value: Int)] {
        let sorted = entries.sorted { $0.loggedAt < $1.loggedAt }
        var running = 0
        return sorted.map { running += $0.amount; return ($0.loggedAt, running) }
    }

    func totalInLast(days: Int) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return entries.filter { $0.loggedAt >= cutoff }.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Goal

struct Goal: Identifiable, Codable, Hashable {
    let id: Int
    let userId: Int
    var title: String
    var description: String?
    /// Identity-based framing: who the user is becoming.
    var identity: String?
    var targetDate: Date?
    var createdAt: Date

    // Populated by a separate /metrics fetch; not part of the goal payload.
    var metrics: [Metric] = []

    var totalLogged: Int { metrics.reduce(0) { $0 + $1.total } }

    enum CodingKeys: String, CodingKey {
        case id, userId, title, description, identity, targetDate, createdAt
    }
}

// MARK: - Color hex helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 3: (r, g, b) = ((int >> 8 & 0xF) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        default: (r, g, b) = (30, 144, 104)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }

    /// Uppercase hex string for sending to the API.
    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
