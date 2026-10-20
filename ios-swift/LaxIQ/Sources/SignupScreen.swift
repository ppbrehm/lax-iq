import SwiftUI

struct SignupScreen: View {
    var onSwitchToLogin: () -> Void

    @EnvironmentObject var appState: AppState

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var loading = false
    @State private var error = ""
    @State private var confirmationSent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("🥍").font(.system(size: 48))

                if confirmationSent {
                    Text("Check Your Email").font(.system(size: 26, weight: .heavy))
                    Text("We sent a confirmation link to \(email). Confirm it, then come back and sign in.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)

                    Button(action: onSwitchToLogin) {
                        Text("Back to Sign In")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(red: 0, green: 0.48, blue: 1))
                            .cornerRadius(14)
                    }
                    .padding(.top, 8)
                } else {
                    Text("Join Your Team").font(.system(size: 28, weight: .heavy))
                    Text("You must be invited by your coach or team administrator to sign up.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
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

                    labeledField("Your Email", placeholder: "coach@example.com", text: $email, keyboard: .emailAddress, autocap: .never)

                    labeledSecureField("Password", placeholder: "At least 6 characters", text: $password)

                    labeledSecureField("Confirm Password", placeholder: "Repeat your password", text: $confirmPassword)

                    Button {
                        Task { await handleSignup() }
                    } label: {
                        if loading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign Up").font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0, green: 0.48, blue: 1))
                    .cornerRadius(14)
                    .disabled(loading)
                    .opacity(loading ? 0.6 : 1)
                    .padding(.top, 4)

                    Button(action: onSwitchToLogin) {
                        Text("Already have an account? ")
                            .foregroundColor(.gray)
                        + Text("Sign in →")
                            .foregroundColor(Color(red: 0, green: 0.48, blue: 1))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                }
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.1), radius: 24, x: 0, y: 8)
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
        .background(Color(white: 0.95))
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func labeledField(_ label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .sentences) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.3))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(autocap)
                .keyboardType(keyboard)
                .padding(12)
                .background(Color(white: 0.98))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.4), lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private func labeledSecureField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: 0.3))
            SecureField(placeholder, text: text)
                .padding(12)
                .background(Color(white: 0.98))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.4), lineWidth: 1.5))
        }
    }

    private func handleSignup() async {
        error = ""

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        if trimmedEmail.isEmpty { error = "Please enter an email."; return }
        if password.count < 6 { error = "Password must be at least 6 characters."; return }
        if password != confirmPassword { error = "Passwords don't match."; return }

        loading = true

        do {
            var hasInvite = trimmedEmail == ownerEmail
            if !hasInvite {
                hasInvite = try await appState.checkInvite(email: trimmedEmail) != nil
            }
            guard hasInvite else {
                error = "This email hasn't been invited. Ask your coach or team administrator to invite you first."
                loading = false
                return
            }

            _ = try await supabase.auth.signUp(email: trimmedEmail, password: password)
            confirmationSent = true
        } catch {
            self.error = error.localizedDescription
        }

        loading = false
    }
}
