import SwiftUI

struct NoTeamScreen: View {
    @EnvironmentObject var appState: AppState
    var onSignOut: () -> Void

    @State private var showDeleteConfirm = false
    @State private var deleting = false

    var body: some View {
        ZStack {
            Color(white: 0.95).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("🥍").font(.system(size: 48))
                Text("Not Linked to a Team").font(.system(size: 24, weight: .heavy))
                Text("Your account isn't connected to a team yet. Ask your head coach or the app administrator to invite your email, then sign up again.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Button("Sign Out", action: onSignOut)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 16)

                Button("Delete Account") {
                    showDeleteConfirm = true
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
                .padding(.top, 4)
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.1), radius: 24, x: 0, y: 8)
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)

            if showDeleteConfirm {
                deleteAccountConfirm
            }
        }
    }

    // A plain centered card instead of the system confirmationDialog, which on
    // iPad renders as an arrowed popover anchored to the tapped row rather than
    // staying put in the middle of the screen.
    private var deleteAccountConfirm: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { if !deleting { showDeleteConfirm = false } }

            VStack(spacing: 16) {
                Text("Delete your account?")
                    .font(.system(size: 18, weight: .bold))
                Text("This permanently deletes your login. This can't be undone.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        deleting = true
                        Task {
                            let success = await appState.deleteAccount()
                            deleting = false
                            showDeleteConfirm = false
                            if success {
                                onSignOut()
                            }
                        }
                    } label: {
                        Text(deleting ? "Deleting..." : "Delete Account")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    .disabled(deleting)

                    Button {
                        showDeleteConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.93))
                            .cornerRadius(10)
                    }
                    .disabled(deleting)
                }
            }
            .padding(24)
            .frame(width: 320)
            .background(Color(white: 0.98))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }
}
