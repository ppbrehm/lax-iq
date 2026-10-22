import SwiftUI

struct TeamManagementScreen: View {
    @EnvironmentObject var appState: AppState
    let userId: String
    var onSignOut: () -> Void

    @State private var showDeleteConfirm = false
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.currentTeam?.name ?? "").font(.system(size: 20, weight: .heavy))
                    Text(appState.currentRole == "head_coach" ? "👑 Head Coach" : "🏃 Assistant Coach")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(white: 0.9))
                        .cornerRadius(999)
                }
                .padding(.vertical, 4)
            }

            Section {
                if appState.currentRole == "head_coach" {
                    NavigationLink("📧 Invite User") {
                        InviteUserScreen(userId: userId)
                    }
                }
                NavigationLink("📅 Schedule") {
                    ScheduleScreen(isReadOnly: false)
                }
                NavigationLink("👥 Roster") {
                    RosterScreen(isReadOnly: false)
                }
            }

            Section {
                Button("Sign Out", action: onSignOut)
                    .foregroundColor(.red)
            }

            Section {
                Button("Delete Account") {
                    showDeleteConfirm = true
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
        .overlay {
            if showDeleteConfirm {
                deleteAccountConfirm
            }
        }
        .alert("Error", isPresented: Binding(
            get: { !appState.errorMessage.isEmpty },
            set: { if !$0 { appState.errorMessage = "" } }
        )) {
            Button("OK") { appState.errorMessage = "" }
        } message: {
            Text(appState.errorMessage)
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
                Text("This permanently deletes your login and removes you from \(appState.currentTeam?.name ?? "your team"). This can't be undone.")
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

struct InviteUserScreen: View {
    @EnvironmentObject var appState: AppState
    let userId: String

    @State private var inviteEmail = ""
    @State private var inviting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invite an assistant coach to join your team. They'll be able to sign up once invited.")
                .foregroundColor(.gray)

            TextField("Assistant coach's email", text: $inviteEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .padding(12)
                .background(Color(white: 0.98))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.4), lineWidth: 1.5))

            Button(inviting ? "Sending..." : "Send Invite") {
                Task {
                    inviting = true
                    await appState.inviteAssistantCoach(email: inviteEmail, userId: userId)
                    inviting = false
                    if appState.errorMessage.isEmpty {
                        inviteEmail = ""
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inviting || inviteEmail.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .padding()
        .navigationTitle("Invite User")
        .alert("Error", isPresented: Binding(
            get: { !appState.errorMessage.isEmpty },
            set: { if !$0 { appState.errorMessage = "" } }
        )) {
            Button("OK") { appState.errorMessage = "" }
        } message: {
            Text(appState.errorMessage)
        }
    }
}
