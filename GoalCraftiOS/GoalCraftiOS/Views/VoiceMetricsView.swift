import SwiftUI

/// Speak about the life you're after → Claude proposes metrics → you confirm.
struct VoiceMetricsView: View {
    @EnvironmentObject var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechService()
    let goalID: Int

    enum Phase { case record, thinking, review, adding }
    @State private var phase: Phase = .record
    @State private var proposals: [ProposedMetric] = []
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.lacquer.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch phase {
                        case .record:   recorder
                        case .thinking: thinking
                        case .review, .adding: review
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SAY IT OUT LOUD").font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { speech.stop(); dismiss() }.tint(Brand.gold)
                }
            }
            .toolbarBackground(Brand.lacquer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(Brand.gold)
        .presentationBackground(Brand.lacquer)
    }

    // MARK: - Record

    private var recorder: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tell me who you're becoming.")
                .font(BrandFont.display(28)).foregroundStyle(Brand.ivory)
                .fixedSize(horizontal: false, vertical: true)
            Text("Say it however you like — I'll turn it into the handful of numbers worth counting.")
                .font(BrandFont.display(15)).italic().foregroundStyle(Brand.ivory.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    if speech.isRecording { await finishRecording() }
                    else if await speech.requestPermission() { speech.start() }
                }
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Brand.lacquer)
                        .frame(width: 92, height: 92)
                        .background(
                            LinearGradient(colors: [Brand.goldBright, Brand.gold], startPoint: .top, endPoint: .bottom),
                            in: Circle())
                    Text(speech.isRecording ? "TAP TO STOP" : "TAP TO SPEAK")
                        .font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.granite)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 12)

            if !speech.transcript.isEmpty {
                Text(speech.transcript)
                    .font(BrandFont.body(16)).foregroundStyle(Brand.ivory)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).lacquerPanel()
            }
            if let err = speech.errorMessage {
                Text(err).font(BrandFont.body(13)).foregroundStyle(Brand.flame)
            }
        }
    }

    // MARK: - Thinking

    private var thinking: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Brand.gold)
            Text("READING BETWEEN THE LINES")
                .font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.granite)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }

    // MARK: - Review

    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Here's what I'd count.")
                .font(BrandFont.display(26)).foregroundStyle(Brand.ivory)
            Text("Keep what rings true; I'll add them to your ledger.")
                .font(BrandFont.display(14)).italic().foregroundStyle(Brand.ivory.opacity(0.7))

            ForEach(proposals) { p in
                let on = selected.contains(p.id)
                Button {
                    if on { selected.remove(p.id) } else { selected.insert(p.id) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: p.color))
                            .frame(width: 42, height: 42)
                            .background(Color(hex: p.color).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.name.uppercased()).font(BrandFont.signage(15)).tracking(1.2).foregroundStyle(Brand.ivory)
                            Text(p.target.map { "toward \($0) \(p.unit)" } ?? p.unit)
                                .font(BrandFont.body(12)).foregroundStyle(Brand.granite)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22)).foregroundStyle(on ? Brand.gold : Brand.granite.opacity(0.5))
                    }
                    .padding(14).lacquerPanel()
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await addSelected() }
            } label: {
                Text(phase == .adding ? "ADDING…" : "ADD \(selected.count) TO THE LEDGER")
                    .font(BrandFont.signage(14)).tracking(2).foregroundStyle(Brand.lacquer)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(LinearGradient(colors: [Brand.goldBright, Brand.gold], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: Brand.corner))
            }
            .buttonStyle(.plain)
            .disabled(selected.isEmpty || phase == .adding)
            .padding(.top, 6)

            Button("Start over") { proposals = []; selected = []; speech.transcript = ""; phase = .record }
                .font(BrandFont.body(13)).tint(Brand.granite)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func finishRecording() async {
        speech.stop()
        let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 3 else { return }
        phase = .thinking
        let result = await store.suggestMetrics(goalID: goalID, transcript: text)
        proposals = result
        selected = Set(result.map { $0.id })
        phase = .review
    }

    private func addSelected() async {
        phase = .adding
        for p in proposals where selected.contains(p.id) {
            await store.addMetric(goalID: goalID, name: p.name, unit: p.unit,
                                  symbol: p.symbol, color: p.color, target: p.target)
        }
        dismiss()
    }
}
