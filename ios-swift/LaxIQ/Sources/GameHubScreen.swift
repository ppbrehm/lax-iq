import SwiftUI

// Quick-read stat columns per position group, per the coach's requested breakdown.
private func statColumns(for group: String) -> [(label: String, index: Int)] {
    switch group {
    case "Attack":
        return [("G", StatIndex.goals), ("A", StatIndex.assists), ("GB", StatIndex.gb)]
    case "Middie":
        return [("G", StatIndex.goals), ("A", StatIndex.assists), ("GB", StatIndex.gb), ("CT", StatIndex.ct)]
    case "Defense":
        return [("GB", StatIndex.gb), ("CT", StatIndex.ct)]
    case "Goalie":
        return [("SOG", StatIndex.saog), ("GA", StatIndex.ga)]
    default:
        return [("GB", StatIndex.gb)]
    }
}

// Real-time, read-only dashboard for a head coach. Never claims timer ownership —
// it just displays whatever the assistant coach's GameStatsScreen (the timer owner)
// pushes over Realtime.
struct GameHubScreen: View {
    @EnvironmentObject var appState: AppState
    let gameId: String
    // Switching screens is handled by the picker that owns this one's spot in the
    // nav stack (it just swaps which screen renders there) rather than this screen
    // pushing a new stack entry — so no matter how many times the coach flips
    // between Game Hub and Stat Input, back always pops directly to the picker.
    var onSwitchToStatsInput: () -> Void
    // Pops all the way back to Home (past the picker) once the coach confirms they
    // want to leave — this is the screen's own idea of "exiting Game Hub," not just
    // popping one level.
    var onExitToHome: () -> Void

    @State private var selectedPlay: Play?
    @State private var showWhiteboardConfirm = false
    @State private var navigateToWhiteboard = false
    @State private var showPlaybook = false
    @State private var showExitConfirm = false
    // The score card's content (fonts/padding) never changes, so its rendered
    // height is effectively fixed — the Playbook button is locked to the same
    // value instead of measuring it, to keep the two aligned at the top.
    private let scoreCardHeight: CGFloat = 84

    private let columnSpacing: CGFloat = 12
    // Width:height of the full field — matches MiniFieldView's own ratio, since the
    // sidebar width is derived from it (see `content`).
    private let fieldAspectRatio: CGFloat = 60.0 / 110.0
    private let nameWidth: CGFloat = 84
    private let totalTimeWidth: CGFloat = 42
    private let sinceTimeWidth: CGFloat = 42
    private let statColWidth: CGFloat = 28

    private var game: Game? { appState.games.first { $0.id == gameId } }

    var body: some View {
        Group {
            if let game {
                GeometryReader { geo in
                    content(game: game, totalSize: geo.size)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Game Hub")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showExitConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Go To Stats Input", action: onSwitchToStatsInput)
            }
        }
        .overlay {
            if showExitConfirm {
                exitConfirmDialog
            }
        }
        .lockLandscape()
        .navigationDestination(isPresented: $navigateToWhiteboard) {
            WhiteboardScreen(
                initialPlayId: selectedPlay?.id,
                onBack: { pieces, actions in
                    selectedPlay = Play(
                        id: selectedPlay?.id ?? "", name: selectedPlay?.name ?? "On the Board",
                        field_type: "full", pieces: pieces, actions: actions, formation: selectedPlay?.formation
                    )
                },
                quickSaveContext: game.map { (opponent: $0.opponent, date: shortDate($0.date)) }
            )
        }
        .overlay {
            if showPlaybook {
                playbookOverlay
            }
        }
        .task {
            await appState.loadGames()
            await appState.loadPlays()
            await appState.subscribeToGameUpdates(gameId: gameId)
        }
        .onDisappear {
            Task { await appState.unsubscribeFromGameUpdates() }
        }
    }

    private func content(game: Game, totalSize: CGSize) -> some View {
        // The HStack below is padded on every side — its children need to be sized
        // against the space actually left AFTER that padding, not the GeometryReader's
        // full, unpadded size, or every column (including the field) renders slightly
        // oversized and gets cut off at the trailing/bottom edge.
        let sidebarTrailingPadding: CGFloat = 12
        let horizontalPadding: CGFloat = 12 + 12 + sidebarTrailingPadding
        let verticalPadding: CGFloat = 2 + 12
        let availableWidth = totalSize.width - horizontalPadding
        let availableHeight = totalSize.height - verticalPadding

        // Sidebar width is derived from the field's own aspect ratio rather than a
        // fixed fraction of the screen — sized so the field, once it fills the space
        // below the Playbook button, comes out exactly as tall as that space (no
        // gap above it), which puts its top edge flush with the first KPI row.
        let sidebarInnerSpacing: CGFloat = 8
        let fieldContainerHeight = availableHeight - scoreCardHeight - sidebarInnerSpacing
        let sidebarWidth = fieldContainerHeight * fieldAspectRatio
        let contentWidth = availableWidth - sidebarWidth - columnSpacing
        let columnWidth = (contentWidth - columnSpacing) / 2

        return ZStack {
            HStack(alignment: .top, spacing: columnSpacing) {
                VStack(alignment: .leading, spacing: 12) {
                    titleBox(game: game, width: contentWidth)
                    teamStatsRow(game: game, width: contentWidth)

                    // Only the player columns scroll — the title/score card and team
                    // stats above stay fixed in place regardless of roster length. On
                    // Field and Bench also scroll independently of each other, and each
                    // box stretches to the bottom of the screen (minus padding) even
                    // when its roster is short enough not to need scrolling.
                    // No extra bottom padding here — the roster boxes' bottom edge
                    // should land exactly even with the field's bottom edge, and both
                    // columns are already sized off the same availableHeight.
                    HStack(alignment: .top, spacing: columnSpacing) {
                        playerColumnBox(title: "On Field", game: game, playing: true, width: columnWidth)
                        playerColumnBox(title: "Bench", game: game, playing: false, width: columnWidth)
                    }
                }
                .frame(height: availableHeight, alignment: .top)

                playCallsSidebar(width: sidebarWidth, height: availableHeight)
                    .padding(.trailing, sidebarTrailingPadding)
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture { showWhiteboardConfirm = false }

            // Field has its own tap gesture (sets showWhiteboardConfirm = true), which takes
            // priority over this ancestor-level tap, so repeated taps on the field keep the
            // popup up while a tap anywhere else dismisses it.
            if showWhiteboardConfirm {
                whiteboardConfirmPopup
                    .position(x: contentWidth - 110 - 24, y: totalSize.height / 2)
            }
        }
    }

    private var whiteboardConfirmPopup: some View {
        VStack(spacing: 12) {
            Text("Open the full Whiteboard?")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Cancel") { showWhiteboardConfirm = false }
                    .buttonStyle(.bordered)
                Button("Open") {
                    navigateToWhiteboard = true
                    showWhiteboardConfirm = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 220)
        .background(Color(white: 0.98))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }

    // A plain centered card instead of the system confirmationDialog, which on
    // iPad renders as an arrowed popover anchored to the Back button rather than
    // staying put in the middle of the screen.
    private var exitConfirmDialog: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showExitConfirm = false }

            VStack(spacing: 16) {
                Text("Exit Game Hub?")
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        showExitConfirm = false
                        onExitToHome()
                    } label: {
                        Text("Exit")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .cornerRadius(10)
                    }

                    Button {
                        showExitConfirm = false
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
            .frame(width: 300)
            .background(Color(white: 0.98))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    private func playCallsSidebar(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            openPlaybookButton
                .frame(height: scoreCardHeight)

            MiniFieldView(pieces: selectedPlay?.pieces ?? [], actions: selectedPlay?.actions ?? [])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { showWhiteboardConfirm = true }
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private var openPlaybookButton: some View {
        Button {
            showPlaybook = true
        } label: {
            Text("Playbook")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .background(Color(white: 0.93))
                .cornerRadius(10)
        }
    }

    // Sized to 75% of the screen, same as WhiteboardScreen's own Playbook overlay.
    private var playbookOverlay: some View {
        let screenSize = UIScreen.main.bounds.size
        return ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showPlaybook = false }

            PlaybookScreen(
                onSelect: { play in
                    selectedPlay = play
                    showPlaybook = false
                },
                onClose: { showPlaybook = false }
            )
            .environmentObject(appState)
            .frame(width: screenSize.width * 0.75, height: screenSize.height * 0.75)
            .background(Color(white: 0.98))
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20)
        }
    }

    private func teamStatsRow(game: Game, width: CGFloat) -> some View {
        let totals = calculateTotalStats(game.stats)
        let kpiWidth = (width - columnSpacing * 3) / 4
        let sogPct = totals[StatIndex.shots] > 0
            ? Int((Double(totals[StatIndex.sog]) / Double(totals[StatIndex.shots]) * 100).rounded())
            : 0
        let turnoverMargin = totals[StatIndex.ct] - totals[StatIndex.turnovers]

        return VStack(spacing: columnSpacing) {
            HStack(spacing: columnSpacing) {
                shootingKpiBox(
                    shotPct: totals[StatIndex.shotPct], sogPct: sogPct,
                    goals: totals[StatIndex.goals], sog: totals[StatIndex.sog], shots: totals[StatIndex.shots],
                    width: kpiWidth
                )
                kpiBox(
                    title: "Ground Balls", value: "\(totals[StatIndex.gb])", accent: .green,
                    subtitle: topLeaders(game: game, statIndex: StatIndex.gb),
                    width: kpiWidth
                )
                kpiBox(
                    title: "Save %", value: "\(totals[StatIndex.savePct])%", accent: .purple,
                    subtitle: ["Shots on Goal: \(totals[StatIndex.saog])", "Goals: \(totals[StatIndex.ga])"],
                    width: kpiWidth
                )
                kpiBox(
                    title: "Face Off Win %", value: "\(totals[StatIndex.foPct])%", accent: .orange,
                    subtitle: ["Face Offs: \(totals[StatIndex.foAtt])", "Wins: \(totals[StatIndex.foWin])"],
                    width: kpiWidth
                )
            }

            HStack(spacing: columnSpacing) {
                kpiBox(
                    title: "Turnover Margin", value: turnoverMargin >= 0 ? "+\(turnoverMargin)" : "\(turnoverMargin)",
                    accent: turnoverMargin >= 0 ? .green : .red,
                    subtitle: ["CT: \(totals[StatIndex.ct])", "TO: \(totals[StatIndex.turnovers])"],
                    width: kpiWidth
                )
                kpiBox(
                    title: "Top Scorers", value: "\(totals[StatIndex.goals])", accent: .blue,
                    subtitle: topLeaders(game: game, statIndex: StatIndex.goals),
                    width: kpiWidth
                )
                mostMinutesKpiBox(game: game, width: kpiWidth)
                kpiBox(
                    title: "Top Assists", value: "\(totals[StatIndex.assists])", accent: .pink,
                    subtitle: topLeaders(game: game, statIndex: StatIndex.assists),
                    width: kpiWidth
                )
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func topLeaders(game: Game, statIndex: Int, limit: Int = 3) -> [String] {
        let leaders = game.players.indices
            .map { (game.players[$0].last_name, game.stats[$0][statIndex]) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { "\($0.0) \($0.1)" }
        return leaders.isEmpty ? ["None yet"] : Array(leaders)
    }

    private func topMinutesLeaders(game: Game, onFieldOnly: Bool, limit: Int = 3) -> [String] {
        let leaders = game.players.indices
            .filter { !onFieldOnly || game.playerIn[$0] }
            .map { (game.players[$0].last_name, game.playerTimesSec[$0]) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { "\($0.0) \(formatSeconds($0.1))" }
        return leaders.isEmpty ? ["None yet"] : Array(leaders)
    }

    private func mostMinutesKpiBox(game: Game, width: CGFloat) -> some View {
        let totalLeaders = topMinutesLeaders(game: game, onFieldOnly: false)
        let onFieldLeaders = topMinutesLeaders(game: game, onFieldOnly: true)

        return kpiCard(accent: .teal, width: width) {
            VStack(spacing: 6) {
                Text("Most Minutes").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                HStack(alignment: .top, spacing: 16) {
                    minutesLeaderList(title: "Total", leaders: totalLeaders)
                    minutesLeaderList(title: "On Field", leaders: onFieldLeaders)
                }
            }
        }
    }

    private func minutesLeaderList(title: String, leaders: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
            ForEach(Array(leaders.enumerated()), id: \.offset) { i, line in
                Text(line)
                    .font(.system(size: i == 0 ? 12 : 10, weight: i == 0 ? .bold : .regular))
                    .foregroundColor(i == 0 ? .teal : .secondary)
            }
        }
    }

    // Fixed so every KPI box is identically sized regardless of how many subtitle
    // lines its content happens to have — sized off the tallest card (a 3-leader
    // list under a title + big value), with a small buffer.
    private let kpiCardHeight: CGFloat = 112

    private func kpiCard<Content: View>(accent: Color, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, 12)
            .frame(width: width, height: kpiCardHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color.white, accent.opacity(0.08)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent.opacity(0.25), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func kpiBox(title: String, value: String, accent: Color, subtitle: [String], width: CGFloat) -> some View {
        kpiCard(accent: accent, width: width) {
            VStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                VStack(spacing: 1) {
                    ForEach(subtitle, id: \.self) { line in
                        Text(line).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func shootingKpiBox(shotPct: Int, sogPct: Int, goals: Int, sog: Int, shots: Int, width: CGFloat) -> some View {
        kpiCard(accent: .blue, width: width) {
            VStack(spacing: 6) {
                Text("Shooting %").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                HStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Text("\(shotPct)%").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.blue)
                        Text("Shot%").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                    VStack(spacing: 0) {
                        Text("\(sogPct)%").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.blue)
                        Text("SOG%").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
                Text("Goals: \(goals)  SOG: \(sog)  Shots: \(shots)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func titleBox(game: Game, width: CGFloat) -> some View {
        // Home team always sits on the right, regardless of which side is ours —
        // the coach's own team renders in gray, the opponent in black, so it's
        // immediately clear which score belongs to whom without a home/away key.
        let isHome = game.location == "home"
        let ourName = appState.currentTeam?.name ?? "Us"
        let leftName = isHome ? game.opponent : ourName
        let rightName = isHome ? ourName : game.opponent
        let leftScore = isHome ? game.opponentScore : game.ourScore
        let rightScore = isHome ? game.ourScore : game.opponentScore
        let leftIsOurs = !isHome
        let rightIsOurs = isHome

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(leftName)
                    .foregroundColor(leftIsOurs ? .gray : .black)
                Text("\(leftScore)")
                Text("-")
                    .foregroundColor(.secondary)
                Text("\(rightScore)")
                Text(rightName)
                    .foregroundColor(rightIsOurs ? .gray : .black)
            }
            .font(.system(size: 26, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text("\(quarterLabel(game.quarter))   \(formatTimeLeft(elapsedSec: game.timerElapsedSec))")
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: scoreCardHeight, alignment: .center)
        .background(Color(white: 0.96))
        .cornerRadius(12)
    }

    // The rounded box itself is fixed-size (stretching to the bottom of the screen)
    // and owns the clipping/border, so its corners — especially the bottom ones —
    // stay put while only the roster content inside scrolls underneath them.
    private func playerColumnBox(title: String, game: Game, playing: Bool, width: CGFloat) -> some View {
        GeometryReader { columnGeo in
            ScrollView(showsIndicators: false) {
                playerColumn(title: title, game: game, playing: playing, width: width)
            }
            .frame(width: width, height: columnGeo.size.height)
            .background(Color(white: 0.98))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.15)))
        }
    }

    private func playerColumn(title: String, game: Game, playing: Bool, width: CGFloat) -> some View {
        let indices = game.players.indices.filter { game.playerIn[$0] == playing }
        let grouped = Dictionary(grouping: indices) { positionGroup(game.players[$0].position) }
        let presentGroups = ["Attack", "LSM", "Middie", "Defense", "Goalie"].filter { !(grouped[$0] ?? []).isEmpty }
        let sinceLabel = playing ? "Since In" : "Since Out"

        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(.gray)
            columnHeaderRow(sinceLabel: sinceLabel)

            ForEach(Array(presentGroups.enumerated()), id: \.element) { position, group in
                VStack(alignment: .leading, spacing: 2) {
                    groupHeaderRow(group: group)
                    ForEach(grouped[group] ?? [], id: \.self) { index in
                        playerRow(index: index, group: group, game: game, playing: playing)
                    }
                }

                if position < presentGroups.count - 1 {
                    Rectangle()
                        .fill(Color(white: 0.6))
                        .frame(height: 1)
                        .padding(.horizontal, 6)
                }
            }
        }
        .padding(8)
        .frame(width: width, alignment: .topLeading)
    }

    // "Total"/"Since In"/"Since Out" only need to appear once per column — they don't
    // vary by position group, unlike the stat abbreviations in groupHeaderRow below.
    private func columnHeaderRow(sinceLabel: String) -> some View {
        HStack(spacing: 4) {
            Text("").frame(width: nameWidth, alignment: .leading)
            Text("Total")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: totalTimeWidth, alignment: .leading)
            Text(sinceLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: sinceTimeWidth, alignment: .leading)
        }
    }

    private func groupHeaderRow(group: String) -> some View {
        HStack(spacing: 4) {
            Text(group)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: nameWidth, alignment: .leading)
            Spacer().frame(width: totalTimeWidth + sinceTimeWidth + 4)
            ForEach(statColumns(for: group), id: \.label) { col in
                Text(col.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: statColWidth)
            }
        }
    }

    private func playerRow(index: Int, group: String, game: Game, playing: Bool) -> some View {
        let player = game.players[index]
        let stats = game.stats[index]

        return HStack(spacing: 4) {
            Text("#\(player.number ?? "—") \(player.last_name)")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)

            Text(formatSeconds(game.playerTimesSec[index]))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: totalTimeWidth, alignment: .leading)

            Text(formatSeconds(game.playerStintSec[index]))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(playing ? .green : .gray)
                .frame(width: sinceTimeWidth, alignment: .leading)

            ForEach(statColumns(for: group), id: \.label) { col in
                Text("\(stats[col.index])")
                    .font(.system(size: 11))
                    .frame(width: statColWidth)
            }
        }
    }
}

// A read-only, scaled-to-fit rendering of a saved play on a full field — reuses the
// same field geometry (FieldLinesView/ArrowHead) as the Whiteboard.
private struct MiniFieldView: View {
    let pieces: [PlayPiece]
    let actions: [PlayAction]

    private let ratio = 60.0 / 110.0 // width:height for the full field

    private func fittedSize(available: CGSize) -> CGSize {
        let w = available.width
        let h = w / ratio
        if h > available.height {
            let h2 = available.height
            return CGSize(width: h2 * ratio, height: h2)
        }
        return CGSize(width: w, height: h)
    }

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(available: geo.size)

            ZStack {
                FieldLinesView(fieldType: "full", size: size)

                ForEach(actions) { action in
                    actionPath(action, size: size)
                }
                ForEach(pieces) { piece in
                    pieceView(piece, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.02, green: 0.47, blue: 0.34))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.98), lineWidth: 2))
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }

    private func actionPath(_ action: PlayAction, size: CGSize) -> some View {
        let isOpponent = (action.team ?? "us") == "opponent"
        let color: Color = isOpponent ? .black : Color.white.opacity(0.85)
        let absPoints = action.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        return ZStack {
            Path { path in
                guard let first = absPoints.first else { return }
                path.move(to: first)
                for pt in absPoints.dropFirst() { path.addLine(to: pt) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, dash: action.type == "pass" ? [8, 6] : []))

            if let last = absPoints.last, let secondLast = absPoints.dropLast().last {
                let angle = atan2(last.y - secondLast.y, last.x - secondLast.x)
                if action.type == "cut" || action.type == "pass" {
                    ArrowHead(angle: angle).fill(color).frame(width: 16, height: 16).position(last)
                } else if action.type == "pick" {
                    Rectangle().fill(color)
                        .frame(width: 18, height: 3)
                        .rotationEffect(.radians(angle + .pi / 2))
                        .position(last)
                }
            }
        }
    }

    private func pieceView(_ piece: PlayPiece, size: CGSize) -> some View {
        let isOpponent = (piece.team ?? "us") == "opponent"
        let label = piece.playerType ?? (isOpponent ? "O" : "X")
        let fillColor: Color = isOpponent ? .black : Color.white.opacity(0.85)
        let textColor: Color = isOpponent ? .white : Color(red: 0.07, green: 0.09, blue: 0.15)

        return Circle()
            .fill(fillColor)
            .frame(width: 24, height: 24)
            .overlay(
                Text(label)
                    .font(.system(size: label.count > 1 ? 10 : 13, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            )
            .position(x: piece.x * size.width, y: piece.y * size.height)
    }
}
