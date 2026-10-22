import SwiftUI

struct GameStatsScreen: View {
    @EnvironmentObject var appState: AppState
    let gameId: String
    var backLabel: String
    var readOnly: Bool
    // Nil when reached from the Schedule (no Game Hub to switch to there). When
    // reached from the Game Hub picker flow, calling this swaps which screen the
    // picker shows in place rather than pushing a new stack entry — so back always
    // pops directly to the picker no matter how many times the coach switches.
    var onSwitchToGameHub: (() -> Void)? = nil

    @State private var showAssistModal = false
    @State private var goalScorerIndex: Int?
    @State private var pendingQuarter: Int?
    @State private var editingStats = false

    private var game: Game? { appState.games.first { $0.id == gameId } }

    // readOnly stays true for a finished game viewed via this screen — no timer
    // section, no timer ownership — but the coach can tap "Edit Stats" to make
    // just the player stat cells editable without reopening the live Game Hub flow.
    private var statsEditable: Bool { !readOnly || editingStats }

    var body: some View {
        guard let game else { return AnyView(EmptyView()) }
        let isHome = game.location == "home"
        let totalStats = calculateTotalStats(game.stats)

        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                // For live stat input, the opponent/date move up into the nav bar
                // itself (see the .principal toolbar item below) so this block
                // doesn't eat space the stat table could use instead.
                if readOnly {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text(isHome ? game.opponent : "@ \(game.opponent)")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(isHome ? .blue : .orange)
                                if game.status == "completed" {
                                    Text("\(game.ourScore)-\(game.opponentScore) \(resultLetter(game))")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                            }
                            Text(shortDate(game.date)).font(.system(size: 14)).foregroundColor(.black)
                        }
                        Spacer()
                        if game.status == "completed" && !editingStats {
                            editStatsButton
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }

                // Live stat input is purely about collecting stats — skip the team
                // totals summary here so the roster table gets as much room as
                // possible; it's still shown once the game is final (readOnly).
                if readOnly {
                    totalsCard(totalStats: totalStats)
                        .padding(.horizontal)
                }

                if !readOnly {
                    timerSection(game: game)
                        .padding(.horizontal)
                        .padding(.top)
                }

                // Everything above this point (opponent/date, totals, timer) stays
                // fixed — only the roster table itself scrolls, so the team context
                // is always visible no matter how far down the roster the coach scrolls.
                if game.players.isEmpty {
                    Text("No players in this game. Go to the Roster screen to add players.")
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                } else {
                    ScrollView {
                        PlayerStatsTable(
                            game: game,
                            readOnly: !statsEditable,
                            lastNameOnly: !readOnly,
                            onToggleIn: { index in Task { await appState.togglePlayerIn(gameId: game.id, index: index) } },
                            onStatChange: { index, col, delta in
                                if col == StatIndex.goals, delta > 0, statsEditable {
                                    goalScorerIndex = index
                                    showAssistModal = true
                                } else {
                                    Task { await appState.handleStatChange(gameId: game.id, row: index, col: col, delta: delta) }
                                }
                            },
                            sortColumn: $appState.statsSortColumn,
                            sortAscending: $appState.statsSortAscending
                        )
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom)
            .navigationTitle(readOnly ? backLabel.replacingOccurrences(of: "← Back to ", with: "") : "Stats Input")
            .navigationBarTitleDisplayMode(.inline)
            .lockLandscape(if: !readOnly)
            // Reached from the live Game Hub picker flow (not the Schedule, and not
            // a finished game's read-only view) — Back goes to the Game Hub field
            // view instead of popping out of the Game Hub flow entirely.
            .navigationBarBackButtonHidden(onSwitchToGameHub != nil)
            .toolbar {
                if let onSwitchToGameHub {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: onSwitchToGameHub) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                    }
                }
                // Only offer a path into Game Hub when we arrived from Game Hub /
                // Stat Input in the first place — not from the Schedule, and not
                // for a finished game (no live dashboard to switch to either way).
                if let onSwitchToGameHub, game.status != "completed" {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Go to Game Hub", action: onSwitchToGameHub)
                    }
                }
            }
            .onAppear {
                // Sort state is shared (AppState) so it survives switching between
                // Stats Input and Game Hub during a live game — but for a completed
                // game's read-only view, each fresh visit should start back at the
                // default position-order sort rather than remembering a past visit's
                // custom sort.
                if readOnly {
                    appState.statsSortColumn = nil
                    appState.statsSortAscending = true
                }
            }
            .task {
                await appState.loadGames()
                await appState.subscribeToGameUpdates(gameId: gameId)
            }
            .onDisappear {
                // Timer ownership for this game is claimed/released by the Game Hub
                // picker for the whole Game Hub <-> Stat Input session, not here —
                // otherwise switching to Game Hub would release it and freeze the
                // clock, since nothing else picks ownership back up.
                Task { await appState.unsubscribeFromGameUpdates() }
            }
            .sheet(isPresented: $showAssistModal) {
                assistSheet(game: game)
            }
            .alert("Switch to \(quarterLabel(pendingQuarter ?? 0))?", isPresented: Binding(
                get: { pendingQuarter != nil },
                set: { if !$0 { pendingQuarter = nil } }
            )) {
                Button("Switch Quarter", role: .destructive) {
                    if let newQuarter = pendingQuarter {
                        Task { await appState.setQuarter(gameId: game.id, quarter: newQuarter) }
                    }
                    pendingQuarter = nil
                }
                Button("Cancel") { pendingQuarter = nil }
            } message: {
                Text("There's still \(formatTimeLeft(elapsedSec: game.timerElapsedSec)) left in \(quarterLabel(game.quarter)). Switching now will reset the clock to 12:00.")
            }
        )
    }

    private func resultLetter(_ game: Game) -> String {
        if game.ourScore > game.opponentScore { return "W" }
        if game.ourScore < game.opponentScore { return "L" }
        return "T"
    }

    private var editStatsButton: some View {
        Button {
            editingStats = true
        } label: {
            Text("✏️ Edit Stats")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0, green: 0.48, blue: 1))
                .cornerRadius(10)
        }
    }

    private func selectQuarter(_ newQuarter: Int, game: Game) {
        guard newQuarter != game.quarter else { return }
        let timeRemaining = quarterLengthSec - game.timerElapsedSec
        if timeRemaining > 0 {
            pendingQuarter = newQuarter
        } else {
            Task { await appState.setQuarter(gameId: game.id, quarter: newQuarter) }
        }
    }

    private func timerSection(game: Game) -> some View {
        let isHome = game.location == "home"

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isHome ? game.opponent : "@ \(game.opponent)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(isHome ? .blue : .orange)
                Text(shortDate(game.date)).font(.system(size: 17)).foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { quarter in
                    Button("Q\(quarter)") { selectQuarter(quarter, game: game) }
                        .buttonStyle(.bordered)
                        .tint(quarter == game.quarter ? .blue : .gray)
                        .frame(width: 50)
                }
                Button("OT") { selectQuarter(5, game: game) }
                    .buttonStyle(.bordered)
                    .tint(game.quarter >= 5 ? .blue : .gray)
                    .frame(width: 50)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 14) {
                Text(formatTimeLeft(elapsedSec: game.timerElapsedSec))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))

                VStack(spacing: 6) {
                    Button(game.timerRunning ? "Running" : "Start") {
                        Task { await appState.toggleGameTimer(gameId: game.id) }
                    }
                    .disabled(game.timerRunning)
                    .buttonStyle(.borderedProminent)
                    .tint(game.timerRunning ? .gray : .green)
                    .controlSize(.small)

                    Button("Stop") {
                        Task { await appState.toggleGameTimer(gameId: game.id) }
                    }
                    .disabled(!game.timerRunning)
                    .buttonStyle(.borderedProminent)
                    .tint(game.timerRunning ? .red : .gray)
                    .controlSize(.small)

                    Button("Reset") {
                        Task { await appState.resetGameTimer(gameId: game.id) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(width: 80)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(white: 0.96))
        .cornerRadius(14)
    }

    private func totalsCard(totalStats: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Team Totals").font(.system(size: 15, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(Array(statHeaders.enumerated()), id: \.offset) { i, header in
                    let value = totalStats[i]
                    let isPct = [StatIndex.shotPct, StatIndex.foPct, StatIndex.savePct].contains(i)
                    VStack {
                        Text(header).font(.system(size: 10)).foregroundColor(.gray)
                        Text(isPct ? "\(value)%" : "\(value)").font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
        .padding()
        .background(Color(white: 0.96))
        .cornerRadius(14)
    }

    private func assistSheet(game: Game) -> some View {
        NavigationStack {
            List {
                Button("No Assist (Unassisted Goal)") {
                    completeGoal(game: game, assistIndex: nil)
                }
                ForEach(Array(game.players.enumerated()), id: \.element.id) { index, player in
                    if index != goalScorerIndex, game.playerIn[index] {
                        Button("#\(player.number ?? "—") \(player.last_name)") {
                            completeGoal(game: game, assistIndex: index)
                        }
                    }
                }
            }
            .navigationTitle("Who assisted?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAssistModal = false; goalScorerIndex = nil }
                }
            }
        }
    }

    private func completeGoal(game: Game, assistIndex: Int?) {
        guard let scorerIndex = goalScorerIndex else { return }
        Task { await appState.handleGoalWithAssist(gameId: game.id, scorerIndex: scorerIndex, assistIndex: assistIndex) }
        showAssistModal = false
        goalScorerIndex = nil
    }
}

private struct StatGroup {
    let name: String
    let columns: [Int]
}

// The editable stat columns, clustered into related groups (excludes computed rate
// fields like Shot%/FO%/Save%/SAOG) — grouping + dividers make it easier to scan to the
// right stat quickly instead of hunting across 12 flat columns.
private let statGroups: [StatGroup] = [
    StatGroup(name: "Shooting", columns: [StatIndex.shots, StatIndex.sog, StatIndex.goals]),
    StatGroup(name: "Playmaking", columns: [StatIndex.assists, StatIndex.turnovers]),
    StatGroup(name: "Faceoff", columns: [StatIndex.foAtt, StatIndex.foWin]),
    StatGroup(name: "Ground Game", columns: [StatIndex.gb, StatIndex.ct]),
    StatGroup(name: "Goalie", columns: [StatIndex.sa, StatIndex.ga, StatIndex.saves]),
]

enum PlayerStatsSortColumn: Hashable {
    case number, name, position, stat(Int)
}

private struct PlayerStatsTable: View {
    let game: Game
    let readOnly: Bool
    // True only for the live Stats Input flow (not a completed game, whether
    // viewed read-only or under "Edit Stats") — shows just the last name there
    // to keep the whole table on-screen with no horizontal scrolling. Every
    // other roster/stats view keeps "Last, First".
    var lastNameOnly: Bool = false
    var onToggleIn: (Int) -> Void
    var onStatChange: (Int, Int, Int) -> Void
    // Bound to AppState rather than local @State — this table is recreated every
    // time the coach switches between Stats Input and Game Hub, so local state
    // would silently reset the sort each time. AppState lives for the whole
    // session, so the sort sticks until the coach picks a different one.
    @Binding var sortColumn: PlayerStatsSortColumn?
    @Binding var sortAscending: Bool

    private let numberWidth: CGFloat = 30
    private var nameWidth: CGFloat { lastNameOnly ? 74 : 120 }
    private let positionWidth: CGFloat = 36
    private let toggleWidth: CGFloat = 40
    private let toggleTimeGapWidth: CGFloat = 10
    private let timeWidth: CGFloat = 54
    private let statWidth: CGFloat = 100
    private let groupDividerWidth: CGFloat = 12

    // Nobody's been subbed in yet — true right when a game is first started,
    // before in/out status means anything.
    private var gameJustStarted: Bool {
        !game.playerIn.contains(true)
    }

    // On-field players always come first, no matter what the coach sorts by —
    // the table is for managing who's in during the game, so in/out status
    // takes priority over any column sort, which only orders within each group.
    //
    // Exception: with no column picked, a completed game (viewing past stats)
    // or a game that was just started has no meaningful in/out state to group
    // by, so the default instead falls back to plain position order —
    // Attack, LSM, Middie, Defense, Goalie.
    private var sortedIndices: [Int] {
        if sortColumn == nil && (readOnly || gameJustStarted) {
            return game.players.indices.sorted { a, b in
                let rankA = positionGroupRank(game.players[a].position)
                let rankB = positionGroupRank(game.players[b].position)
                if rankA != rankB { return rankA < rankB }
                return (Int(game.players[a].number ?? "") ?? Int.max) < (Int(game.players[b].number ?? "") ?? Int.max)
            }
        }

        return game.players.indices.sorted { a, b in
            let aIn = game.playerIn[a]
            let bIn = game.playerIn[b]
            if aIn != bIn { return aIn }

            if let sortColumn {
                let result = isLess(a, b, column: sortColumn)
                return sortAscending ? result : !result
            }

            let numberA = Int(game.players[a].number ?? "") ?? Int.max
            let numberB = Int(game.players[b].number ?? "") ?? Int.max

            if aIn {
                let rankA = positionGroupRank(game.players[a].position)
                let rankB = positionGroupRank(game.players[b].position)
                if rankA != rankB { return rankA < rankB }
                return numberA < numberB
            }

            // Smaller stint = subbed out more recently (the stint clock resets to 0
            // on every sub). Bench players who've never been in at all are all tied
            // at 0 here — without tiebreakers that tie falls back to raw roster/DB
            // order, which looked like a shuffle every time the in/out state
            // changed. Position, then number, keeps it stable instead.
            let stintA = game.playerStintSec[a], stintB = game.playerStintSec[b]
            if stintA != stintB { return stintA < stintB }
            let rankA = positionGroupRank(game.players[a].position)
            let rankB = positionGroupRank(game.players[b].position)
            if rankA != rankB { return rankA < rankB }
            return numberA < numberB
        }
    }

    private func isLess(_ a: Int, _ b: Int, column: PlayerStatsSortColumn) -> Bool {
        switch column {
        case .number:
            return (Int(game.players[a].number ?? "") ?? Int.max) < (Int(game.players[b].number ?? "") ?? Int.max)
        case .name:
            let an = game.players[a].last_name.lowercased(), bn = game.players[b].last_name.lowercased()
            if an != bn { return an < bn }
            return game.players[a].first_name.lowercased() < game.players[b].first_name.lowercased()
        case .position:
            return positionGroupRank(game.players[a].position) < positionGroupRank(game.players[b].position)
        case .stat(let i):
            return game.stats[a][i] < game.stats[b][i]
        }
    }

    private func toggleSort(_ column: PlayerStatsSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                groupNameRow
                columnHeaderRow
                ForEach(sortedIndices, id: \.self) { index in
                    playerRow(index: index, player: game.players[index])
                }
                .animation(.easeInOut(duration: 0.35), value: sortedIndices)
            }
        }
    }

    private var leadingColumnsWidth: CGFloat {
        numberWidth + nameWidth + positionWidth + (readOnly ? 0 : toggleWidth + toggleTimeGapWidth + timeWidth)
    }

    // Lighter shades of gray only, alternating per stat group so it's easy to tell
    // where one group's columns end and the next begins.
    private func groupColor(_ i: Int) -> Color {
        i % 2 == 0 ? Color(white: 0.95) : Color(white: 0.90)
    }

    private var groupNameRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: leadingColumnsWidth)
            ForEach(Array(statGroups.enumerated()), id: \.offset) { i, group in
                Text(group.name)
                    .frame(width: CGFloat(group.columns.count) * statWidth, alignment: .center)
                    .background(groupColor(i))
                if i < statGroups.count - 1 {
                    Color.clear.frame(width: groupDividerWidth)
                }
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.secondary)
    }

    private func sortHeaderButton(_ title: String, column: PlayerStatsSortColumn, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Button {
            toggleSort(column)
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            sortHeaderButton("#", column: .number, width: numberWidth)
            sortHeaderButton("Player", column: .name, width: nameWidth)
            sortHeaderButton("Pos", column: .position, width: positionWidth)
            if !readOnly {
                Text("In").frame(width: toggleWidth)
                Color.clear.frame(width: toggleTimeGapWidth)
                Text("Time").frame(width: timeWidth)
            }
            ForEach(Array(statGroups.enumerated()), id: \.offset) { i, group in
                HStack(spacing: 0) {
                    ForEach(group.columns, id: \.self) { col in
                        sortHeaderButton(statHeaders[col], column: .stat(col), width: statWidth, alignment: .center)
                    }
                }
                .background(groupColor(i))
                if i < statGroups.count - 1 {
                    groupDivider
                }
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.gray)
        .padding(.bottom, 8)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(Color(white: 0.85))
            .frame(width: 1)
            .padding(.horizontal, groupDividerWidth / 2)
    }

    private func playerRow(index: Int, player: GamePlayerRow) -> some View {
        HStack(spacing: 0) {
            Text(player.number ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: numberWidth, alignment: .leading)

            Text(lastNameOnly ? player.last_name : "\(player.last_name), \(player.first_name)")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)

            Text(positionAbbreviation(player.position))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: positionWidth, alignment: .leading)

            if !readOnly {
                Toggle("", isOn: Binding(get: { game.playerIn[index] }, set: { _ in onToggleIn(index) }))
                    .labelsHidden()
                    .frame(width: toggleWidth)
                Color.clear.frame(width: toggleTimeGapWidth)
                Text(formatSeconds(game.playerTimesSec[index]))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: timeWidth)
            }

            ForEach(Array(statGroups.enumerated()), id: \.offset) { i, group in
                HStack(spacing: 0) {
                    ForEach(group.columns, id: \.self) { col in
                        statCell(index: index, col: col, editable: !readOnly && game.playerIn[index])
                    }
                }
                .background(groupColor(i))
                if i < statGroups.count - 1 {
                    groupDivider
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func statCell(index: Int, col: Int, editable: Bool) -> some View {
        Group {
            if !editable {
                Text("\(game.stats[index][col])")
                    .font(.system(size: 15, weight: .semibold))
            } else {
                HStack(spacing: 4) {
                    stepperButton(symbol: "−", color: .red) { onStatChange(index, col, -1) }
                    Text("\(game.stats[index][col])")
                        .font(.system(size: 17, weight: .bold))
                        .frame(minWidth: 26)
                    stepperButton(symbol: "+", color: .green) { onStatChange(index, col, 1) }
                }
            }
        }
        .frame(width: statWidth)
    }

    private func stepperButton(symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
