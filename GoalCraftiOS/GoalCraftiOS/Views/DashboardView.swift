import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: GoalStore
    @State private var selectedGoalID: Int?
    @State private var showAddMetric = false
    @State private var showAddGoal = false
    @State private var showSettings = false
    @State private var showVoice = false
    @State private var detailMetric: Metric?
    @State private var appeared = false

    private var currentGoal: Goal? {
        if let id = selectedGoalID, let g = store.goal(id) { return g }
        return store.goals.first
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Brand.lacquer.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let goal = currentGoal {
                            if store.goals.count > 1 { goalPicker.padding(.bottom, 18) }
                            hero(goal)
                            if let featured = goal.metrics.first {
                                FeaturedMetricView(metric: featured) {
                                    quickLog(featured.id, goal.id)
                                }
                                .onTapGesture { detailMetric = featured }
                                .padding(.top, 22)
                            }
                            ledger(goal)
                        } else if store.isLoading {
                            loading
                        } else if let msg = store.errorMessage {
                            errorState(msg)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                }
                .refreshable { await store.load() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SCREEN TEST")
                        .font(BrandFont.signage(16)).tracking(3).foregroundStyle(Brand.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showVoice = true } label: { Label("Describe by Voice", systemImage: "mic.fill") }
                            .disabled(currentGoal == nil)
                        Button { showAddMetric = true } label: { Label("Add Metric", systemImage: "plus") }
                            .disabled(currentGoal == nil)
                        Button { showAddGoal = true } label: { Label("New Goal", systemImage: "target") }
                        Divider()
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Brand.ivory)
                    }
                }
            }
            .toolbarBackground(Brand.lacquer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAddMetric) {
                if let goal = currentGoal { AddMetricView(goalID: goal.id).environmentObject(store) }
            }
            .sheet(isPresented: $showAddGoal) {
                AddGoalView { newID in selectedGoalID = newID }.environmentObject(store)
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
            .sheet(isPresented: $showVoice) {
                if let goal = currentGoal { VoiceMetricsView(goalID: goal.id).environmentObject(store) }
            }
            .sheet(item: $detailMetric) { metric in
                if let goal = currentGoal {
                    MetricDetailView(goalID: goal.id, metricID: metric.id).environmentObject(store)
                }
            }
        }
        .tint(Brand.gold)
        .task { await store.load() }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appeared = true } }
    }

    // MARK: - Hero

    private func hero(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOU ARE BECOMING")
                .font(BrandFont.signage(13)).tracking(3).foregroundStyle(Brand.gold)

            Text(goal.title)
                .font(BrandFont.display(42)).foregroundStyle(Brand.ivory)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)

            GoldHairline().frame(width: 120).padding(.vertical, 4)

            if let identity = goal.identity, !identity.isEmpty {
                Text(identity)
                    .font(BrandFont.display(17)).italic()
                    .foregroundStyle(Brand.ivory.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }

            HStack(spacing: 26) {
                heroStat("\(goal.totalLogged)", "ENTRIES")
                heroStat("\(goal.metrics.count)", "METRICS")
                if let d = goal.targetDate { heroStat(daysLeft(d), "DAYS") }
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(BrandFont.numeral(30)).foregroundStyle(Brand.ivory)
            Text(label).font(BrandFont.signage(10)).tracking(1.5).foregroundStyle(Brand.granite)
        }
    }

    // MARK: - Ledger

    private func ledger(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("THE LEDGER")
                    .font(BrandFont.signage(13)).tracking(3).foregroundStyle(Brand.gold)
                Spacer()
                Button { showVoice = true } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.gold)
                        .padding(.trailing, 4)
                }
                Button { showAddMetric = true } label: {
                    Text("＋ METRIC")
                        .font(BrandFont.signage(12)).tracking(1.5).foregroundStyle(Brand.granite)
                }
            }
            .padding(.top, 34).padding(.bottom, 4)

            GoldHairline(opacity: 0.5)

            ForEach(Array(goal.metrics.dropFirst()), id: \.id) { metric in
                MetricRow(metric: metric) { quickLog(metric.id, goal.id) }
                    .onTapGesture { detailMetric = metric }
                GoldHairline(opacity: 0.28)
            }

            if goal.metrics.count <= 1 {
                Text("Now — what shall we count as proof?")
                    .font(BrandFont.display(15)).italic().foregroundStyle(Brand.granite)
                    .padding(.top, 18)
            }
        }
    }

    // MARK: - Goal picker

    private var goalPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(store.goals) { goal in
                    let selected = goal.id == currentGoal?.id
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { selectedGoalID = goal.id }
                    } label: {
                        VStack(spacing: 5) {
                            Text(goal.title.uppercased())
                                .font(BrandFont.signage(13)).tracking(1.5)
                                .foregroundStyle(selected ? Brand.ivory : Brand.granite)
                            Rectangle().fill(selected ? Brand.gold : .clear)
                                .frame(width: 20, height: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    // MARK: - States

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Brand.gold)
            Text("LOADING THE LEDGER")
                .font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.granite)
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COULDN'T LOAD")
                .font(BrandFont.signage(15)).tracking(2).foregroundStyle(Brand.flame)
            Text(msg).font(BrandFont.body(14)).foregroundStyle(Brand.ivory.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            goldButton("RETRY") { Task { await store.load() } }.padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 100)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NOTHING HERE YET")
                .font(BrandFont.signage(15)).tracking(2).foregroundStyle(Brand.gold)
            Text("Blank page, darling.\nMy favourite kind.")
                .font(BrandFont.display(30)).foregroundStyle(Brand.ivory)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            Text("Tell me who you're becoming. Then we'll count the proof, one small mark at a time.")
                .font(BrandFont.display(15)).italic()
                .foregroundStyle(Brand.ivory.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                .padding(.top, 2)
            goldButton("BEGIN") { showAddGoal = true }.padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 90)
    }

    private func goldButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.signage(14)).tracking(3).foregroundStyle(Brand.lacquer)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(LinearGradient(colors: [Brand.goldBright, Brand.gold],
                                           startPoint: .top, endPoint: .bottom), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func quickLog(_ metricID: Int, _ goalID: Int) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task { await store.log(1, to: metricID, in: goalID) }
    }

    private func daysLeft(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return "\(max(0, days))"
    }
}
