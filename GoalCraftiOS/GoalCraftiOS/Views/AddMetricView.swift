import SwiftUI

struct AddMetricView: View {
    @EnvironmentObject var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    let goalID: Int

    @State private var name = ""
    @State private var unit = ""
    @State private var hasTarget = false
    @State private var target = 12
    @State private var symbol = "sparkles"
    @State private var colorHex = "#1E9068"
    @State private var saving = false

    private let symbols = ["sparkles", "pencil.and.scribble", "waveform", "person.2.fill",
                           "dollarsign.circle.fill", "music.note", "mic.fill", "star.fill",
                           "flame.fill", "book.fill", "paintbrush.fill", "figure.run"]
    private let palette = ["#1E9068", "#116B4E", "#3AA981", "#C9A55C", "#E9D19A", "#C6413B"]

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.lacquer.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        preview.padding(.top, 8)

                        field("WHAT WE'RE COUNTING") { brandTextField("Songs Released", text: $name) }
                        field("MEASURED IN") { brandTextField("songs", text: $unit) }

                        field("THE NUMBER TO CHASE") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle(isOn: $hasTarget) {
                                    Text("Give it a number to chase")
                                        .font(BrandFont.body(15)).foregroundStyle(Brand.ivory)
                                }.tint(Brand.emerald)
                                if hasTarget {
                                    Stepper(value: $target, in: 1...100000) {
                                        Text("\(target)").font(BrandFont.numeral(26)).foregroundStyle(Brand.ivory)
                                    }.tint(Brand.emerald)
                                }
                            }
                        }

                        field("ITS FACE") { symbolGrid }
                        field("ITS COLOUR") { colorRow }

                        Button {
                            Task { await save() }
                        } label: {
                            Text(saving ? "ADDING…" : "ADD TO THE LEDGER")
                                .font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.lacquer)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(LinearGradient(colors: [Brand.goldBright, Brand.gold],
                                                           startPoint: .top, endPoint: .bottom),
                                            in: RoundedRectangle(cornerRadius: Brand.corner))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("saveMetricButton")
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("A NEW COUNT").font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.gold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Brand.granite)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView().tint(Brand.gold) }
                        else { Text("Add").font(BrandFont.body(16, .semibold)) }
                    }
                    .tint(Brand.gold)
                    .accessibilityIdentifier("saveMetricButton")
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .toolbarBackground(Brand.lacquer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(Brand.gold)
        .presentationBackground(Brand.lacquer)
    }

    private var preview: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: colorHex))
                .frame(width: 48, height: 48)
                .background(Color(hex: colorHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "Metric name" : name.uppercased())
                    .font(BrandFont.signage(15)).tracking(1.4)
                    .foregroundStyle(name.isEmpty ? Brand.granite : Brand.ivory)
                Text(hasTarget ? "toward \(target)" : (unit.isEmpty ? "logged" : unit))
                    .font(BrandFont.body(12)).foregroundStyle(Brand.granite)
            }
            Spacer()
            Text("0").font(BrandFont.numeral(38)).foregroundStyle(Brand.ivory)
        }
        .padding(16).lacquerPanel()
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(symbols, id: \.self) { s in
                let sel = s == symbol
                Image(systemName: s)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(sel ? Brand.lacquer : Brand.ivory)
                    .frame(width: 44, height: 44)
                    .background(sel ? Brand.gold : Brand.lacquerRaise, in: RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { symbol = s }
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 12) {
            ForEach(palette, id: \.self) { hex in
                Circle().fill(Color(hex: hex))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Brand.ivory, lineWidth: colorHex == hex ? 2 : 0))
                    .onTapGesture { colorHex = hex }
            }
        }
    }

    private func save() async {
        saving = true
        await store.addMetric(goalID: goalID,
                              name: name.trimmingCharacters(in: .whitespaces),
                              unit: unit, symbol: symbol, color: colorHex,
                              target: hasTarget ? target : nil)
        saving = false
        dismiss()
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.gold)
            content()
        }
    }
}
