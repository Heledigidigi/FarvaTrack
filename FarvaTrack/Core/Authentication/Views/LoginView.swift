import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            AppLogo(size: 90)
            Text("FarvaTrack")
                .font(.title.bold())
                .foregroundStyle(.white)

            VStack(spacing: 14) {
                TextField("E-posta", text: $email)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.ftCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)

                SecureField("Şifre", text: $password)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.ftCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)

            Button {
                auth.authState = .authenticated
            } label: {
                Text("Giriş Yap")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.ftAccent)
                    .foregroundStyle(Color.ftBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)

            Spacer()
        }
        .background(Color.ftBackground.ignoresSafeArea())
    }
}
