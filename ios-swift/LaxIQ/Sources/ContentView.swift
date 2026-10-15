import SwiftUI
import Supabase

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var session: Session?
    @State private var showSignup = false

    var body: some View {
        Group {
            if let session {
                let onSignOut: () -> Void = { Task { try? await supabase.auth.signOut() } }
                if appState.loading {
                    ProgressView("Loading...")
                } else if session.user.email?.lowercased() == ownerEmail {
                    OwnerScreen(ownerId: session.user.id.uuidString, onSignOut: onSignOut)
                        .environmentObject(appState)
                } else if appState.currentTeam == nil {
                    NoTeamScreen(onSignOut: onSignOut)
                        .environmentObject(appState)
                } else {
                    HomeScreen(userId: session.user.id.uuidString, onSignOut: onSignOut)
                        .environmentObject(appState)
                }
            } else if showSignup {
                SignupScreen(onSwitchToLogin: { showSignup = false })
                    .environmentObject(appState)
            } else {
                LoginScreen(onSwitchToSignup: { showSignup = true })
            }
        }
        .task {
            for await state in supabase.auth.authStateChanges {
                session = state.session
                if let user = state.session?.user, let email = user.email {
                    await appState.bootstrap(userId: user.id.uuidString, email: email)
                }
            }
        }
    }
}
