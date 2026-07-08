import SwiftUI

struct AddGoalView: View {
    @EnvironmentObject var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    var onCreated: (Int) -> Void

    @State private var title = ""
    @State private var identity = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.lacquer.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("So. Who are you\nbecoming?")
                                .font(BrandFont.display(30)).foregroundStyle(Brand.ivory)
                                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                            Text("Don't tell me what you'll try. Tell me who you already are — we'll spend the rest proving it.")
                                .font(BrandFont.display(14)).italic()
                                .foregroundStyle(Brand.ivory.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                        }
                        .padding(.top, 8)

                        field("THE NAME FOR IT") {
                            brandTextField("Professional Songwriter", text: $title)
                        }

                        field("WHO THAT MAKES YOU") {
                            brandTextField("A songwriter whose work is heard, recorded, and paid for.",
                                           text: $identity, axis: .vertical)
                        }

                        field("BY WHEN") {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle(isOn: $hasTargetDate) {
                                    Text("Give it a horizon")
                                        .font(BrandFont.body(15)).foregroundStyle(Brand.ivory)
                                }
                                .tint(Brand.emerald)
                                if hasTargetDate {
                                    DatePicker("", selection: $targetDate, displayedComponents: .date)
                                        .labelsHidden().datePickerStyle(.compact)
                                        .colorScheme(.dark).tint(Brand.gold)
                                }
                            }
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            Text(saving ? "BEGINNING…" : "BEGIN")
                                .font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.lacquer)
                                .frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(LinearGradient(colors: [Brand.goldBright, Brand.gold],
                                                           startPoint: .top, endPoint: .bottom),
                                            in: RoundedRectangle(cornerRadius: Brand.corner))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("saveGoalButton")
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("A NEW SELF").font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.gold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not yet") { dismiss() }.tint(Brand.granite)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView().tint(Brand.gold) }
                        else { Text("Begin").font(BrandFont.body(16, .semibold)) }
                    }
                    .tint(Brand.gold)
                    .accessibilityIdentifier("saveGoalButton")
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .toolbarBackground(Brand.lacquer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(Brand.gold)
        .presentationBackground(Brand.lacquer)
    }

    private func save() async {
        saving = true
        let goal = await store.createGoal(
            title: title.trimmingCharacters(in: .whitespaces),
            identity: identity.isEmpty ? nil : identity,
            targetDate: hasTargetDate ? targetDate : nil)
        saving = false
        if let goal { onCreated(goal.id); dismiss() }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.gold)
            content()
        }
    }
}

func brandTextField(_ prompt: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
    TextField("", text: text, prompt: Text(prompt).foregroundStyle(Brand.granite.opacity(0.7)), axis: axis)
        .font(BrandFont.body(16)).foregroundStyle(Brand.ivory)
        .lineLimit(axis == .vertical ? 5 : 1)
        .padding(14)
        .background(Brand.lacquerRaise, in: RoundedRectangle(cornerRadius: Brand.corner))
        .overlay(RoundedRectangle(cornerRadius: Brand.corner).stroke(Brand.gold.opacity(0.18), lineWidth: 0.75))
}
