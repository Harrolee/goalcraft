import Foundation
import SwiftUI

/// View-model over the GoalCraft API. All data lives in Postgres; this holds
/// only the in-memory copy the UI renders. No seed data, nothing hardcoded.
@MainActor
final class GoalStore: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            var loaded = try await api.listGoals()
            for i in loaded.indices {
                loaded[i].metrics = try await api.listMetrics(goalId: loaded[i].id)
            }
            goals = loaded
        } catch {
            errorMessage = friendly(error)
        }
        isLoading = false
    }

    func goal(_ id: Int) -> Goal? { goals.first { $0.id == id } }

    // MARK: - Mutations

    @discardableResult
    func createGoal(title: String, identity: String?, targetDate: Date?) async -> Goal? {
        do {
            var goal = try await api.createGoal(title: title, identity: identity, targetDate: targetDate)
            goal.metrics = []
            goals.insert(goal, at: 0)
            return goal
        } catch {
            errorMessage = friendly(error); return nil
        }
    }

    func addMetric(goalID: Int, name: String, unit: String, symbol: String,
                   color: String, target: Int?) async {
        guard let gi = goals.firstIndex(where: { $0.id == goalID }) else { return }
        let order = goals[gi].metrics.count
        do {
            let metric = try await api.createMetric(goalId: goalID, name: name, unit: unit,
                                                    symbol: symbol, color: color,
                                                    target: target, order: order)
            goals[gi].metrics.append(metric)
        } catch {
            errorMessage = friendly(error)
        }
    }

    func log(_ amount: Int = 1, note: String = "", to metricID: Int, in goalID: Int) async {
        do {
            let updated = try await api.logEntry(metricId: metricID, amount: amount, note: note)
            replace(updated, in: goalID)
        } catch {
            errorMessage = friendly(error)
        }
    }

    func deleteEntry(_ entry: MetricEntry, from metricID: Int, in goalID: Int) async {
        // optimistic removal
        if let gi = goals.firstIndex(where: { $0.id == goalID }),
           let mi = goals[gi].metrics.firstIndex(where: { $0.id == metricID }) {
            goals[gi].metrics[mi].entries.removeAll { $0.id == entry.id }
            goals[gi].metrics[mi].total = goals[gi].metrics[mi].entries.reduce(0) { $0 + $1.amount }
        }
        do { try await api.deleteEntry(metricId: metricID, entryId: entry.id) }
        catch { errorMessage = friendly(error) }
    }

    func deleteMetric(_ metricID: Int, from goalID: Int) async {
        if let gi = goals.firstIndex(where: { $0.id == goalID }) {
            goals[gi].metrics.removeAll { $0.id == metricID }
        }
        do { try await api.deleteMetric(metricID) }
        catch { errorMessage = friendly(error) }
    }

    func deleteGoal(_ goalID: Int) async {
        goals.removeAll { $0.id == goalID }
        do { try await api.deleteGoal(goalID) }
        catch { errorMessage = friendly(error) }
    }

    func deleteAccount() async {
        do {
            try await api.deleteAccount()
            goals = []
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Helpers

    private func replace(_ metric: Metric, in goalID: Int) {
        guard let gi = goals.firstIndex(where: { $0.id == goalID }),
              let mi = goals[gi].metrics.firstIndex(where: { $0.id == metric.id }) else { return }
        goals[gi].metrics[mi] = metric
    }

    private func friendly(_ error: Error) -> String {
        if error is URLError {
            return "Can't reach the server. Is the backend running at \(APIClient.shared.baseURL.absoluteString)?"
        }
        return error.localizedDescription
    }
}
