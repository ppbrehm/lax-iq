import SwiftUI

private enum RosterSortColumn: Hashable {
    case number, name, position, stat(Int)
}

// What the Home screen's "Roster" tile opens directly: one row per player,
// season totals across every game, computed the same way PlayerStatsScreen
// does (matched by name + number since game_players is a per-game snapshot,
// not foreign-keyed to the roster). Tapping a row drills into that player's
// game-by-game breakdown. Every column header is tappable to sort.
struct RosterStatsScreen: View {
    @EnvironmentObject var appState: AppState

    @State private var sortColumn: RosterSortColumn = .position
    @State private var sortAscending = true

    private let numberWidth: CGFloat = 44
    private let nameWidth: CGFloat = 130
    private let positionWidth: CGFloat = 50
    private let statWidth: CGFloat = 64

    private var teamTotals: [Int] {
        calculateTotalStats(appState.games.flatMap { $0.stats })
    }

    private var rows: [(player: RosterPlayer, totals: [Int])] {
        let unsorted = appState.roster.map { player -> (player: RosterPlayer, totals: [Int]) in
            let matching = appState.games.flatMap { game in
                game.players.filter {
                    $0.first_name == player.firstName &&
                    $0.last_name == player.lastName &&
                    $0.number == player.number
                }
            }
            return (player, calculateTotalStats(matching.map { $0.stats }))
        }
        return unsorted.sorted { a, b in
            let result = isLess(a, b)
            return sortAscending ? result : !result
        }
    }

    private func isLess(_ a: (player: RosterPlayer, totals: [Int]), _ b: (player: RosterPlayer, totals: [Int])) -> Bool {
        switch sortColumn {
        case .number:
            return (Int(a.player.number ?? "") ?? Int.max) < (Int(b.player.number ?? "") ?? Int.max)
        case .name:
            let an = a.player.lastName.lowercased(), bn = b.player.lastName.lowercased()
            if an != bn { return an < bn }
            return a.player.firstName.lowercased() < b.player.firstName.lowercased()
        case .position:
            return positionGroupRank(a.player.position) < positionGroupRank(b.player.position)
        case .stat(let i):
            return a.totals[i] < b.totals[i]
        }
    }

    private func toggleSort(_ column: RosterSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    var body: some View {
        Group {
            if appState.roster.isEmpty {
                Text("No players in the roster yet.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        teamTotalsCard
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 0) {
                                headerRow
                                ForEach(rows, id: \.player.id) { entry in
                                    NavigationLink(value: PlayerStatsRoute(
                                        firstName: entry.player.firstName,
                                        lastName: entry.player.lastName,
                                        number: entry.player.number
                                    )) {
                                        playerRow(entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                }
            }
        }
        .navigationTitle("Roster Stats")
        .navigationDestination(for: PlayerStatsRoute.self) { route in
            PlayerStatsScreen(firstName: route.firstName, lastName: route.lastName, number: route.number)
        }
        .task {
            await appState.loadRoster()
            await appState.loadGames()
        }
    }

    private var teamTotalsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Team Totals").font(.system(size: 15, weight: .bold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(Array(statHeaders.enumerated()), id: \.offset) { i, header in
                    let value = teamTotals[i]
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

    private func sortHeaderButton(_ title: String, column: RosterSortColumn, width: CGFloat, alignment: Alignment = .leading) -> some View {
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

    private var headerRow: some View {
        HStack(spacing: 0) {
            sortHeaderButton("#", column: .number, width: numberWidth)
            sortHeaderButton("Player", column: .name, width: nameWidth)
            sortHeaderButton("Pos", column: .position, width: positionWidth)
            ForEach(Array(statHeaders.enumerated()), id: \.offset) { i, header in
                sortHeaderButton(header, column: .stat(i), width: statWidth, alignment: .center)
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.secondary)
        .padding(.vertical, 8)
        .background(Color(white: 0.93))
    }

    private func playerRow(_ entry: (player: RosterPlayer, totals: [Int])) -> some View {
        HStack(spacing: 0) {
            Text(entry.player.number ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: numberWidth, alignment: .leading)

            Text("\(entry.player.lastName), \(entry.player.firstName)")
                .font(.system(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: nameWidth, alignment: .leading)

            Text(positionAbbreviation(entry.player.position))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: positionWidth, alignment: .leading)

            ForEach(Array(entry.totals.enumerated()), id: \.offset) { i, value in
                let isPct = [StatIndex.shotPct, StatIndex.foPct, StatIndex.savePct].contains(i)
                Text(isPct ? "\(value)%" : "\(value)")
                    .font(.system(size: 13))
                    .frame(width: statWidth)
            }
        }
        .foregroundColor(.primary)
        .padding(.vertical, 8)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(white: 0.9)), alignment: .bottom)
    }
}
