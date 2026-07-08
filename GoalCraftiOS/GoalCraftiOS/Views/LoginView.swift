import SwiftUI
import AuthenticationServices

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

                SignInWithAppleButton(.signIn,
                    onRequest: { $0.requestedScopes = [.fullName, .email] },
                    onCompletion: { auth.handleAppleCompletion($0) })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Brand.corner))

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
