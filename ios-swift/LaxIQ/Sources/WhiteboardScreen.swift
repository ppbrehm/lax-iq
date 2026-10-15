import SwiftUI

// Positioned in the attacking box near the bottom goal of the full field
// (restraining line at y=0.6818, crease/goal line at y=0.8636, end line at y=1.0).
// Coordinates follow laxgoalierat.com's descriptions of each set (restraining line at
// y=0.6818, goal/crease line at y=0.8636, end line at y=1.0 on the attacking half).
private let formations: [String: [(x: Double, y: Double, type: String)]] = [
    // 1 middie up top, 2 wing middies + 2 crease attackmen in the middle, 1 attackman behind (X).
    "1-4-1": [
        (0.5, 0.700, "OM"),
        (0.22, 0.819, "OM"), (0.78, 0.819, "OM"),
        (0.38, 0.819, "A"), (0.62, 0.819, "A"),
        (0.5, 0.925, "A"),
    ],
    // 2 middies up top, 1 middie + 1 attackman in the middle, 2 attackmen behind (X).
    "2-2-2": [
        (0.35, 0.700, "OM"), (0.65, 0.700, "OM"),
        (0.35, 0.819, "OM"), (0.65, 0.819, "A"),
        (0.35, 0.925, "A"), (0.65, 0.925, "A"),
    ],
    // 1 middie up top, 2 wing middies + 1 crease attackman in the middle, 2 attackmen behind (X).
    "2-3-1": [
        (0.5, 0.700, "OM"),
        (0.25, 0.819, "OM"), (0.5, 0.819, "A"), (0.75, 0.819, "OM"),
        (0.35, 0.925, "A"), (0.65, 0.925, "A"),
    ],
    // 2 middies up top + 1 crease middie in the middle, 2 wing attackmen in the middle, 1 attackman behind (X).
    "1-3-2": [
        (0.35, 0.700, "OM"), (0.65, 0.700, "OM"),
        (0.25, 0.819, "A"), (0.5, 0.819, "OM"), (0.75, 0.819, "A"),
        (0.5, 0.925, "A"),
    ],
    // 3 middies up top, 3 attackmen on the crease line, nobody behind the goal.
    "3-3": [
        (0.25, 0.700, "OM"), (0.5, 0.700, "OM"), (0.75, 0.700, "OM"),
        (0.25, 0.818, "A"), (0.5, 0.818, "A"), (0.75, 0.818, "A"),
    ],
    // 1 middie up top, 2 high-middle + 2 low-middle on the wheel, 1 attackman behind (X).
    "Open Set": [
        (0.5, 0.700, "OM"),
        (0.25, 0.742, "OM"), (0.75, 0.742, "OM"),
        (0.3, 0.819, "A"), (0.7, 0.819, "A"),
        (0.5, 0.925, "A"),
    ],
    // 3 middies up top (umbrella), 1 crease attackman, 2 attackmen behind (X).
    "2-1-3": [
        (0.25, 0.700, "OM"), (0.5, 0.700, "OM"), (0.75, 0.700, "OM"),
        (0.5, 0.819, "A"),
        (0.35, 0.925, "A"), (0.65, 0.925, "A"),
    ],
]

private func newId() -> String { UUID().uuidString }

private struct PositionOption {
    let label: String
    let code: String
    let side: String
}

private let positionOptions: [PositionOption] = [
    PositionOption(label: "Attack", code: "A", side: "offense"),
    PositionOption(label: "Offensive Middie", code: "OM", side: "offense"),
    PositionOption(label: "Face Off", code: "FO", side: "offense"),
    PositionOption(label: "Middie", code: "M", side: "offense"),
    PositionOption(label: "Defensive Middie", code: "DM", side: "defense"),
    PositionOption(label: "Long Stick Middie", code: "LS", side: "defense"),
    PositionOption(label: "Defense", code: "D", side: "defense"),
    PositionOption(label: "Goalie", code: "G", side: "defense"),
]

struct WhiteboardScreen: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var initialPlayId: String?

    @State private var fieldType = "full"
    // Nil until the coach picks something from the Position or Action dropdown —
    // no piece/line can be placed on the field before one of those is chosen.
    @State private var playMode: String?
    @State private var pieces: [PlayPiece] = []
    @State private var actions: [PlayAction] = []
    @State private var drawingAction: PlayAction?
    @State private var selectedFormation: String?

    // Playbook: browse saved plays grouped by formation, drop the chosen one on the
    // field, then either overwrite it (Update) or save the edited board as a new play.
    @State private var loadedPlay: Play?
    @State private var updating = false
    @State private var showUpdateConfirm = false
    @State private var showPlaybook = false

    @State private var dragStart: [String: CGPoint] = [:]
    @State private var fieldDragStartLocation: CGPoint?
    @State private var history: [(pieces: [PlayPiece], actions: [PlayAction])] = []

    @State private var showSaveModal = false
    @State private var playNameInput = ""
    @State private var saving = false

    @State private var pendingFieldType: String?
    @State private var showFieldSwitchConfirm = false
    @State private var switchFieldAfterSave = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                ipadLayout
            } else {
                phoneLayout
            }
        }
        .padding()
        .navigationTitle(loadedPlay?.name ?? "Whiteboard")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await appState.loadPlays()
            if let initialPlayId, let play = appState.savedPlays.first(where: { $0.id == initialPlayId }) {
                loadFromPlaybook(play)
            }
        }
        .sheet(isPresented: $showSaveModal) {
            saveModal
        }
        .overlay {
            if showPlaybook {
                playbookOverlay
            }
        }
        .confirmationDialog(
            "Save this play before switching fields? Switching will clear the board.",
            isPresented: $showFieldSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("Save Play") {
                switchFieldAfterSave = true
                playNameInput = ""
                showSaveModal = true
            }
            Button("Don't Save", role: .destructive) {
                applyPendingFieldSwitch()
            }
            Button("Cancel") {
                pendingFieldType = nil
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

    private var isPositionMode: Bool {
        guard let playMode else { return false }
        return positionOptions.contains { $0.code == playMode }
    }

    private var isActionMode: Bool {
        guard let playMode else { return false }
        return ["cut", "pass", "pick"].contains(playMode)
    }

    private var phoneLayout: some View {
        VStack(spacing: 12) {
            playbookSection

            sectionTitle("Whiteboard").padding(.top, 20)
            controlsSection

            fieldView
        }
    }

    private var ipadLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                playbookSection

                sectionTitle("Whiteboard").padding(.top, 20)
                sideColumnControls

                Spacer()
            }
            .frame(width: 220)

            fieldView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Sized to 75% of the screen in both dimensions (same aspect ratio as the
    // screen itself), rather than a UIKit sheet's default sizing.
    private var playbookOverlay: some View {
        let screenSize = UIScreen.main.bounds.size
        return ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showPlaybook = false }

            PlaybookScreen(
                onSelect: { play in
                    loadFromPlaybook(play)
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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playbookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            openPlaybookButton

            // Always reserve this row's height, even with no play loaded, so the
            // Whiteboard controls below never shift up/down depending on state.
            HStack(spacing: 10) {
                updatePlayButton(loadedPlay ?? Play(id: "", name: "", field_type: fieldType))
                saveAsNewButton
            }
            .opacity(loadedPlay == nil ? 0 : 1)
            .allowsHitTesting(loadedPlay != nil)
        }
    }

    private var openPlaybookButton: some View {
        Button {
            showPlaybook = true
        } label: {
            Text("Playbook")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
                .background(Color(white: 0.93))
                .cornerRadius(10)
        }
    }

    private func updatePlayButton(_ play: Play) -> some View {
        Button {
            showUpdateConfirm = true
        } label: {
            Text(updating ? "Updating..." : "Update Play")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(red: 0, green: 0.48, blue: 1))
                .cornerRadius(10)
        }
        .disabled(updating)
        .confirmationDialog(
            "This will overwrite \"\(play.name)\" with the current board. This can't be undone.",
            isPresented: $showUpdateConfirm,
            titleVisibility: .visible
        ) {
            Button("Overwrite \"\(play.name)\"", role: .destructive) {
                Task {
                    updating = true
                    _ = await appState.updatePlay(id: play.id, fieldType: fieldType, pieces: pieces, actions: actions, formation: selectedFormation)
                    updating = false
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var saveAsNewButton: some View {
        Button {
            playNameInput = ""
            showSaveModal = true
        } label: {
            Text("Save as New")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(white: 0.93))
                .cornerRadius(10)
        }
    }

    private func loadFromPlaybook(_ play: Play) {
        load(play: play)
        loadedPlay = play
    }

    private var controlsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                fieldMenu
                formationMenu
            }
            HStack(spacing: 10) {
                positionMenu
                moveMenu
            }
            undoButton
            clearButton
            // Update Play / Save as New above already cover saving once a play is
            // loaded from the Playbook — this redundant Save only applies to a
            // fresh, never-saved board.
            if loadedPlay == nil {
                saveButton
            }
        }
    }

    private var sideColumnControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldMenu
            formationMenu
            HStack(spacing: 10) {
                positionMenu
                moveMenu
            }
            undoButton
            clearButton
            if loadedPlay == nil {
                saveButton
            }
        }
    }

    private var fieldMenu: some View {
        Menu {
            ForEach(["full", "half", "mid"], id: \.self) { type in
                Button(type == "mid" ? "Faceoff" : type.capitalized) { requestFieldChange(type) }
            }
        } label: {
            controlLabel("Field", value: fieldType == "mid" ? "Faceoff" : fieldType.capitalized, active: false)
        }
    }

    private var formationMenu: some View {
        Menu {
            ForEach(formations.keys.sorted(), id: \.self) { name in
                Button(name) { applyFormation(name) }
            }
        } label: {
            controlLabel("Formation", value: selectedFormation ?? "Select", active: false)
        }
    }

    private var positionMenu: some View {
        Menu {
            ForEach(positionOptions, id: \.code) { option in
                Button(option.label) { playMode = option.code }
            }
        } label: {
            let currentLabel = positionOptions.first { $0.code == playMode }?.label
            controlLabel("Position", value: currentLabel ?? "Select", active: isPositionMode)
        }
    }

    private var moveMenu: some View {
        Menu {
            ForEach(["cut", "pass", "pick"], id: \.self) { move in
                Button(move.capitalized) { playMode = move }
            }
        } label: {
            controlLabel("Action", value: isActionMode ? (playMode?.capitalized ?? "Select") : "Select", active: isActionMode)
        }
    }

    private var saveButton: some View {
        Button {
            playNameInput = ""
            showSaveModal = true
        } label: {
            Text("💾 Save")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(red: 0, green: 0.48, blue: 1))
                .cornerRadius(10)
        }
    }

    private var undoButton: some View {
        Button {
            undo()
        } label: {
            Text("↩️ Undo")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(history.isEmpty ? .gray : .primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(white: 0.93))
                .cornerRadius(10)
        }
        .disabled(history.isEmpty)
    }

    private var clearButton: some View {
        Button {
            clearBoard()
        } label: {
            Text("🗑️ Clear")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
        }
        .disabled(pieces.isEmpty && actions.isEmpty)
    }

    private func pushHistory() {
        history.append((pieces, actions))
        if history.count > 30 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        pieces = last.pieces
        actions = last.actions
        selectedFormation = nil
    }

    private func clearBoard() {
        pushHistory()
        pieces = []
        actions = []
        selectedFormation = nil
        loadedPlay = nil
    }

    private func requestFieldChange(_ type: String) {
        guard type != fieldType else { return }
        if pieces.isEmpty && actions.isEmpty {
            fieldType = type
        } else {
            pendingFieldType = type
            showFieldSwitchConfirm = true
        }
    }

    private func applyPendingFieldSwitch() {
        if let pendingFieldType {
            fieldType = pendingFieldType
        }
        pieces = []
        actions = []
        selectedFormation = nil
        loadedPlay = nil
        history = []
        pendingFieldType = nil
    }

    private func controlLabel(_ label: String, value: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundColor(.gray)
            HStack {
                Text(value).font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .foregroundColor(active ? .white : .primary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.green : Color(white: 0.93))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // width:height in real yards for each field view, so the rendered box isn't distorted.
    private func fieldAspectRatio(_ type: String) -> Double {
        switch type {
        case "half": return 60.0 / 55.0
        case "mid": return 60.0 / 30.0
        default: return 60.0 / 110.0
        }
    }

    private func fittedFieldSize(available: CGSize) -> CGSize {
        let ratio = fieldAspectRatio(fieldType)
        let w = available.width
        let h = w / ratio
        if h > available.height {
            let h2 = available.height
            return CGSize(width: h2 * ratio, height: h2)
        }
        return CGSize(width: w, height: h)
    }

    private var fieldView: some View {
        GeometryReader { geo in
            let size = fittedFieldSize(available: geo.size)

            ZStack {
                FieldLinesView(fieldType: fieldType, size: size)

                ForEach(actions) { action in
                    actionPath(action, size: size, color: .black)
                }
                if let drawingAction {
                    actionPath(drawingAction, size: size, color: .black.opacity(0.6))
                }

                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .contentShape(Rectangle())
                    .gesture(fieldDragGesture(size: size))

                ForEach(pieces) { piece in
                    pieceView(piece, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.02, green: 0.47, blue: 0.34))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.98), lineWidth: 2))
            .clipped()
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func pieceView(_ piece: PlayPiece, size: CGSize) -> some View {
        let label = piece.playerType ?? (piece.side == "offense" ? "X" : "O")
        let isDefense = piece.side == "defense"
        let fillColor: Color = isDefense ? .black : Color.white.opacity(0.85)
        let textColor: Color = isDefense ? .white : (piece.side == "offense" ? Color(red: 0.07, green: 0.09, blue: 0.15) : Color(red: 0.98, green: 0.75, blue: 0.14))

        return Circle()
            .fill(fillColor)
            .frame(width: 32, height: 32)
            .overlay(
                Text(label)
                    .font(.system(size: label.count > 1 ? 13 : 18, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            )
            .position(x: piece.x * size.width, y: piece.y * size.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart[piece.id] == nil {
                            pushHistory()
                            dragStart[piece.id] = CGPoint(x: piece.x, y: piece.y)
                        }
                        guard let start = dragStart[piece.id], let idx = pieces.firstIndex(where: { $0.id == piece.id }) else { return }
                        pieces[idx].x = min(max(0, start.x + value.translation.width / size.width), 1)
                        pieces[idx].y = min(max(0, start.y + value.translation.height / size.height), 1)
                    }
                    .onEnded { _ in dragStart[piece.id] = nil }
            )
    }

    private func actionPath(_ action: PlayAction, size: CGSize, color: Color) -> some View {
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

    private func fieldDragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Nothing to place until Position or Action has been picked.
                guard let playMode else { return }
                if fieldDragStartLocation == nil {
                    fieldDragStartLocation = value.startLocation
                }
                if isActionMode {
                    let fx = value.location.x / size.width
                    let fy = value.location.y / size.height
                    if drawingAction == nil {
                        drawingAction = PlayAction(id: newId(), type: playMode, points: [PlayPoint(x: fx, y: fy)])
                    } else {
                        let last = drawingAction!.points.last!
                        let dx = (fx - last.x) * size.width
                        let dy = (fy - last.y) * size.height
                        if sqrt(dx * dx + dy * dy) >= 5 {
                            drawingAction!.points.append(PlayPoint(x: fx, y: fy))
                        }
                    }
                }
            }
            .onEnded { value in
                guard playMode != nil else { return }
                if let drawingAction, drawingAction.points.count > 1 {
                    pushHistory()
                    actions.append(drawingAction)
                } else if isPositionMode, let start = fieldDragStartLocation {
                    let dx = value.location.x - start.x
                    let dy = value.location.y - start.y
                    if sqrt(dx * dx + dy * dy) < 10, let option = positionOptions.first(where: { $0.code == playMode }) {
                        pushHistory()
                        pieces.append(PlayPiece(id: newId(), x: start.x / size.width, y: start.y / size.height, side: option.side, playerType: option.code))
                    }
                }
                drawingAction = nil
                fieldDragStartLocation = nil
            }
    }

    private func applyFormation(_ name: String) {
        guard let formation = formations[name] else { return }
        pushHistory()
        selectedFormation = name
        loadedPlay = nil
        pieces = formation.map { PlayPiece(id: newId(), x: $0.x, y: $0.y, side: "offense", playerType: $0.type) }
    }

    private func load(play: Play) {
        fieldType = play.field_type
        pieces = play.pieces ?? []
        actions = play.actions ?? []
        drawingAction = nil
        selectedFormation = play.formation
    }

    private var saveModal: some View {
        NavigationStack {
            Form {
                TextField("Play name (e.g. 1-4-1 Sweep)", text: $playNameInput)
            }
            .navigationTitle("Save Play")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSaveModal = false
                        switchFieldAfterSave = false
                        pendingFieldType = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : "Save") {
                        Task {
                            saving = true
                            let inserted = await appState.savePlay(name: playNameInput, fieldType: fieldType, pieces: pieces, actions: actions, formation: selectedFormation)
                            saving = false
                            if let inserted {
                                loadedPlay = inserted
                                showSaveModal = false
                                if switchFieldAfterSave {
                                    applyPendingFieldSwitch()
                                    switchFieldAfterSave = false
                                }
                            }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

struct ArrowHead: Shape {
    var angle: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.midX, y: rect.midY)
        let back = CGPoint(x: tip.x - cos(angle) * rect.width, y: tip.y - sin(angle) * rect.width)
        let perp = angle + .pi / 2
        let wing = rect.width * 0.35
        let left = CGPoint(x: back.x + cos(perp) * wing, y: back.y + sin(perp) * wing)
        let right = CGPoint(x: back.x - cos(perp) * wing, y: back.y - sin(perp) * wing)
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}

// All real-world lacrosse field markings, in yards on the full 110x60 field.
// full/half/mid views are just different vertical crops of this same coordinate
// space, so proportions always agree no matter which view is selected.
struct FieldLinesView: View {
    let fieldType: String
    let size: CGSize

    private let totalLength = 110.0 // end line to end line
    private let totalWidth = 60.0 // sideline to sideline
    private let goalLineFromEnd = 15.0
    private let restrainingFromMid = 20.0
    private let boxLineFromSideline = 10.0 // alley/wing/box side line
    private let wingHalfSpan = 10.0 // each wing line extends 10yd each side of midfield
    private let creaseRadiusYards = 3.0 // 9ft
    private let goalWidthYards = 2.0 // 6ft

    private var midfieldY: Double { totalLength / 2 } // 55

    // (start, length) in yards of the vertical slice this field type shows.
    private var window: (start: Double, length: Double) {
        switch fieldType {
        case "half": return (midfieldY, totalLength - midfieldY)
        case "mid": return (midfieldY - 15, 30)
        default: return (0, totalLength)
        }
    }

    private func xPt(_ yard: Double) -> CGFloat { CGFloat(yard / totalWidth) * size.width }
    private func yPt(_ yardAbs: Double) -> CGFloat {
        let win = window
        return CGFloat((yardAbs - win.start) / win.length) * size.height
    }
    private var pointsPerYard: CGFloat { size.width / CGFloat(totalWidth) }

    var body: some View {
        let w = size.width
        let h = size.height

        ZStack {
            hline(y: yPt(midfieldY), w: w)
            hline(y: yPt(midfieldY - restrainingFromMid), w: w)
            hline(y: yPt(midfieldY + restrainingFromMid), w: w)

            vline(x: xPt(boxLineFromSideline), yFrom: yPt(0), yTo: yPt(midfieldY - restrainingFromMid))
            vline(x: xPt(totalWidth - boxLineFromSideline), yFrom: yPt(0), yTo: yPt(midfieldY - restrainingFromMid))
            vline(x: xPt(boxLineFromSideline), yFrom: yPt(midfieldY + restrainingFromMid), yTo: yPt(totalLength))
            vline(x: xPt(totalWidth - boxLineFromSideline), yFrom: yPt(midfieldY + restrainingFromMid), yTo: yPt(totalLength))

            vline(x: xPt(boxLineFromSideline), yFrom: yPt(midfieldY - wingHalfSpan), yTo: yPt(midfieldY + wingHalfSpan))
            vline(x: xPt(totalWidth - boxLineFromSideline), yFrom: yPt(midfieldY - wingHalfSpan), yTo: yPt(midfieldY + wingHalfSpan))

            hline(y: yPt(0), w: w, thickness: 3)
            hline(y: yPt(totalLength), w: w, thickness: 3)

            creaseAndGoal(centerY: goalLineFromEnd)
            creaseAndGoal(centerY: totalLength - goalLineFromEnd)

            centerFaceoffX(armLength: pointsPerYard * 1.2)
        }
        .frame(width: w, height: h)
    }

    private func hline(y: CGFloat, w: CGFloat, thickness: CGFloat = 2) -> some View {
        Rectangle().fill(Color(white: 0.98)).frame(width: w, height: thickness).position(x: w / 2, y: y)
    }

    private func vline(x: CGFloat, yFrom: CGFloat, yTo: CGFloat) -> some View {
        Rectangle().fill(Color(white: 0.98)).frame(width: 2, height: max(0, yTo - yFrom)).position(x: x, y: (yFrom + yTo) / 2)
    }

    private func creaseAndGoal(centerY: Double) -> some View {
        let diameter = CGFloat(creaseRadiusYards * 2) * pointsPerYard
        let goalWidth = CGFloat(goalWidthYards) * pointsPerYard
        let cx = size.width / 2
        let cy = yPt(centerY)
        return ZStack {
            Circle().stroke(Color(white: 0.98), lineWidth: 2).frame(width: diameter, height: diameter).position(x: cx, y: cy)
            Rectangle().fill(Color(white: 0.98)).frame(width: goalWidth, height: 4).position(x: cx, y: cy)
        }
    }

    private func centerFaceoffX(armLength: CGFloat) -> some View {
        let x = xPt(totalWidth / 2)
        let y = yPt(midfieldY)
        return ZStack {
            Rectangle().fill(Color(white: 0.98)).frame(width: armLength, height: 2).rotationEffect(.degrees(45)).position(x: x, y: y)
            Rectangle().fill(Color(white: 0.98)).frame(width: armLength, height: 2).rotationEffect(.degrees(-45)).position(x: x, y: y)
        }
    }
}
