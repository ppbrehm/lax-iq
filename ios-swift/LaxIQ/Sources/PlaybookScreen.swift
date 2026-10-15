import SwiftUI

// Browsable playbook: saved plays grouped by formation, 4 per page (no scrolling —
// prev/next arrows step through pages, including across formations), with a live
// field-preview thumbnail per play.
struct PlaybookScreen: View {
    @EnvironmentObject var appState: AppState
    var onSelect: (Play) -> Void
    var onClose: () -> Void

    @State private var pageIndex = 0

    private var pages: [(formation: String, plays: [Play])] {
        var result: [(formation: String, plays: [Play])] = []
        for formation in playbookFormationOrder {
            let plays = appState.savedPlays.filter { $0.formation == formation }
            guard !plays.isEmpty else { continue }
            let chunks = stride(from: 0, to: plays.count, by: 4).map { Array(plays[$0..<min($0 + 4, plays.count)]) }
            for chunk in chunks {
                result.append((formation: formation, plays: chunk))
            }
        }
        return result
    }

    private var safePageIndex: Int {
        guard !pages.isEmpty else { return 0 }
        return min(pageIndex, pages.count - 1)
    }

    // Formations present among saved plays, in the same order next/previous walk
    // through them (playbookFormationOrder), so the dropdown and the arrows agree.
    private var formationsPresent: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for page in pages where !seen.contains(page.formation) {
            seen.insert(page.formation)
            result.append(page.formation)
        }
        return result
    }

    private func firstPageIndex(for formation: String) -> Int? {
        pages.firstIndex { $0.formation == formation }
    }

    private var formationJumpMenu: some View {
        Menu {
            ForEach(formationsPresent, id: \.self) { formation in
                Button(formation) {
                    if let idx = firstPageIndex(for: formation) {
                        pageIndex = idx
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(formationName(at: safePageIndex)).font(.system(size: 17, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.primary)
        }
    }

    private func formationName(at index: Int) -> String {
        guard pages.indices.contains(index) else { return "" }
        return pages[index].formation
    }

    private func pageSuffix(at index: Int) -> String? {
        guard pages.indices.contains(index) else { return nil }
        let formation = pages[index].formation
        let sameFormationIndices = pages.indices.filter { pages[$0].formation == formation }
        guard let posInFormation = sameFormationIndices.firstIndex(of: index) else { return nil }
        return "Page \(posInFormation + 1) of \(sameFormationIndices.count)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if pages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("📖").font(.system(size: 48))
                    Text("No plays saved yet.").foregroundColor(.secondary)
                }
                Spacer()
            } else {
                pageContent
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Playbook").font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Close", action: onClose)
                    .font(.system(size: 15, weight: .semibold))
            }

            if !pages.isEmpty {
                HStack {
                    Button {
                        pageIndex = max(0, safePageIndex - 1)
                    } label: {
                        Image(systemName: "chevron.left.circle.fill").font(.system(size: 30))
                    }
                    .disabled(safePageIndex == 0)
                    .opacity(safePageIndex == 0 ? 0.3 : 1)

                    // Stacked vertically (rather than sharing a row) so the formation
                    // name's position doesn't shift as either line's text width changes.
                    VStack(spacing: 2) {
                        formationJumpMenu
                        if let suffix = pageSuffix(at: safePageIndex) {
                            Text("Formation: \(suffix)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Text("Playbook: Page \(safePageIndex + 1) of \(pages.count)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        pageIndex = min(pages.count - 1, safePageIndex + 1)
                    } label: {
                        Image(systemName: "chevron.right.circle.fill").font(.system(size: 30))
                    }
                    .disabled(safePageIndex == pages.count - 1)
                    .opacity(safePageIndex == pages.count - 1 ? 0.3 : 1)
                }
            }
        }
        .padding()
        .background(Color(white: 0.96))
    }

    private var pageContent: some View {
        let plays = pages[safePageIndex].plays
        return GeometryReader { geo in
            let spacing: CGFloat = 20
            let cardWidth = (geo.size.width - spacing - 24) / 2
            let cardHeight = (geo.size.height - spacing - 24) / 2

            LazyVGrid(columns: [GridItem(.fixed(cardWidth), spacing: spacing), GridItem(.fixed(cardWidth), spacing: spacing)], spacing: spacing) {
                ForEach(0..<4, id: \.self) { slot in
                    if slot < plays.count {
                        playCard(plays[slot], height: cardHeight)
                    } else {
                        Color.clear.frame(width: cardWidth, height: cardHeight)
                    }
                }
            }
            .padding(12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func playCard(_ play: Play, height: CGFloat) -> some View {
        Button {
            onSelect(play)
        } label: {
            VStack(spacing: 8) {
                PlaybookThumbnail(play: play)
                    .frame(height: height - 28)
                Text(play.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(height: height)
        }
        .buttonStyle(.plain)
    }
}

private let playbookFormationOrder = ["1-4-1", "2-2-2", "2-3-1", "1-3-2", "3-3", "Open Set", "2-1-3"]

private struct PlaybookThumbnail: View {
    let play: Play

    private var ratio: Double {
        switch play.field_type {
        case "half": return 60.0 / 55.0
        case "mid": return 60.0 / 30.0
        default: return 60.0 / 110.0
        }
    }

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
                FieldLinesView(fieldType: play.field_type, size: size)

                ForEach(play.actions ?? []) { action in
                    actionPath(action, size: size)
                }
                ForEach(play.pieces ?? []) { piece in
                    pieceView(piece, size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.02, green: 0.47, blue: 0.34))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.98), lineWidth: 2))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func actionPath(_ action: PlayAction, size: CGSize) -> some View {
        let absPoints = action.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        return ZStack {
            Path { path in
                guard let first = absPoints.first else { return }
                path.move(to: first)
                for pt in absPoints.dropFirst() { path.addLine(to: pt) }
            }
            .stroke(Color.black, style: StrokeStyle(lineWidth: 2, dash: action.type == "pass" ? [6, 5] : []))

            if let last = absPoints.last, let secondLast = absPoints.dropLast().last {
                let angle = atan2(last.y - secondLast.y, last.x - secondLast.x)
                if action.type == "cut" || action.type == "pass" {
                    ArrowHead(angle: angle).fill(Color.black).frame(width: 12, height: 12).position(last)
                } else if action.type == "pick" {
                    Rectangle().fill(Color.black)
                        .frame(width: 14, height: 2)
                        .rotationEffect(.radians(angle + .pi / 2))
                        .position(last)
                }
            }
        }
    }

    private func pieceView(_ piece: PlayPiece, size: CGSize) -> some View {
        let label = piece.playerType ?? (piece.side == "offense" ? "X" : "O")
        let isDefense = piece.side == "defense"
        let fillColor: Color = isDefense ? .black : Color.white.opacity(0.85)
        let textColor: Color = isDefense ? .white : (piece.side == "offense" ? Color(red: 0.07, green: 0.09, blue: 0.15) : Color(red: 0.98, green: 0.75, blue: 0.14))

        return Circle()
            .fill(fillColor)
            .frame(width: 22, height: 22)
            .overlay(
                Text(label)
                    .font(.system(size: label.count > 1 ? 9 : 12, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            )
            .position(x: piece.x * size.width, y: piece.y * size.height)
    }
}
