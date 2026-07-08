import SwiftUI
import Charts

// MARK: - Featured metric — the marquee of the ledger

struct FeaturedMetricView: View {
    let metric: Metric
    let onQuickLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(metric.name.uppercased())
                    .font(BrandFont.signage(15))
                    .tracking(2)
                    .foregroundStyle(Brand.gold)
                Spacer()
                if let target = metric.target {
                    Text("OF \(target)")
                        .font(BrandFont.signage(12))
                        .tracking(1.5)
                        .foregroundStyle(Brand.granite)
                        .padding(.top, 3)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text("\(metric.total)")
                    .font(BrandFont.numeral(88))
                    .foregroundStyle(Brand.ivory)
                    .contentTransition(.numericText())
                Spacer()
                logButton
            }
            .padding(.top, 2)

            if metric.target != nil {
                progressRule.padding(.top, 6)
            }

            trendLine
                .frame(height: 44)
                .padding(.top, 14)
        }
        .padding(22)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Brand.corner, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.emeraldDeep, Brand.lacquerRaise],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                DiffusedGlow(color: metric.tint)
                    .frame(width: 260, height: 260)
                    .offset(x: 120, y: -70)
                Feather(tint: Brand.gold)
                    .frame(width: 130, height: 190)
                    .opacity(0.5)
                    .rotationEffect(.degrees(18))
                    .offset(x: 120, y: 30)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: Brand.corner, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.corner, style: .continuous)
                .stroke(Brand.gold.opacity(0.22), lineWidth: 0.75)
        )
    }

    private var logButton: some View {
        Button(action: onQuickLog) {
            Text("＋")
                .font(BrandFont.display(24))
                .foregroundStyle(Brand.lacquer)
                .frame(width: 46, height: 46)
                .background(
                    LinearGradient(colors: [Brand.goldBright, Brand.gold],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle())
        }
        .buttonStyle(.plain)
        .offset(y: -8)
    }

    private var progressRule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.ivory.opacity(0.08)).frame(height: 2)
                Capsule()
                    .fill(LinearGradient(colors: [Brand.emerald, Brand.emeraldSilk],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * metric.progress), height: 2)
            }
        }
        .frame(height: 2)
    }

    @ViewBuilder
    private var trendLine: some View {
        let series = metric.cumulativeSeries
        if series.count >= 2 {
            Chart(series, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Total", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(
                        colors: [Brand.emeraldSilk.opacity(0.28), .clear],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value("Total", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Brand.emeraldSilk)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
        }
    }
}

// MARK: - Ledger row — hairline-separated, editorial

struct MetricRow: View {
    let metric: Metric
    let onQuickLog: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(metric.name.uppercased())
                    .font(BrandFont.signage(14))
                    .tracking(1.6)
                    .foregroundStyle(Brand.ivory)
                if let target = metric.target {
                    HStack(spacing: 8) {
                        thinBar(metric.progress).frame(width: 88)
                        Text("toward \(target)")
                            .font(BrandFont.body(11))
                            .foregroundStyle(Brand.granite)
                    }
                } else {
                    Text(metric.unit.isEmpty ? "logged" : metric.unit)
                        .font(BrandFont.body(11))
                        .foregroundStyle(Brand.granite)
                }
            }

            Spacer()

            Text("\(metric.total)")
                .font(BrandFont.numeral(40))
                .foregroundStyle(Brand.ivory)
                .contentTransition(.numericText())

            Button(action: onQuickLog) {
                Text("＋")
                    .font(BrandFont.display(20))
                    .foregroundStyle(Brand.gold)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Brand.gold.opacity(0.4), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func thinBar(_ p: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.ivory.opacity(0.08)).frame(height: 2)
                Capsule().fill(metric.tint)
                    .frame(width: max(2, geo.size.width * p), height: 2)
            }
        }
        .frame(height: 2)
    }
}
