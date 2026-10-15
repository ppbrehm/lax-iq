import SwiftUI

// Entry point for "Game Hub" on the home screen. Pick a game, then land on
// either the real-time head-coach dashboard or the assistant coach's stat
// input screen, depending on the signed-in user's role.
struct GameHubPickerScreen: View {
    @EnvironmentObject var appState: AppState

    // Game awaiting the "Start Game?" confirmation (shown here, on the picker,
    // before ever pushing into Game Hub / Stat Input), and the Bool-driven
    // destination for the confirmed game — the same stable pattern GameHubScreen
    // already uses for its own Whiteboard push (an item-based destination here
    // caused the stack to bounce back under frequent Realtime-driven re-renders).
    @State private var pendingGame: Game?
    @State private var confirmedGameId: String?
    @State private var navigate = false
    // Overrides the default role-based screen choice below when the coach taps
    // "Go To Stats Input" / "Go to Game Hub" — switching flips this flag instead of
    // pushing a new stack entry, so back always pops directly to this picker in one
    // tap no matter how many times the coach switches between the two screens.
    @State private var forcedScreen: ForcedScreen?

    private enum ForcedScreen {
        case gameHub, statsInput
    }

    private var sortedGames: [Game] {
        appState.games.sorted {
            (usDateFormatter.date(from: $0.date) ?? .distantPast) <
            (usDateFormatter.date(from: $1.date) ?? .distantPast)
        }
    }

    var body: some View {
        Group {
            if sortedGames.isEmpty {
                Text("No games yet. Add games in the Schedule screen.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(sortedGames) { game in
                    Button {
                        if game.status == "scheduled" {
                            pendingGame = game
                        } else {
                            confirmedGameId = game.id
                            navigate = true
                        }
                    } label: {
                        GameRowView(game: game)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(game.location == "home" ? Color.blue.opacity(0.08) : Color.orange.opacity(0.08))
                }
            }
        }
        .navigationTitle("Game Hub")
        .navigationDestination(isPresented: $navigate) {
            if let confirmedGameId {
                // A finished game always lands on the read-only final-stats view
                // (with its own "Edit Stats" button), regardless of role — the
                // live dashboard/timer-owning flows only make sense pre-final.
                if appState.games.first(where: { $0.id == confirmedGameId })?.status == "completed" {
                    GameStatsScreen(gameId: confirmedGameId, backLabel: "← Back to Game Hub", readOnly: true)
                } else if forcedScreen == .statsInput || (forcedScreen == nil && appState.currentRole != "head_coach") {
                    GameStatsScreen(
                        gameId: confirmedGameId, backLabel: "← Back to Game Hub", readOnly: false,
                        onSwitchToGameHub: { forcedScreen = .gameHub }
                    )
                } else {
                    GameHubScreen(gameId: confirmedGameId, onSwitchToStatsInput: { forcedScreen = .statsInput })
                }
            }
        }
        .onChange(of: navigate) { _, isNavigating in
            // Timer ownership is claimed/released for the whole Game Hub <-> Stat
            // Input session here (not per sub-screen) — otherwise switching between
            // them tears down and never re-claims ownership, and the clock freezes.
            guard let confirmedGameId else { return }
            if isNavigating {
                if appState.games.first(where: { $0.id == confirmedGameId })?.status != "completed" {
                    appState.claimTimerOwnership(gameId: confirmedGameId)
                }
            } else {
                // Reset so the next game picked starts from the normal role-based default.
                forcedScreen = nil
                appState.releaseTimerOwnership(gameId: confirmedGameId)
            }
        }
        .overlay {
            if let pendingGame {
                startGameConfirm(pendingGame)
            }
        }
        .task { await appState.loadGames() }
    }

    // A plain centered card instead of the system confirmationDialog, which on
    // iPad renders as an arrowed popover anchored to the tapped row rather than
    // staying put in the middle of the screen.
    private func startGameConfirm(_ game: Game) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { pendingGame = nil }

            VStack(spacing: 16) {
                Text("Start this game?")
                    .font(.system(size: 18, weight: .bold))
                Text("This marks the game vs \(game.opponent) as in progress and updates the Schedule.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        let gameId = game.id
                        Task {
                            await appState.startGame(gameId: gameId)
                            confirmedGameId = gameId
                            navigate = true
                        }
                        pendingGame = nil
                    } label: {
                        Text("Start Game")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0, green: 0.48, blue: 1))
                            .cornerRadius(10)
                    }

                    Button {
                        pendingGame = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.93))
                            .cornerRadius(10)
                    }
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

struct GameRowView: View {
    let game: Game
    private let sideColumnWidth: CGFloat = 76

    var body: some View {
        let isHome = game.location == "home"
        HStack(spacing: 8) {
            Text(shortDate(game.date))
                .font(.system(size: 17, weight: .bold))
                .frame(width: sideColumnWidth, alignment: .leading)

            Text(game.opponent)
                .font(.system(size: 19, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .trailing, spacing: 4) {
                Text(isHome ? "HOME" : "AWAY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isHome ? Color.blue : Color.orange)
                    .cornerRadius(6)
                GameStatusBadge(game: game)
            }
            .frame(width: sideColumnWidth, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

struct GameStatusBadge: View {
    let game: Game

    private var config: (text: String, color: Color)? {
        switch game.status {
        case "in_progress":
            return ("🔴 Live", .red)
        case "completed":
            let score = "\(game.ourScore)-\(game.opponentScore)"
            if game.ourScore > game.opponentScore {
                return ("W  \(score)", .green)
            } else if game.ourScore < game.opponentScore {
                return ("L  \(score)", .red)
            } else {
                return ("T  \(score)", .gray)
            }
        default:
            return nil
        }
    }

    var body: some View {
        if let config {
            Text(config.text)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(config.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(config.color.opacity(0.12))
                .cornerRadius(999)
        }
    }
}
