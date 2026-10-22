import Foundation
import Supabase

struct TeamMembership: Codable {
    let team_id: String
    let role: String
}

private struct GameRealtimeRow: Codable {
    let id: String
    let timer_running: Bool?
    let timer_elapsed_sec: Int?
    let quarter: Int?
    let status: String?
}

let ownerEmail = "ppbrehm@gmail.com"

@MainActor
final class AppState: ObservableObject {
    @Published var currentTeam: Team?
    @Published var currentRole: String?
    @Published var roster: [RosterPlayer] = []
    @Published var games: [Game] = []
    @Published var savedPlays: [Play] = []
    @Published var allTeams: [Team] = []
    @Published var loading = true
    @Published var errorMessage = ""
    // Lives here (not as local @State on the table) so it survives switching
    // between Stats Input and Game Hub, which recreates PlayerStatsTable.
    @Published var statsSortColumn: PlayerStatsSortColumn?
    @Published var statsSortAscending = true

    private var timer: Timer?
    private var gameChannel: RealtimeChannelV2?
    private var gameRealtimeSubscriptions: [RealtimeSubscription] = []

    // A cancelled in-flight request (e.g. the view that started it disappeared before
    // it finished) isn't a real failure — surfacing "Swift.CancellationError" to the
    // coach as an alert is just noise, so swallow it instead of setting errorMessage.
    private func setError(_ error: Error) {
        if error is CancellationError { return }
        errorMessage = error.localizedDescription
    }

    // Only the device that owns a game's timer (the assistant coach actively running
    // the game clock) ticks it locally and writes it to the DB. Other devices (e.g. a
    // head coach's Game Hub) just receive the synced value over Realtime.
    private var ownedTimerGameIds: Set<String> = []

    func claimTimerOwnership(gameId: String) {
        ownedTimerGameIds.insert(gameId)
    }

    func releaseTimerOwnership(gameId: String) {
        ownedTimerGameIds.remove(gameId)
    }

    // Looks up a membership for this user; if none exists yet, checks for an
    // unclaimed invite matching their email and joins + claims it. This covers
    // the gap between signUp (invite is checked then) and first confirmed login
    // (team_members row and invite claim actually happen here).
    func bootstrap(userId: String, email: String) async {
        loading = true
        do {
            let memberships: [TeamMembership] = try await supabase
                .from("team_members")
                .select("team_id, role")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value

            if let membership = memberships.first {
                let team: Team = try await supabase
                    .from("teams")
                    .select()
                    .eq("id", value: membership.team_id)
                    .single()
                    .execute()
                    .value

                currentTeam = team
                currentRole = membership.role
            } else if let invite = try await checkInvite(email: email) {
                try await supabase
                    .from("team_members")
                    .insert(TeamMemberInsert(team_id: invite.team_id, user_id: userId, role: invite.role))
                    .execute()

                try await supabase
                    .from("invited_emails")
                    .update(InviteClaim(claimed_by: userId, claimed_at: ISO8601DateFormatter().string(from: Date())))
                    .eq("team_id", value: invite.team_id)
                    .ilike("email", pattern: email)
                    .execute()

                let team: Team = try await supabase
                    .from("teams")
                    .select()
                    .eq("id", value: invite.team_id)
                    .single()
                    .execute()
                    .value

                currentTeam = team
                currentRole = invite.role
            }

            if currentTeam != nil {
                await loadRoster()
                await loadGames()
                await loadPlays()
                startTimerLoop()
            }
        } catch {
            setError(error)
        }
        loading = false
    }

    func checkInvite(email: String) async throws -> InviteCheckResult? {
        let results: [InviteCheckResult] = try await supabase
            .rpc("check_invite", params: ["p_email": email])
            .execute()
            .value
        return results.first
    }

    // MARK: - Owner

    func loadAllTeams() async {
        do {
            allTeams = try await supabase.from("teams").select().order("name").execute().value
        } catch {
            setError(error)
        }
    }

    func createTeamAndInviteHeadCoach(teamName: String, headCoachEmail: String, ownerId: String) async {
        let trimmedName = teamName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = headCoachEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            errorMessage = "Please enter both a team name and head coach email."
            return
        }

        do {
            let team: Team = try await supabase
                .from("teams")
                .insert(TeamInsert(name: trimmedName))
                .select()
                .single()
                .execute()
                .value

            try await supabase
                .from("invited_emails")
                .insert(InvitedEmailInsert(email: trimmedEmail, team_id: team.id, role: "head_coach", invited_by: ownerId))
                .execute()

            await loadAllTeams()
        } catch {
            setError(error)
        }
    }

    // MARK: - Team invites (head coach)

    func inviteAssistantCoach(email: String, userId: String) async {
        guard let teamId = currentTeam?.id else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Please enter an email."
            return
        }

        do {
            try await supabase
                .from("invited_emails")
                .insert(InvitedEmailInsert(email: trimmedEmail, team_id: teamId, role: "assistant_coach", invited_by: userId))
                .execute()
        } catch {
            setError(error)
        }
    }

    // Calls the delete_own_account() Postgres function (see
    // supabase_delete_account_migration.sql) — it removes this user's team
    // memberships and auth.users row server-side, since the client only ever
    // holds the anon key and can't delete an auth user directly. The caller
    // should only sign the device out if this returns true.
    func deleteAccount() async -> Bool {
        do {
            try await supabase.rpc("delete_own_account").execute()
            return true
        } catch {
            setError(error)
            return false
        }
    }

    func loadRoster() async {
        guard let teamId = currentTeam?.id else { return }
        do {
            let players: [RosterPlayer] = try await supabase
                .from("roster")
                .select()
                .eq("team_id", value: teamId)
                .order("created_at", ascending: false)
                .execute()
                .value
            roster = players
        } catch {
            setError(error)
        }
    }

    func addRosterPlayer(number: String, firstName: String, lastName: String, position: String) async {
        guard let teamId = currentTeam?.id,
              !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please fill in first and last name."
            return
        }

        let newPlayer = RosterPlayerInsert(
            number: number.trimmingCharacters(in: .whitespaces),
            first_name: firstName.trimmingCharacters(in: .whitespaces),
            last_name: lastName.trimmingCharacters(in: .whitespaces),
            position: position.trimmingCharacters(in: .whitespaces),
            team_id: teamId
        )

        do {
            try await supabase.from("roster").insert(newPlayer).execute()
            await loadRoster()
            await syncRosterToGamesWithoutPlayers()
        } catch {
            setError(error)
        }
    }

    func removeRosterPlayer(id: String) async {
        do {
            try await supabase.from("roster").delete().eq("id", value: id).execute()
            roster.removeAll { $0.id == id }
        } catch {
            setError(error)
        }
    }

    // Parsed rows: (number, lastName, firstName, position). Mirrors App.js's CSV import.
    func importRoster(rows: [(String, String, String, String)], overwrite: Bool) async {
        guard let teamId = currentTeam?.id else { return }

        do {
            if overwrite {
                try await supabase.from("roster").delete().eq("team_id", value: teamId).execute()
            }

            var toInsert = rows.map {
                RosterPlayerInsert(number: $0.0, first_name: $0.2, last_name: $0.1, position: $0.3, team_id: teamId)
            }

            if !overwrite {
                let existingKeys = Set(roster.map { "\($0.number ?? "")|\($0.lastName.lowercased())|\($0.firstName.lowercased())" })
                toInsert = toInsert.filter {
                    !existingKeys.contains("\($0.number)|\($0.last_name.lowercased())|\($0.first_name.lowercased())")
                }
            }

            guard !toInsert.isEmpty else {
                errorMessage = "No new players to add."
                return
            }

            try await supabase.from("roster").insert(toInsert).execute()
            await loadRoster()
            await syncRosterToGamesWithoutPlayers()
        } catch {
            setError(error)
        }
    }

    // Propagates the roster into any games that don't have players yet (e.g. created before roster existed).
    private func syncRosterToGamesWithoutPlayers() async {
        guard !roster.isEmpty else { return }
        let gamesWithoutPlayers = games.filter { $0.players.isEmpty }
        guard !gamesWithoutPlayers.isEmpty else { return }

        do {
            var allGamePlayers: [GamePlayerInsert] = []
            for game in gamesWithoutPlayers {
                allGamePlayers.append(contentsOf: roster.map {
                    GamePlayerInsert(game_id: game.id, first_name: $0.firstName, last_name: $0.lastName, number: $0.number, position: $0.position)
                })
            }
            try await supabase.from("game_players").insert(allGamePlayers).execute()
            await loadGames()
        } catch {
            setError(error)
        }
    }

    // MARK: - Games

    func loadGames() async {
        guard let teamId = currentTeam?.id else { return }
        do {
            let rows: [GameRow] = try await supabase
                .from("games")
                .select("*, game_players (*)")
                .eq("team_id", value: teamId)
                .order("created_at", ascending: false)
                .execute()
                .value
            games = rows.map(Game.init)
        } catch {
            setError(error)
        }
    }

    func createGame(year: String, month: String, day: String, opponent: String, location: String) async {
        guard let teamId = currentTeam?.id,
              !year.isEmpty, !month.isEmpty, !day.isEmpty,
              !opponent.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please fill in year, month, day, and opponent."
            return
        }

        let insert = GameInsert(
            date: "\(month)/\(day)/\(year)",
            opponent: opponent.trimmingCharacters(in: .whitespaces),
            location: location,
            team_id: teamId
        )

        do {
            struct GameIdRow: Codable { let id: String }
            let newGame: GameIdRow = try await supabase
                .from("games")
                .insert(insert)
                .select("id")
                .single()
                .execute()
                .value

            if !roster.isEmpty {
                let players = roster.map {
                    GamePlayerInsert(
                        game_id: newGame.id, first_name: $0.firstName, last_name: $0.lastName,
                        number: $0.number, position: $0.position
                    )
                }
                try await supabase.from("game_players").insert(players).execute()
            }

            await loadGames()
        } catch {
            setError(error)
        }
    }

    // Parsed rows: (year, month, day, opponent, location). Mirrors App.js's CSV import.
    func importGames(rows: [(String, String, String, String, String)], overwrite: Bool) async {
        guard let teamId = currentTeam?.id else { return }

        do {
            if overwrite {
                try await supabase.from("games").delete().eq("team_id", value: teamId).execute()
            }

            var toInsert = rows.map {
                GameInsert(date: "\($0.1)/\($0.2)/\($0.0)", opponent: $0.3, location: $0.4 == "away" ? "away" : "home", team_id: teamId)
            }

            if !overwrite {
                let existingKeys = Set(games.map { "\($0.date)|\($0.opponent.lowercased())" })
                toInsert = toInsert.filter { !existingKeys.contains("\($0.date)|\($0.opponent.lowercased())") }
            }

            guard !toInsert.isEmpty else {
                errorMessage = "No new games to add."
                return
            }

            struct GameIdRow: Codable { let id: String }
            let insertedGames: [GameIdRow] = try await supabase
                .from("games")
                .insert(toInsert)
                .select("id")
                .execute()
                .value

            if !roster.isEmpty {
                var allGamePlayers: [GamePlayerInsert] = []
                for game in insertedGames {
                    allGamePlayers.append(contentsOf: roster.map {
                        GamePlayerInsert(game_id: game.id, first_name: $0.firstName, last_name: $0.lastName, number: $0.number, position: $0.position)
                    })
                }
                try await supabase.from("game_players").insert(allGamePlayers).execute()
            }

            await loadGames()
        } catch {
            setError(error)
        }
    }

    private func updateGameInDb(gameId: String, updates: [String: AnyJSON]) async {
        do {
            try await supabase.from("games").update(updates).eq("id", value: gameId).execute()
        } catch {
            setError(error)
        }
    }

    private func updateGamePlayerInDb(playerId: String, updates: [String: AnyJSON]) async {
        do {
            try await supabase.from("game_players").update(updates).eq("id", value: playerId).execute()
        } catch {
            setError(error)
        }
    }

    // MARK: - Realtime (live game sync between devices, e.g. assistant coach logging stats -> head coach's Game Hub)

    func subscribeToGameUpdates(gameId: String) async {
        await unsubscribeFromGameUpdates()

        let channel = supabase.channel("game-\(gameId)")

        let playerSub = channel.onPostgresChange(
            UpdateAction.self, schema: "public", table: "game_players", filter: .eq("game_id", value: gameId)
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.applyRemoteGamePlayerUpdate(action, gameId: gameId)
            }
        }

        let gameSub = channel.onPostgresChange(
            UpdateAction.self, schema: "public", table: "games", filter: .eq("id", value: gameId)
        ) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.applyRemoteGameUpdate(action)
            }
        }

        gameRealtimeSubscriptions = [playerSub, gameSub]
        gameChannel = channel
        await channel.subscribe()
    }

    func unsubscribeFromGameUpdates() async {
        gameRealtimeSubscriptions = []
        if let gameChannel {
            await gameChannel.unsubscribe()
        }
        gameChannel = nil
    }

    private func applyRemoteGamePlayerUpdate(_ action: UpdateAction, gameId: String) {
        guard let updated = try? action.decodeRecord(as: GamePlayerRow.self, decoder: JSONDecoder()),
              let gIdx = games.firstIndex(where: { $0.id == gameId }),
              let pIdx = games[gIdx].players.firstIndex(where: { $0.id == updated.id }) else { return }

        games[gIdx].players[pIdx] = updated
        games[gIdx].stats[pIdx] = updated.stats
        games[gIdx].playerTimesSec[pIdx] = updated.player_time_sec ?? 0
        games[gIdx].playerIn[pIdx] = updated.player_in ?? false
        games[gIdx].playerStintSec[pIdx] = updated.current_stint_sec ?? 0
    }

    private func applyRemoteGameUpdate(_ action: UpdateAction) {
        guard let updated = try? action.decodeRecord(as: GameRealtimeRow.self, decoder: JSONDecoder()),
              let idx = games.firstIndex(where: { $0.id == updated.id }) else { return }

        if let running = updated.timer_running { games[idx].timerRunning = running }
        if let elapsed = updated.timer_elapsed_sec { games[idx].timerElapsedSec = elapsed }
        if let quarter = updated.quarter { games[idx].quarter = quarter }
        if let status = updated.status { games[idx].status = status }
    }

    // Marks a scheduled game as started — called after the user confirms via the
    // "Start Game" prompt in the Game Hub picker.
    func startGame(gameId: String) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }), games[idx].status == "scheduled" else { return }
        games[idx].status = "in_progress"
        await updateGameInDb(gameId: gameId, updates: ["status": .string("in_progress")])
    }

    // Manually closes out a live game without playing the clock to 0:00 — used when
    // the coach switches to a different game while this one's still in_progress,
    // since only one game can be live at a time.
    func finishGame(gameId: String) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].status = "completed"
        games[idx].timerRunning = false
        await updateGameInDb(gameId: gameId, updates: ["status": .string("completed"), "timer_running": .bool(false)])
    }

    // Reverts an in_progress game back to scheduled (e.g. it was started by mistake)
    // so it can be properly started again later — used in the same "only one game
    // can be live" conflict as finishGame above. This is a safety net for an edge
    // case that shouldn't come up in normal use (coaches aren't expected to open a
    // second game while one's live), so it fully wipes the game back to a blank
    // slate — stats, score (derived from stats), lineup, and clock — rather than
    // leaving partial data that could be mistaken for a fresh start.
    func resetGameToScheduled(gameId: String) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].status = "scheduled"
        games[idx].timerRunning = false
        games[idx].timerElapsedSec = 0
        games[idx].quarter = 1
        games[idx].playerTimesSec = games[idx].players.map { _ in 0 }
        games[idx].playerStintSec = games[idx].players.map { _ in 0 }
        games[idx].playerIn = games[idx].players.map { _ in false }
        games[idx].stats = games[idx].players.map { _ in Array(repeating: 0, count: statHeaders.count) }

        await updateGameInDb(gameId: gameId, updates: [
            "status": .string("scheduled"), "timer_running": .bool(false),
            "timer_elapsed_sec": .double(0), "quarter": .double(1),
        ])

        let zeroedPlayerUpdates: [String: AnyJSON] = [
            "player_time_sec": .double(0), "current_stint_sec": .double(0), "player_in": .bool(false),
            "shots": .double(0), "shots_on_goal": .double(0), "goals": .double(0),
            "assists": .double(0), "turnovers": .double(0),
            "faceoff_attempts": .double(0), "faceoff_wins": .double(0),
            "ground_balls": .double(0), "caused_turnovers": .double(0),
            "shots_against": .double(0), "shots_against_on_goal": .double(0),
            "goals_against": .double(0), "saves": .double(0),
        ]
        for player in games[idx].players {
            await updateGamePlayerInDb(playerId: player.id, updates: zeroedPlayerUpdates)
        }
    }

    func toggleGameTimer(gameId: String) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].timerRunning.toggle()
        await updateGameInDb(gameId: gameId, updates: ["timer_running": .bool(games[idx].timerRunning)])
    }

    func resetGameTimer(gameId: String) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].timerRunning = false
        games[idx].timerElapsedSec = 0
        games[idx].playerTimesSec = games[idx].players.map { _ in 0 }
        games[idx].playerStintSec = games[idx].players.map { _ in 0 }
        await updateGameInDb(gameId: gameId, updates: ["timer_running": .bool(false), "timer_elapsed_sec": .double(0)])
        for player in games[idx].players {
            await updateGamePlayerInDb(playerId: player.id, updates: ["player_time_sec": .double(0), "current_stint_sec": .double(0)])
        }
    }

    func setQuarter(gameId: String, quarter: Int) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].quarter = quarter
        games[idx].timerElapsedSec = 0
        await updateGameInDb(gameId: gameId, updates: ["quarter": .double(Double(quarter)), "timer_elapsed_sec": .double(0)])
    }

    func togglePlayerIn(gameId: String, index: Int) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        games[idx].playerIn[index].toggle()
        let nowIn = games[idx].playerIn[index]
        let player = games[idx].players[index]

        // Resets the player's "current stint" clock — tickTimers() below ticks it back up
        // every second the game clock is running, whether they're in or on the bench, so
        // Game Hub's "time since sub in/out" always reflects actual GAME time.
        games[idx].playerStintSec[index] = 0
        let updates: [String: AnyJSON] = ["player_in": .bool(nowIn), "current_stint_sec": .double(0)]
        await updateGamePlayerInDb(playerId: player.id, updates: updates)
    }

    private func startTimerLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickTimers()
            }
        }
    }

    private func tickTimers() {
        for idx in games.indices where games[idx].timerRunning && ownedTimerGameIds.contains(games[idx].id) {
            // Quarter is over — stop the clock here instead of letting it (and player time,
            // which ticks off this same loop) keep climbing past the displayed 0:00.
            guard games[idx].timerElapsedSec < quarterLengthSec else {
                games[idx].timerRunning = false
                var updates: [String: AnyJSON] = ["timer_running": .bool(false)]
                if games[idx].quarter >= 4 {
                    // Clock hit 0:00 in the 4th (or OT) quarter — the game is over.
                    if games[idx].status != "completed" {
                        games[idx].status = "completed"
                        updates["status"] = .string("completed")
                    }
                } else {
                    // Clock hit 0:00 in Q1-3 — move on to the next quarter automatically.
                    games[idx].quarter += 1
                    games[idx].timerElapsedSec = 0
                    updates["quarter"] = .double(Double(games[idx].quarter))
                    updates["timer_elapsed_sec"] = .double(0)
                }
                let gameId = games[idx].id
                Task { await updateGameInDb(gameId: gameId, updates: updates) }
                continue
            }
            games[idx].timerElapsedSec += 1
            for i in games[idx].playerIn.indices {
                games[idx].playerStintSec[i] += 1
                if games[idx].playerIn[i] {
                    games[idx].playerTimesSec[i] += 1
                }
            }
            if games[idx].timerElapsedSec % 5 == 0 {
                let gameId = games[idx].id
                let elapsed = games[idx].timerElapsedSec
                Task { await updateGameInDb(gameId: gameId, updates: ["timer_elapsed_sec": .double(Double(elapsed))]) }

                for (i, player) in games[idx].players.enumerated() {
                    let playerId = player.id
                    let stintSeconds = games[idx].playerStintSec[i]
                    var playerUpdates: [String: AnyJSON] = ["current_stint_sec": .double(Double(stintSeconds))]
                    if games[idx].playerIn[i] {
                        playerUpdates["player_time_sec"] = .double(Double(games[idx].playerTimesSec[i]))
                    }
                    Task { await updateGamePlayerInDb(playerId: playerId, updates: playerUpdates) }
                }
            }
        }
    }

    // Mirrors App.js's handleStatChange cascade rules (Goals -> SOG/Shots, SOG -> Shots, GA/Saves -> SAOG/SA).
    func handleStatChange(gameId: String, row: Int, col: Int, delta: Int) async {
        guard let idx = games.firstIndex(where: { $0.id == gameId }) else { return }
        var newStats = games[idx].stats[row]
        newStats[col] = max(0, newStats[col] + delta)

        // These always carry the same +1/-1 through to the broader stat they're
        // a subset of, on top of whatever's already been tapped directly there —
        // e.g. a faceoff win is still its own separate attempt even if attempts
        // was already bumped for an earlier loss, so it can't just raise a floor.
        if col == StatIndex.goals {
            newStats[StatIndex.sog] = max(0, newStats[StatIndex.sog] + delta)
            newStats[StatIndex.shots] = max(0, newStats[StatIndex.shots] + delta)
        }
        if col == StatIndex.sog {
            newStats[StatIndex.shots] = max(0, newStats[StatIndex.shots] + delta)
        }
        if col == StatIndex.foWin {
            newStats[StatIndex.foAtt] = max(0, newStats[StatIndex.foAtt] + delta)
        }
        if col == StatIndex.ga || col == StatIndex.saves {
            newStats[StatIndex.sa] = max(0, newStats[StatIndex.sa] + delta)
            newStats[StatIndex.saog] = newStats[StatIndex.ga] + newStats[StatIndex.saves]
        }

        games[idx].stats[row] = newStats

        let player = games[idx].players[row]
        var updates: [String: AnyJSON] = [:]
        let statNames: [Int: String] = [
            StatIndex.shots: "shots", StatIndex.sog: "shots_on_goal", StatIndex.goals: "goals",
            StatIndex.assists: "assists", StatIndex.turnovers: "turnovers",
            StatIndex.foAtt: "faceoff_attempts", StatIndex.foWin: "faceoff_wins",
            StatIndex.gb: "ground_balls", StatIndex.ct: "caused_turnovers",
            StatIndex.sa: "shots_against", StatIndex.ga: "goals_against", StatIndex.saves: "saves",
        ]
        if let name = statNames[col] {
            updates[name] = .double(Double(newStats[col]))
        }
        if col == StatIndex.goals || col == StatIndex.sog {
            updates["shots"] = .double(Double(newStats[StatIndex.shots]))
            updates["shots_on_goal"] = .double(Double(newStats[StatIndex.sog]))
        }
        if col == StatIndex.foWin {
            updates["faceoff_attempts"] = .double(Double(newStats[StatIndex.foAtt]))
        }
        if col == StatIndex.ga || col == StatIndex.saves {
            updates["shots_against_on_goal"] = .double(Double(newStats[StatIndex.saog]))
            updates["shots_against"] = .double(Double(newStats[StatIndex.sa]))
        }

        await updateGamePlayerInDb(playerId: player.id, updates: updates)
    }

    func handleGoalWithAssist(gameId: String, scorerIndex: Int, assistIndex: Int?) async {
        await handleStatChange(gameId: gameId, row: scorerIndex, col: StatIndex.goals, delta: 1)
        if let assistIndex {
            await handleStatChange(gameId: gameId, row: assistIndex, col: StatIndex.assists, delta: 1)
        }
    }

    // MARK: - Plays

    func loadPlays() async {
        guard let teamId = currentTeam?.id else { return }
        do {
            let plays: [Play] = try await supabase
                .from("plays")
                .select()
                .eq("team_id", value: teamId)
                .order("created_at", ascending: false)
                .execute()
                .value
            savedPlays = plays
        } catch {
            setError(error)
        }
    }

    func deletePlay(id: String) async {
        do {
            try await supabase.from("plays").delete().eq("id", value: id).execute()
            savedPlays.removeAll { $0.id == id }
        } catch {
            setError(error)
        }
    }

    @discardableResult
    func savePlay(name: String, fieldType: String, pieces: [PlayPiece], actions: [PlayAction], formation: String?) async -> Play? {
        guard let teamId = currentTeam?.id else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !(pieces.isEmpty && actions.isEmpty) else {
            errorMessage = "Enter a play name and add at least one player or movement first."
            return nil
        }

        do {
            let inserted: Play = try await supabase
                .from("plays")
                .insert(PlayInsert(name: trimmed, field_type: fieldType, pieces: pieces, actions: actions, team_id: teamId, formation: formation))
                .select()
                .single()
                .execute()
                .value
            savedPlays.append(inserted)
            return inserted
        } catch {
            setError(error)
            return nil
        }
    }

    @discardableResult
    func updatePlay(id: String, fieldType: String, pieces: [PlayPiece], actions: [PlayAction], formation: String?) async -> Bool {
        guard !(pieces.isEmpty && actions.isEmpty) else {
            errorMessage = "Add at least one player or movement before updating this play."
            return false
        }

        do {
            let updated: Play = try await supabase
                .from("plays")
                .update(PlayUpdate(field_type: fieldType, pieces: pieces, actions: actions, formation: formation))
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            if let idx = savedPlays.firstIndex(where: { $0.id == id }) {
                savedPlays[idx] = updated
            }
            return true
        } catch {
            setError(error)
            return false
        }
    }
}
