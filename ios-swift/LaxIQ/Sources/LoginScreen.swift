import SwiftUI

struct LoginScreen: View {
    var onSwitchToSignup: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        ZStack {
            Color(white: 0.95).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("🥍").font(.system(size: 48))
                Text("LaxIQ").font(.system(size: 28, weight: .heavy))
                Text("Sign in to your team")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .padding(.bottom, 12)

                if !error.isEmpty {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.system(size: 14, weight: .medium))
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                }

                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color(white: 0.98))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.4), lineWidth: 1.5))

                SecureField("Password", text: $password)
                    .padding(12)
                    .background(Color(white: 0.98))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.4), lineWidth: 1.5))
                    .onSubmit { Task { await handleLogin() } }

                Button {
                    Task { await handleLogin() }
                } label: {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0, green: 0.48, blue: 1))
                .cornerRadius(14)
                .disabled(loading)
                .opacity(loading ? 0.6 : 1)

                Button(action: onSwitchToSignup) {
                    Text("No account? ")
                        .foregroundColor(.gray)
                    + Text("Create your team →")
                        .foregroundColor(Color(red: 0, green: 0.48, blue: 1))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.1), radius: 24, x: 0, y: 8)
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func handleLogin() async {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            error = "Please enter your email and password."
            return
        }

        loading = true
        error = ""

        do {
            try await supabase.auth.signIn(
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                password: password
            )
            // Auth state change listener in LaxIQApp handles navigation
        } catch {
            self.error = error.localizedDescription
        }

        loading = false
    }
}
