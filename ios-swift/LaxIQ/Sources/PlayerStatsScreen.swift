import SwiftUI

// Season-long view for a single roster player: shown when tapping into the
// Roster, mirroring how tapping into the Schedule shows a single game's stats.
// Matches game_players rows by name + number since they're snapshotted onto
// each game rather than foreign-keyed to the roster.
struct PlayerStatsScreen: View {
    @EnvironmentObject var appState: AppState
    let firstName: String
    let lastName: String
    let number: String?

    private var matchingRows: [(game: Game, player: GamePlayerRow)] {
        appState.games.compactMap { game in
            guard let player = game.players.first(where: {
                $0.first_name == firstName && $0.last_name == lastName && $0.number == number
            }) else { return nil }
            return (game, player)
        }
        .sorted {
            (usDateFormatter.date(from: $0.game.date) ?? .distantPast) <
            (usDateFormatter.date(from: $1.game.date) ?? .distantPast)
        }
    }

    private var seasonTotals: [Int] {
        calculateTotalStats(matchingRows.map { $0.player.stats })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if matchingRows.isEmpty {
                    Text("No game stats recorded yet for this player.")
                        .foregroundColor(.gray)
                } else {
                    statsCard(title: "Season Totals", values: seasonTotals)

                    ForEach(matchingRows, id: \.game.id) { entry in
                        gameCard(game: entry.game, player: entry.player)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("\(lastName), \(firstName)")
        .task { await appState.loadGames() }
    }

    private func gameCard(game: Game, player: GamePlayerRow) -> some View {
        let isHome = game.location == "home"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isHome ? game.opponent : "@ \(game.opponent)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isHome ? .blue : .orange)
                Spacer()
                Text(shortDate(game.date)).font(.system(size: 13)).foregroundColor(.gray)
            }
            statsGrid(calculateTotalStats([player.stats]))
        }
        .padding()
        .background(Color(white: 0.98))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.15)))
    }

    private func statsCard(title: String, values: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 15, weight: .bold))
            statsGrid(values)
        }
        .padding()
        .background(Color(white: 0.96))
        .cornerRadius(14)
    }

    private func statsGrid(_ values: [Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(Array(statHeaders.enumerated()), id: \.offset) { i, header in
                let value = values[i]
                let isPct = [StatIndex.shotPct, StatIndex.foPct, StatIndex.savePct].contains(i)
                VStack {
                    Text(header).font(.system(size: 10)).foregroundColor(.gray)
                    Text(isPct ? "\(value)%" : "\(value)").font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }
}
