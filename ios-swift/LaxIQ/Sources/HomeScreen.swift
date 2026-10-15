import SwiftUI
import UIKit

struct HomeScreen: View {
    @EnvironmentObject var appState: AppState
    let userId: String
    var onSignOut: () -> Void

    // Sized off the third-width tile (the tightest fit, from the Schedule/Roster/
    // Settings row), so every tile's label uses the same font size and it scales
    // with screen size (iPhone vs iPad).
    private var tileFontSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let outerPadding: CGFloat = 32
        let columnSpacing: CGFloat = 16
        let thirdTileWidth = (screenWidth - outerPadding - columnSpacing * 2) / 3
        return min(max(thirdTileWidth * 0.12, 15), 30)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("LaxIQ").font(.system(size: 32, weight: .heavy))

                    VStack(spacing: 24) {
                        tile(id: "gameHub", icon: "📊", label: "Game Hub", minHeight: 90)

                        tile(id: "playDesign", icon: "✏️", label: "Whiteboard", minHeight: 90)

                        HStack(spacing: 16) {
                            tile(id: "schedule", icon: "📅", label: "Schedule")
                            tile(id: "roster", icon: "👥", label: "Roster")
                            tile(id: "teamManagement", icon: "⚙️", label: "Settings")
                        }
                    }
                }
                .padding()
            }
            .navigationDestination(for: String.self) { tileId in
                destination(for: tileId)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out", action: onSignOut)
                }
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

    private func tile(id: String, icon: String, label: String, minHeight: CGFloat = 100) -> some View {
        NavigationLink(value: id) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: tileFontSize, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(icon).font(.system(size: 36))
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding()
            .background(Color(white: 0.98))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2)))
        }
    }

    @ViewBuilder
    private func destination(for tileId: String) -> some View {
        switch tileId {
        case "roster":
            RosterStatsScreen()
        case "gameHub":
            GameHubPickerScreen()
        case "schedule":
            ScheduleScreen(isReadOnly: true)
        case "teamManagement":
            TeamManagementScreen(userId: userId, onSignOut: onSignOut)
        case "playDesign":
            WhiteboardScreen(initialPlayId: nil)
        default:
            VStack(spacing: 12) {
                Text("🚧").font(.system(size: 48))
                Text("Not ported yet").font(.headline)
                Text("This screen still needs to be rebuilt in Swift.")
                    .foregroundColor(.gray)
            }
        }
    }
}
