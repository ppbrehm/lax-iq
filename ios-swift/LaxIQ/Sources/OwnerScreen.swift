import SwiftUI

struct OwnerScreen: View {
    @EnvironmentObject var appState: AppState
    let ownerId: String
    var onSignOut: () -> Void

    @State private var showCreateTeam = false
    @State private var teamName = ""
    @State private var headCoachEmail = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.allTeams.isEmpty {
                    Text("No teams yet. Create one to get started.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(appState.allTeams) { team in
                        Text(team.name)
                    }
                }
            }
            .navigationTitle("Owner: Teams")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out", action: onSignOut)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("+ New Team") { showCreateTeam = true }
                }
            }
            .task { await appState.loadAllTeams() }
            .sheet(isPresented: $showCreateTeam) {
                createTeamSheet
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
    }

    private var createTeamSheet: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Team Name (e.g. Westfield Varsity Boys)", text: $teamName)
                }
                Section("Head Coach") {
                    TextField("Head coach's email", text: $headCoachEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    Text("They'll be able to sign up with this email and become Head Coach of this team.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("New Team")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateTeam = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(creating ? "Creating..." : "Create") {
                        Task {
                            creating = true
                            await appState.createTeamAndInviteHeadCoach(
                                teamName: teamName, headCoachEmail: headCoachEmail, ownerId: ownerId
                            )
                            creating = false
                            if appState.errorMessage.isEmpty {
                                teamName = ""; headCoachEmail = ""
                                showCreateTeam = false
                            }
                        }
                    }
                    .disabled(creating)
                }
            }
        }
    }
}
