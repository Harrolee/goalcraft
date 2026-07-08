import SwiftUI

/// External links. These resolve to pages served by the GoalCraft web app.
enum AppLinks {
    // Live GitHub Pages deployment (base path /goalcraft/). Update if a custom domain is added.
    static let base = "https://harrolee.github.io/goalcraft"
    static let privacy = URL(string: "\(base)/privacy")!
    static let terms = URL(string: "\(base)/terms")!
    static let about = URL(string: "\(base)/about")!
    static let support = URL(string: "mailto:halzinnia@gmail.com")!
}

struct SettingsView: View {
    @EnvironmentObject var store: GoalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @ObservedObject private var notif = NotificationManager.shared
    @State private var confirmDelete = false
    @State private var deleting = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(v)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.lacquer.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        section("NUDGES FROM BOWIE") {
                            Toggle(isOn: Binding(
                                get: { notif.enabled },
                                set: { on in
                                    Task {
                                        if on { await notif.enableNudges() } else { notif.disableNudges() }
                                    }
                                })
                            ) {
                                Text("Let him leave you notes")
                                    .font(BrandFont.body(16)).foregroundStyle(Brand.ivory)
                            }
                            .tint(Brand.emerald)
                            Text("A word most evenings — tender, theatrical, and certain you've got more in you.")
                                .font(BrandFont.body(12)).foregroundStyle(Brand.granite).padding(.top, 4)
                        }

                        section("SUPPORT & LEGAL") {
                            link("About Screen Test", "info.circle") { openURL(AppLinks.about) }
                            hairline
                            link("Privacy Policy", "hand.raised") { openURL(AppLinks.privacy) }
                            hairline
                            link("Terms of Use", "doc.text") { openURL(AppLinks.terms) }
                            hairline
                            link("Contact Support", "envelope") { openURL(AppLinks.support) }
                        }

                        section("ACCOUNT") {
                            Button {
                                confirmDelete = true
                            } label: {
                                HStack {
                                    Image(systemName: "trash").foregroundStyle(Brand.flame)
                                    Text("Delete Account")
                                        .font(BrandFont.body(16)).foregroundStyle(Brand.flame)
                                    Spacer()
                                    if deleting { ProgressView().tint(Brand.flame) }
                                }
                            }
                            .buttonStyle(.plain)
                            Text("Permanently deletes your account and all goals, metrics, and history. This cannot be undone.")
                                .font(BrandFont.body(12)).foregroundStyle(Brand.granite)
                                .padding(.top, 4)
                        }

                        Text(version)
                            .font(BrandFont.body(12)).foregroundStyle(Brand.granite)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS").font(BrandFont.signage(15)).tracking(3).foregroundStyle(Brand.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.tint(Brand.gold)
                }
            }
            .toolbarBackground(Brand.lacquer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deleting = true
                    Task { await store.deleteAccount(); deleting = false; dismiss() }
                }
            } message: {
                Text("This permanently erases your account and every goal, metric, and entry. This cannot be undone.")
            }
        }
        .tint(Brand.gold)
        .presentationBackground(Brand.lacquer)
        .task { await notif.refreshStatus() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(BrandFont.signage(12)).tracking(2).foregroundStyle(Brand.gold)
            content()
        }
    }

    private func link(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Brand.gold).frame(width: 22)
                Text(title).font(BrandFont.body(16)).foregroundStyle(Brand.ivory)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(Brand.granite)
            }
        }
        .buttonStyle(.plain)
    }

    private var hairline: some View { GoldHairline(opacity: 0.22) }
}
