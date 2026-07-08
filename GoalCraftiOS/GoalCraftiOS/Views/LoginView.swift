import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        ZStack {
            Brand.lacquer.ignoresSafeArea()

            // Diffused light + feather — the lobby at night.
            DiffusedGlow(color: Brand.emeraldSilk)
                .frame(width: 340, height: 340).offset(x: -80, y: -220)
            Feather(tint: Brand.gold)
                .frame(width: 180, height: 300).opacity(0.35)
                .rotationEffect(.degrees(-14)).offset(x: 120, y: -120)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("SCREEN TEST")
                    .font(BrandFont.signage(20)).tracking(5).foregroundStyle(Brand.gold)

                GoldHairline().frame(width: 90).padding(.vertical, 16)

                Text("Come in, darling.\nLet's make you someone.")
                    .font(BrandFont.display(40)).foregroundStyle(Brand.ivory)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)

                Text("Tell me the life you're after. We'll count it into being, you and I.")
                    .font(BrandFont.display(16)).italic()
                    .foregroundStyle(Brand.ivory.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    .padding(.top, 12)

                Spacer()

                Text("Go on. A little out of your depth is exactly where I'll find you.")
                    .font(BrandFont.display(15)).italic()
                    .foregroundStyle(Brand.ivory.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    .padding(.bottom, 20)

                Button {
                    Task { await auth.loginWithApple() }
                } label: {
                    HStack(spacing: 8) {
                        if auth.isWorking { ProgressView().tint(.black) }
                        else { Image(systemName: "applelogo").font(.system(size: 18, weight: .medium)) }
                        Text("Sign in with Apple").font(.system(size: 19, weight: .medium))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: Brand.corner))
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking)

                if let err = auth.errorMessage {
                    Text(err).font(BrandFont.body(12)).foregroundStyle(Brand.flame)
                        .padding(.top, 8)
                }

                #if DEBUG
                Button {
                    auth.devEnter()
                } label: {
                    Text("Continue in dev mode")
                        .font(BrandFont.body(13)).foregroundStyle(Brand.granite)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .padding(.top, 8)
                #endif

                Text("By continuing you agree to our Terms & Privacy Policy.")
                    .font(BrandFont.body(11)).foregroundStyle(Brand.granite)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)
            }
            .padding(28)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
    }
}
