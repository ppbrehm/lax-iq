import SwiftUI

struct TeamManagementScreen: View {
    @EnvironmentObject var appState: AppState
    let userId: String
    var onSignOut: () -> Void

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
        }
        .navigationTitle("Settings")
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
