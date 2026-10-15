import Foundation

struct GameStatsRoute: Hashable {
    let gameId: String
    let backLabel: String
    let readOnly: Bool
}

struct WhiteboardRoute: Hashable {
    let playId: String
}

struct PlayerStatsRoute: Hashable {
    let firstName: String
    let lastName: String
    let number: String?
}
