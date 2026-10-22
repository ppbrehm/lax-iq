import SwiftUI

// Entry point for "Game Hub" on the home screen. Pick a game, then land on
// either the real-time head-coach dashboard or the assistant coach's stat
// input screen, depending on the signed-in user's role.
struct GameHubPickerScreen: View {
    @EnvironmentObject var appState: AppState
    // Lets Game Hub's own back button bypass this picker (and the Home screen's
    // whole nav stack in between) and pop straight back to Home in one step.
    var onExitToHome: () -> Void

    // Game awaiting the "Start Game?" confirmation (shown here, on the picker,
    // before ever pushing into Game Hub / Stat Input), and the Bool-driven
    // destination for the confirmed game — the same stable pattern GameHubScreen
    // already uses for its own Whiteboard push (an item-based destination here
    // caused the stack to bounce back under frequent Realtime-driven re-renders).
    @State private var pendingGame: Game?
    @State private var confirmedGameId: String?
    @State private var navigate = false
    // Only one game can be live at once — if the coach taps a different game while
    // another is still in_progress, this holds that live game (for the Finish/Reset
    // prompt) and the game they were actually trying to select, resumed once
    // they've resolved the conflict one way or the other.
    @State private var conflictingLiveGame: Game?
    @State private var pendingSelection: Game?
    // Set right after confirming "Start Game" — drives the full-screen countdown
    // before actually navigating into Game Hub, so starting a game feels like an event.
    @State private var countdownGameId: String?
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

    // The game the coach is most likely here for: the live one if a game is
    // already in progress, otherwise the next scheduled game up on the calendar.
    // Highlighted green in the list so it's obvious what's ready to start.
    private var currentGameId: String? {
        if let live = sortedGames.first(where: { $0.status == "in_progress" }) {
            return live.id
        }
        return sortedGames.first(where: { $0.status == "scheduled" })?.id
    }

    private func rowBackground(_ game: Game) -> Color {
        if game.id == currentGameId {
            return Color.green.opacity(0.22)
        }
        return game.status == "completed" ? Color(white: 0.9) : Color.white
    }

    // Cumulative W-L-T through each completed game, in schedule (chronological) order.
    private var runningRecords: [String: (wins: Int, losses: Int, ties: Int)] {
        seasonRunningRecords(sortedGames)
    }

    var body: some View {
        Group {
            if sortedGames.isEmpty {
                Text("No games yet. Add games in the Schedule screen.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                List(Array(sortedGames.enumerated()), id: \.element.id) { offset, game in
                    Button {
                        selectGame(game)
                    } label: {
                        GameRowView(game: game, gameNumber: offset + 1, record: runningRecords[game.id], cardColor: rowBackground(game))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
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
                    GameHubScreen(
                        gameId: confirmedGameId, onSwitchToStatsInput: { forcedScreen = .statsInput },
                        onExitToHome: onExitToHome
                    )
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
        .overlay {
            if let conflictingLiveGame {
                liveGameConflictPrompt(conflictingLiveGame)
            }
        }
        .overlay {
            if let countdownGameId, let game = appState.games.first(where: { $0.id == countdownGameId }) {
                GameStartCountdownOverlay(
                    gameNumber: (sortedGames.firstIndex(where: { $0.id == countdownGameId }) ?? 0) + 1,
                    teamName: appState.currentTeam?.name ?? "Us",
                    opponent: game.opponent,
                    isHome: game.location == "home"
                ) {
                    confirmedGameId = countdownGameId
                    navigate = true
                    self.countdownGameId = nil
                }
            }
        }
        .task { await appState.loadGames() }
    }

    private func selectGame(_ game: Game) {
        // A completed game is read-only (stats as they were), so it can't actually
        // conflict with a live game — only starting/resuming another game can.
        if game.status != "completed",
           let live = appState.games.first(where: { $0.status == "in_progress" && $0.id != game.id }) {
            conflictingLiveGame = live
            pendingSelection = game
        } else {
            proceedWithSelection(game)
        }
    }

    private func proceedWithSelection(_ game: Game) {
        if game.status == "scheduled" {
            pendingGame = game
        } else {
            confirmedGameId = game.id
            navigate = true
        }
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
                            countdownGameId = gameId
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

    // Only one game can be live at a time, so picking a different game while one is
    // still in_progress blocks here until the coach finishes or resets it.
    private func liveGameConflictPrompt(_ live: Game) -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { cancelLiveGameConflict() }

            VStack(spacing: 16) {
                Text("Game vs \(live.opponent) is still live")
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Only one game can be live at a time. Finish it or reset it back to scheduled before starting another.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        Task {
                            await appState.finishGame(gameId: live.id)
                            resumePendingSelection()
                        }
                    } label: {
                        Text("Finish Game")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(10)
                    }

                    Button {
                        Task {
                            await appState.resetGameToScheduled(gameId: live.id)
                            resumePendingSelection()
                        }
                    } label: {
                        Text("Reset to Scheduled")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }

                    Button {
                        cancelLiveGameConflict()
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
            .frame(width: 340)
            .background(Color(white: 0.98))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    private func cancelLiveGameConflict() {
        conflictingLiveGame = nil
        pendingSelection = nil
    }

    private func resumePendingSelection() {
        conflictingLiveGame = nil
        guard let pendingSelection else { return }
        self.pendingSelection = nil
        proceedWithSelection(pendingSelection)
    }
}

// Full-screen "3...2...1...GO!" countdown shown right after confirming Start
// Game, before actually navigating into Game Hub — makes kicking off a game
// feel like an event instead of an instant screen swap.
struct GameStartCountdownOverlay: View {
    let gameNumber: Int
    let teamName: String
    let opponent: String
    let isHome: Bool
    var onFinished: () -> Void

    @State private var count = 3
    @State private var showGo = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("Game \(gameNumber): \(teamName) \(isHome ? "vs" : "at") \(opponent)")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)

                Text(showGo ? "GO!" : "\(count)")
                    .font(.system(size: 140, weight: .black, design: .rounded))
                    .foregroundColor(showGo ? .green : .white)
                    .scaleEffect(pulse ? 1.15 : 0.85)
                    .shadow(color: (showGo ? Color.green : Color.white).opacity(0.6), radius: 30)
            }
        }
        .task {
            for n in [3, 2, 1] {
                count = n
                pulse = false
                withAnimation(.easeOut(duration: 0.15)) { pulse = true }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            showGo = true
            pulse = false
            withAnimation(.easeOut(duration: 0.2)) { pulse = true }
            try? await Task.sleep(nanoseconds: 600_000_000)
            onFinished()
        }
    }
}

// Shared tabular row for every schedule list (Game Hub's picker and the Home
// screen's read-only Schedule): Game, Date, Opponent (with a home/away badge
// beside it), Result, Record — no column headers, so each cell is self-
// labeled enough to read on its own. Lives in a rounded "card" rather than a
// plain list row.
struct GameRowView: View {
    let game: Game
    var gameNumber: Int? = nil
    // Our own team's cumulative record through this game — kept in its own
    // column, away from the opponent's name, so it doesn't read as theirs.
    var record: (wins: Int, losses: Int, ties: Int)? = nil
    var cardColor: Color = Color(white: 0.96)

    private let gameWidth: CGFloat = 68
    private let dateWidth: CGFloat = 72
    private let recordWidth: CGFloat = 62

    var body: some View {
        let isHome = game.location == "home"
        HStack(spacing: 12) {
            if let gameNumber {
                Text("Game \(gameNumber)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: gameWidth, alignment: .leading)
            }

            Text(shortDate(game.date))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: dateWidth, alignment: .leading)

            HStack(spacing: 8) {
                Text(isHome ? game.opponent : "@ \(game.opponent)")
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(isHome ? "HOME" : "AWAY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(isHome ? Color.blue : Color.orange)
                    .cornerRadius(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GameStatusBadge(game: game)
                .frame(width: 100, alignment: .leading)

            Text(record.map(seasonRecordLabel) ?? "—")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: recordWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(cardColor)
        .cornerRadius(14)
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
                return ("T  \(score)", .black)
            }
        default:
            return nil
        }
    }

    var body: some View {
        if let config {
            Text(config.text)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(config.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(config.color.opacity(0.12))
                .cornerRadius(999)
        }
    }
}
