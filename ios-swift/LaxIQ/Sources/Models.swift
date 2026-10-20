import Foundation

struct Team: Codable, Identifiable {
    let id: String
    let name: String
}

struct TeamInsert: Codable {
    let name: String
}

struct TeamMember: Codable, Identifiable {
    let id: String
    let role: String
    let user_id: String
    let created_at: String
}

struct TeamMemberInsert: Codable {
    let team_id: String
    let user_id: String
    let role: String
}

struct InviteCheckResult: Codable {
    let team_id: String
    let role: String
}

struct InvitedEmailInsert: Codable {
    let email: String
    let team_id: String
    let role: String
    let invited_by: String?
}

struct InviteClaim: Codable {
    let claimed_by: String
    let claimed_at: String
}

struct RosterPlayer: Codable, Identifiable {
    let id: String
    let number: String?
    let firstName: String
    let lastName: String
    let position: String?

    enum CodingKeys: String, CodingKey {
        case id, number
        case firstName = "first_name"
        case lastName = "last_name"
        case position
    }
}

struct RosterPlayerInsert: Codable {
    let number: String
    let first_name: String
    let last_name: String
    let position: String
    let team_id: String
}

let statHeaders = [
    "Shots", "SOG", "Goals", "Shot%", "Assists", "TO",
    "FO Att", "FO Win", "FO%",
    "GB", "CT",
    "SA", "SAOG", "GA", "Saves", "Save%",
]

enum StatIndex {
    static let shots = 0, sog = 1, goals = 2, shotPct = 3, assists = 4, turnovers = 5
    static let foAtt = 6, foWin = 7, foPct = 8
    static let gb = 9, ct = 10
    static let sa = 11, saog = 12, ga = 13, saves = 14, savePct = 15
}

// Games are stored as "M/d/yyyy" but every display in the app should read m/d/yy.
let usDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d/yyyy"
    return f
}()

private let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "M/d/yy"
    return f
}()

func shortDate(_ dateString: String) -> String {
    guard let date = usDateFormatter.date(from: dateString) else { return dateString }
    return shortDateFormatter.string(from: date)
}

func formatSeconds(_ total: Int) -> String {
    let s = max(0, total)
    return "\(s / 60):\(String(format: "%02d", s % 60))"
}

// Standard high school/college quarter length. Adjust here if your league plays shorter/longer quarters.
let quarterLengthSec = 12 * 60

func formatTimeLeft(elapsedSec: Int) -> String {
    formatSeconds(max(0, quarterLengthSec - elapsedSec))
}

func quarterLabel(_ quarter: Int) -> String {
    quarter >= 5 ? "OT" : "Q\(quarter)"
}

// Short letter codes for the Pos column in stats tables — long stick middies and
// faceoff specialists get their own code since they play very differently from a
// regular middie, even though positionGroup() above lumps them together.
func positionAbbreviation(_ position: String?) -> String {
    let p = (position ?? "").lowercased()
    if p.isEmpty { return "—" }
    if p.contains("goalie") { return "G" }
    if p.contains("long stick") || p.contains("lsm") { return "LS" }
    if p.contains("face off") || p.contains("faceoff") || p.contains("fogo") { return "FO" }
    if p.contains("middie") || p.contains("midfield") { return "M" }
    if p.contains("attack") { return "A" }
    if p.contains("defense") { return "D" }
    return String(p.prefix(1)).uppercased()
}

func positionGroup(_ position: String?) -> String {
    let p = (position ?? "").lowercased()
    if p.contains("goalie") { return "Goalie" }
    if p.contains("middie") || p.contains("midfield") || p.contains("face off") || p.contains("faceoff") || p.contains("long stick") {
        return "Middie"
    }
    if p.contains("attack") { return "Attack" }
    if p.contains("defense") { return "Defense" }
    return "Other"
}

private let positionGroupOrder = ["Attack": 0, "Middie": 1, "Defense": 2, "Goalie": 3, "Other": 4]

func positionGroupRank(_ position: String?) -> Int {
    positionGroupOrder[positionGroup(position)] ?? 4
}

func calculateTotalStats(_ stats: [[Int]]) -> [Int] {
    var totals = Array(repeating: 0, count: statHeaders.count)
    for row in stats {
        for i in row.indices where ![StatIndex.shotPct, StatIndex.foPct, StatIndex.savePct, StatIndex.saog].contains(i) {
            totals[i] += row[i]
        }
    }
    totals[StatIndex.shotPct] = totals[StatIndex.shots] > 0 ? Int((Double(totals[StatIndex.goals]) / Double(totals[StatIndex.shots]) * 100).rounded()) : 0
    totals[StatIndex.foPct] = totals[StatIndex.foAtt] > 0 ? Int((Double(totals[StatIndex.foWin]) / Double(totals[StatIndex.foAtt]) * 100).rounded()) : 0
    totals[StatIndex.saog] = totals[StatIndex.ga] + totals[StatIndex.saves]
    totals[StatIndex.savePct] = totals[StatIndex.saog] > 0 ? Int((Double(totals[StatIndex.saves]) / Double(totals[StatIndex.saog]) * 100).rounded()) : 0
    return totals
}

struct GamePlayerRow: Codable, Identifiable {
    let id: String
    let first_name: String
    let last_name: String
    let number: String?
    let position: String?
    var shots: Int?
    var shots_on_goal: Int?
    var goals: Int?
    var assists: Int?
    var turnovers: Int?
    var faceoff_attempts: Int?
    var faceoff_wins: Int?
    var ground_balls: Int?
    var caused_turnovers: Int?
    var shots_against: Int?
    var shots_against_on_goal: Int?
    var goals_against: Int?
    var saves: Int?
    var player_time_sec: Int?
    var player_in: Bool?
    var current_stint_sec: Int?

    var stats: [Int] {
        [
            shots ?? 0, shots_on_goal ?? 0, goals ?? 0, 0,
            assists ?? 0, turnovers ?? 0,
            faceoff_attempts ?? 0, faceoff_wins ?? 0, 0,
            ground_balls ?? 0, caused_turnovers ?? 0,
            shots_against ?? 0, shots_against_on_goal ?? 0,
            goals_against ?? 0, saves ?? 0, 0,
        ]
    }
}

struct GameRow: Codable {
    let id: String
    let date: String
    let opponent: String
    let location: String?
    let timer_running: Bool?
    let timer_elapsed_sec: Int?
    let quarter: Int?
    let status: String?
    let game_players: [GamePlayerRow]
}

struct Game: Identifiable {
    let id: String
    var date: String
    var opponent: String
    var location: String
    var timerRunning: Bool
    var timerElapsedSec: Int
    var quarter: Int
    var status: String
    var players: [GamePlayerRow]
    var stats: [[Int]]
    var playerTimesSec: [Int]
    var playerIn: [Bool]
    var playerStintSec: [Int]

    var ourScore: Int { stats.reduce(0) { $0 + $1[StatIndex.goals] } }
    // Opponent goals are recorded via the goalie's GA (Goals Against) stat rather
    // than a separately-adjusted counter, same as our own score comes from Goals.
    var opponentScore: Int { stats.reduce(0) { $0 + $1[StatIndex.ga] } }

    init(row: GameRow) {
        id = row.id
        date = row.date
        opponent = row.opponent
        location = row.location ?? "home"
        timerRunning = row.timer_running ?? false
        timerElapsedSec = row.timer_elapsed_sec ?? 0
        quarter = row.quarter ?? 1
        status = row.status ?? "scheduled"
        players = row.game_players
        stats = row.game_players.map { $0.stats }
        playerTimesSec = row.game_players.map { $0.player_time_sec ?? 0 }
        playerIn = row.game_players.map { $0.player_in ?? false }
        playerStintSec = row.game_players.map { $0.current_stint_sec ?? 0 }
    }
}

struct GameInsert: Codable {
    let date: String
    let opponent: String
    let location: String
    let team_id: String
}

struct GamePlayerInsert: Codable {
    let game_id: String
    let first_name: String
    let last_name: String
    let number: String?
    let position: String?
}

struct PlayPiece: Codable, Identifiable, Equatable {
    let id: String
    var x: Double
    var y: Double
    var side: String
    var playerType: String?
    // "us" or "opponent" — drives color, independent of `side`/position, so a
    // defensive or faceoff play can color-code by team even when both teams have
    // the same position on the field (e.g. two FOs). Optional/nil (rather than a
    // required field defaulting to "us") so plays saved before this existed still
    // decode fine and just render as "us".
    var team: String?
}

struct PlayPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

struct PlayAction: Codable, Identifiable, Equatable {
    let id: String
    var type: String
    var points: [PlayPoint]
    // Same "us"/"opponent" color-coding as PlayPiece.team — optional/nil so plays
    // saved before this existed still decode fine and render as "us" (black).
    var team: String?
}

struct Play: Codable, Identifiable {
    let id: String
    let name: String
    let field_type: String
    var pieces: [PlayPiece]?
    var actions: [PlayAction]?
    var formation: String?
}

struct PlayInsert: Codable {
    let name: String
    let field_type: String
    let pieces: [PlayPiece]
    let actions: [PlayAction]
    let team_id: String
    let formation: String?
}

struct PlayUpdate: Codable {
    let field_type: String
    let pieces: [PlayPiece]
    let actions: [PlayAction]
    let formation: String?
}

