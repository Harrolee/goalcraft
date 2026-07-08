import SwiftUI
import Charts

struct MetricDetailView: View {
    @EnvironmentObject var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    let goalID: Int
    let metricID: Int

    @State private var logAmount = 1
    @State private var note = ""

    private var metric: Metric? {
        store.goal(goalID)?.metrics.first { $0.id == metricID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.lacquer.ignoresSafeArea()
                if let metric {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            header(metric)
                            chart(metric)
                            logger(metric)
                            history(metric)
                        }
                        .padding(20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("THE COUNT").font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(Brand.gold)
                }
            }
            .toolbarBackground(Brand.lacquer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(Brand.gold)
        .presentationBackground(Brand.lacquer)
    }

    private func header(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.name.uppercased())
                .font(BrandFont.signage(18)).tracking(2).foregroundStyle(Brand.gold)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text("\(metric.total)")
                    .font(BrandFont.numeral(72)).foregroundStyle(Brand.ivory)
                if let target = metric.target {
                    Text("/ \(target) \(metric.unit)")
                        .font(BrandFont.body(15)).foregroundStyle(Brand.granite)
                }
            }
            GoldHairline().frame(width: 100)
            Text("\(metric.totalInLast(days: 30)) marks in the last 30 days")
                .font(BrandFont.body(13)).foregroundStyle(Brand.granite)
        }
    }

    @ViewBuilder
    private func chart(_ metric: Metric) -> some View {
        let series = metric.cumulativeSeries
        if series.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("HOW FAR YOU'VE COME").font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.granite)
                Chart(series, id: \.date) { point in
                    AreaMark(x: .value("Date", point.date), y: .value("Total", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Brand.emeraldSilk.opacity(0.30), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", point.date), y: .value("Total", point.value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Brand.emeraldSilk)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(Brand.ivory.opacity(0.06))
                        AxisValueLabel().font(BrandFont.body(10)).foregroundStyle(Brand.granite)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel().font(BrandFont.body(10)).foregroundStyle(Brand.granite)
                    }
                }
            }
            .padding(18)
            .lacquerPanel()
        }
    }

    private func logger(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MARK IT DOWN").font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.gold)
            HStack(spacing: 16) {
                Stepper(value: $logAmount, in: 1...99) {
                    Text("\(logAmount)").font(BrandFont.numeral(28)).foregroundStyle(Brand.ivory)
                }
                .tint(Brand.emerald)
            }
            TextField("", text: $note, prompt: Text("Note (optional)").foregroundStyle(Brand.granite))
                .font(BrandFont.body(15)).foregroundStyle(Brand.ivory)
                .padding(12)
                .background(Brand.lacquerRaise, in: RoundedRectangle(cornerRadius: Brand.corner))
                .overlay(RoundedRectangle(cornerRadius: Brand.corner).stroke(Brand.gold.opacity(0.15), lineWidth: 0.75))
            Button {
                let amt = logAmount, n = note
                note = ""; logAmount = 1
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                Task { await store.log(amt, note: n, to: metricID, in: goalID) }
            } label: {
                Text("MARK IT").font(BrandFont.signage(14)).tracking(3).foregroundStyle(Brand.lacquer)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(LinearGradient(colors: [Brand.goldBright, Brand.gold],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: Brand.corner))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .lacquerPanel()
    }

    @ViewBuilder
    private func history(_ metric: Metric) -> some View {
        if !metric.entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("THE RECORD").font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.gold)
                    .padding(.bottom, 8)
                GoldHairline(opacity: 0.4)
                ForEach(metric.entries.sorted { $0.date > $1.date }) { entry in
                    HStack {
                        Text("+\(entry.amount)")
                            .font(BrandFont.numeral(22)).foregroundStyle(Brand.emeraldSilk)
                            .frame(width: 46, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date, format: .dateTime.month().day().year())
                                .font(BrandFont.body(14)).foregroundStyle(Brand.ivory)
                            if !entry.note.isEmpty {
                                Text(entry.note).font(BrandFont.body(12)).foregroundStyle(Brand.granite)
                            }
                        }
                        Spacer()
                        Button {
                            Task { await store.deleteEntry(entry, from: metricID, in: goalID) }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Brand.granite)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    GoldHairline(opacity: 0.2)
                }
            }
        }
    }
}
